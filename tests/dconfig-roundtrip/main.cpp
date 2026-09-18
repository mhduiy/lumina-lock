// 沙箱里真跑一遍 org.lumina.lock 的 DConfig 读写：验证「控制中心加视频 → 锁屏能抽到」
// 这条链路的存储环节。不碰系统目录、不碰用户真实配置（HOME / DSG_DATA_DIRS 都指向沙箱）。
//
// 用法见 tests/dconfig-roundtrip/run.sh（写和读分成两个进程，和真机上「控制中心写、
// 锁屏读」一致；DConfig 的值是退出时才落盘的，同进程内新建实例读不到）。
//
// 两个实现细节：
//   * 输出用 fprintf 而不是 qInfo —— libdtk6core 装了日志处理器，会把 Qt 日志重定向走，
//     终端上看不到。
//   * dtk6 的 setValue() 返回 void，写没写进去只能靠重新读回来判断。
#include <DConfig>

#include <QCoreApplication>
#include <QStringList>

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

DConfig *open(QObject *parent)
{
    return DConfig::create(QStringLiteral("org.lumina.lock"),
                           QStringLiteral("org.lumina.lock"), QString(), parent);
}

QString list(const QVariant &v)
{
    return QStringLiteral("[%1]").arg(v.toStringList().join(QLatin1Char(',')));
}
} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const QString mode = argc > 1 ? QString::fromLocal8Bit(argv[1]) : QStringLiteral("defaults");

    DConfig *cfg = open(&app);
    if (!cfg || !cfg->isValid()) {
        say(QStringLiteral("  FAIL DConfig 不可用（schema 没找到？）"));
        return 1;
    }

    const QString kPool = QStringLiteral("videoPaths");
    const QString kType = QStringLiteral("wallpaperType");
    const QString kAlignX = QStringLiteral("clockPositionX");
    const QString kAlignY = QStringLiteral("clockPositionY");

    if (mode == QLatin1String("defaults")) {
        // 全新沙箱：没写过任何值时，schema 默认值要能读出来。
        say(QStringLiteral("schema 默认值:"));
        check(cfg->value(kPool).toStringList().isEmpty(), QStringLiteral("videoPaths 默认空列表"),
              list(cfg->value(kPool)));
        check(cfg->value(kAlignX).toInt() == 50, QStringLiteral("clockPositionX 默认 50"),
              QStringLiteral("-> %1").arg(cfg->value(kAlignX).toInt()));
        check(cfg->value(kType).toString() == QLatin1String("none"),
              QStringLiteral("wallpaperType 默认 none"),
              QStringLiteral("-> %1").arg(cfg->value(kType).toString()));
    } else if (mode == QLatin1String("write")) {
        // 控制中心「添加视频」+ 调取景 + 选类型，写的就是这几条。
        say(QStringLiteral("写入（模拟控制中心操作）:"));
        const QStringList pool{QStringLiteral("/tmp/a.mp4"), QStringLiteral("/tmp/b.mp4"),
                               QStringLiteral("/tmp/c.mp4")};
        cfg->setValue(kPool, pool);
        cfg->setValue(kAlignX, 30);
        cfg->setValue(kAlignY, 70);
        cfg->setValue(kType, QStringLiteral("video-random"));
        check(true, QStringLiteral("已写入 3 个视频路径 / 取景 30,70 / 类型 video-random"));
    } else if (mode == QLatin1String("read")) {
        say(QStringLiteral("另一个进程读回:"));
        const QStringList expect{QStringLiteral("/tmp/a.mp4"), QStringLiteral("/tmp/b.mp4"),
                                 QStringLiteral("/tmp/c.mp4")};
        check(cfg->value(kPool).toStringList() == expect, QStringLiteral("videoPaths 一致"),
              list(cfg->value(kPool)));
        check(cfg->value(kAlignX).toInt() == 30 && cfg->value(kAlignY).toInt() == 70,
              QStringLiteral("取景 30 / 70 一致"),
              QStringLiteral("-> %1 / %2").arg(cfg->value(kAlignX).toInt())
                  .arg(cfg->value(kAlignY).toInt()));
        check(cfg->value(kType).toString() == QLatin1String("video-random"),
              QStringLiteral("类型 video-random 一致"),
              QStringLiteral("-> %1").arg(cfg->value(kType).toString()));
    } else if (mode == QLatin1String("align")) {
        // 只改取景值：用来触发锁屏的 live reload（changed() → applyTo → 再抽一次签）
        const int x = argc > 2 ? QString::fromLocal8Bit(argv[2]).toInt() : 50;
        cfg->setValue(kAlignX, x);
        say(QStringLiteral("已写入 clockPositionX=%1").arg(x));
    } else if (mode == QLatin1String("write-args")) {
        // 用库来配置沙箱：probe write-args <type> <video...>
        const QString type = argc > 2 ? QString::fromLocal8Bit(argv[2]) : QStringLiteral("none");
        QStringList pool;
        for (int i = 3; i < argc; ++i)
            pool << QString::fromLocal8Bit(argv[i]);
        cfg->setValue(kPool, pool);
        cfg->setValue(kType, type);
        say(QStringLiteral("已写入 type=%1, %2 个视频").arg(type).arg(pool.size()));
    } else if (mode == QLatin1String("clear")) {
        // 「删到空」/「重置默认」走的是空列表。
        say(QStringLiteral("清空列表（模拟删到空 / 重置）:"));
        cfg->setValue(kPool, QStringList());
        check(true, QStringLiteral("已写入空列表"));
    } else if (mode == QLatin1String("read-clear")) {
        say(QStringLiteral("另一个进程读回:"));
        check(cfg->value(kPool).toStringList().isEmpty(), QStringLiteral("videoPaths 为空"),
              list(cfg->value(kPool)));
        check(cfg->value(kAlignX).toInt() == 30, QStringLiteral("位置值不受影响"),
              QStringLiteral("-> %1").arg(cfg->value(kAlignX).toInt()));
    } else {
        say(QStringLiteral("  FAIL 未知模式 %1").arg(mode));
        return 1;
    }

    say(failures == 0 ? QStringLiteral("全部通过")
                      : QStringLiteral("有 %1 项失败").arg(failures));
    return failures == 0 ? 0 : 1;
}
