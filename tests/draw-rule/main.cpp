// 抽签规则单测：直接拿 WallpaperConfig + WallpaperManager 抽多次，验证
//   * 抽中的永远是真实存在的文件（失效条目被过滤，且从未被抽中）
//   * 连续两次不会抽到同一个（"不连续重复"）
//   * 池里只有 1 个时始终抽它
//   * 池空 / 全失效时回退内置静态壁纸（不是视频）
//
// 只依赖 QtCore + Dtk6Core，不碰 GUI。池由 run.sh 通过 DConfig 写进沙箱。
// 期望值从 DConfig 的原始列表来（不经 WallpaperConfig 的过滤），断言因此更强。
#include "WallpaperConfig.h"
#include "WallpaperManager.h"

#include <DConfig>

#include <QCoreApplication>
#include <QFileInfo>
#include <QSet>
#include <QStringList>

#include <algorithm>
#include <cstdio>

using namespace Dtk::Core;

namespace {
int failures = 0;

void say(const QString &line)
{
    std::fprintf(stderr, "%s\n", qPrintable(line));
    std::fflush(stderr);
}

void check(bool ok, const QString &what, const QString &detail = QString())
{
    say(QStringLiteral("%1 %2 %3").arg(ok ? QStringLiteral("  PASS") : QStringLiteral("  FAIL"),
                                       what, detail));
    if (!ok)
        ++failures;
}

QString names(const QStringList &paths)
{
    QStringList out;
    for (const QString &p : paths)
        out << p.section(QLatin1Char('/'), -1);
    return out.join(QLatin1Char(' '));
}

QStringList configuredPool(QObject *parent)
{
    DConfig *c = DConfig::create(QStringLiteral("org.lumina.lock"),
                                 QStringLiteral("org.lumina.lock"), QString(), parent);
    if (!c || !c->isValid())
        return QStringList{};
    // 先问 keyList()：dtk6 直接读 meta 里没有的键会空指针崩溃（就是产品代码里那个坑，
    // 测试自己也得绕开）。
    const QString key = QStringLiteral("videoPaths");
    if (!c->keyList().contains(key))
        return QStringList{};
    return c->value(key).toStringList();
}

QStringList existingOnly(const QStringList &paths)
{
    QStringList out;
    for (const QString &p : paths)
        if (QFileInfo(p).isFile() && QFileInfo(p).isReadable())
            out << p;
    return out;
}

QStringList draw(WallpaperConfig &cfg, WallpaperManager &wm, int times)
{
    QStringList out;
    for (int i = 0; i < times; ++i) {
        cfg.pickForNewLock(wm);
        out << wm.source().toLocalFile();
    }
    return out;
}
} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const QString mode = argc > 1 ? QString::fromLocal8Bit(argv[1]) : QStringLiteral("multi");

    WallpaperManager wm;
    WallpaperConfig cfg;
    const QStringList raw = configuredPool(&app);
    const QStringList good = existingOnly(raw);
    say(QStringLiteral("模式=%1  配置里 %2 条，其中真实存在 %3 条 [%4]")
            .arg(mode).arg(raw.size()).arg(good.size()).arg(names(good)));

    if (mode == QLatin1String("multi")) {
        const QStringList picked = draw(cfg, wm, 8);
        say(QStringLiteral("抽签结果: %1").arg(names(picked)));

        check(raw.size() == 4 && good.size() == 3, "配置 4 条、可用 3 条（失效条目被过滤）");
        check(std::all_of(picked.cbegin(), picked.cend(),
                          [&good](const QString &p) { return good.contains(p); }),
              "抽中的都是真实存在的文件（失效路径从未被抽中）");
        bool noRepeat = true;
        for (int i = 1; i < picked.size(); ++i)
            if (picked.at(i) == picked.at(i - 1))
                noRepeat = false;
        check(noRepeat, "连续两次不重复（8 次抽签）");
        check(QSet<QString>(picked.cbegin(), picked.cend()).size() > 1, "确实在轮换（不止一个结果）");
        check(wm.isVideo() && wm.type() == QLatin1String("video"), "抽中后处于视频状态",
              QStringLiteral("-> type=%1 isVideo=%2").arg(wm.type()).arg(wm.isVideo()));
    } else if (mode == QLatin1String("single")) {
        const QStringList picked = draw(cfg, wm, 6);
        say(QStringLiteral("抽签结果: %1").arg(names(picked)));
        check(good.size() == 1, "可用条目 1 条");
        check(std::all_of(picked.cbegin(), picked.cend(),
                          [&good](const QString &p) { return good.contains(p); }),
              "没有别的可轮换时始终抽它");
        check(wm.isVideo(), "仍然是视频状态");
    } else if (mode == QLatin1String("empty") || mode == QLatin1String("allgone")) {
        const QStringList picked = draw(cfg, wm, 3);
        say(QStringLiteral("抽签结果: %1").arg(names(picked)));
        check(good.isEmpty(), "没有可用条目（空池 / 全失效）", QStringLiteral("-> %1").arg(good.size()));
        check(!wm.isVideo() && wm.type() == QLatin1String("static"),
              "回退到内置静态壁纸（不是视频）",
              QStringLiteral("-> type=%1").arg(wm.type()));
        check(wm.source().toString().contains(QLatin1String("default.jpg")),
              "回退的是内置默认壁纸", QStringLiteral("-> %1").arg(wm.source().toString()));
    } else if (mode == QLatin1String("oldschema")) {
        // 装的是旧 schema（没有 videoPaths / clockPosition*）时，锁屏必须优雅回退。
        // 这里能跑完本身就是断言：不带默认值读不存在的键会让 dtk6 段错误。
        cfg.applyTo(wm);
        cfg.pickForNewLock(wm);
        say(QStringLiteral("抽签/应用后: type=%1 source=%2").arg(wm.type(), wm.source().toString()));
        check(wm.type() == QLatin1String("static") || wm.type() == QLatin1String("video"),
              QStringLiteral("旧 schema 下没有崩、拿到了一个确定状态"),
              QStringLiteral("-> %1").arg(wm.type()));
        check(!wm.source().toString().isEmpty(), QStringLiteral("拿到了一个确定的壁纸来源"),
              QStringLiteral("-> %1").arg(wm.source().toString()));
    } else {
        say(QStringLiteral("  FAIL 未知模式 %1").arg(mode));
        return 1;
    }

    say(failures == 0 ? QStringLiteral("全部通过")
                      : QStringLiteral("有 %1 项失败").arg(failures));
    return failures == 0 ? 0 : 1;
}
