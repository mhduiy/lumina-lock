// 回归测试：控制中心「添加视频」这条路径（插件后端 Luminalock）。
//
// 覆盖的坑：dtk6 的 DConfig::setValue() 返回 void，而键不在当前 schema 里时守护进程会
// *静默*拒掉写入 —— 从界面上看就是"选完视频，对话框里没有记录"。所以这里既断言成功
// 路径（列表里真有这一条、类型切到 video-random），也断言失败路径必须给出 lastError，
// 不能假装成功。
//
// 单独编译，不需要控制中心在跑；配置在沙箱里，见 run.sh。
#include "luminalock.h"

#include <QCoreApplication>
#include <QUrl>

#include <cstdio>

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
} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const QString mode = argc > 1 ? QString::fromLocal8Bit(argv[1]) : QStringLiteral("add-ok");
    const QString video = argc > 2 ? QString::fromLocal8Bit(argv[2]) : QString();
    const QUrl url = QUrl::fromLocalFile(video);

    Luminalock data;
    say(QStringLiteral("模式=%1  文件=%2").arg(mode, video));

    if (mode == QLatin1String("add-ok")) {
        check(data.addVideo(url), QStringLiteral("addVideo 返回成功"));
        check(data.videoPaths().contains(video), QStringLiteral("列表里有这一条"),
              QStringLiteral("-> [%1]").arg(data.videoPaths().join(QLatin1Char(','))));
        check(data.wallpaperType() == QLatin1String("video-random"),
              QStringLiteral("类型自动切到 video-random"),
              QStringLiteral("-> %1").arg(data.wallpaperType()));
        check(data.lastError().isEmpty(), QStringLiteral("没有错误信息"), data.lastError());
    } else if (mode == QLatin1String("read-back")) {
        // 另一个进程：列表必须真的落盘了
        check(data.videoPaths().contains(video), QStringLiteral("新进程读回列表里有这一条"),
              QStringLiteral("-> [%1]").arg(data.videoPaths().join(QLatin1Char(','))));
        check(data.wallpaperType() == QLatin1String("video-random"),
              QStringLiteral("新进程读回类型是 video-random"),
              QStringLiteral("-> %1").arg(data.wallpaperType()));
    } else if (mode == QLatin1String("add-then-remove")) {
        check(data.addVideo(url), QStringLiteral("先添加成功"));
        data.removeVideo(video);
        check(!data.videoPaths().contains(video), QStringLiteral("删掉后列表里没有了"),
              QStringLiteral("-> [%1]").arg(data.videoPaths().join(QLatin1Char(','))));
        check(data.wallpaperType() == QLatin1String("none"),
              QStringLiteral("删空后回退默认壁纸类型"),
              QStringLiteral("-> %1").arg(data.wallpaperType()));
    } else if (mode == QLatin1String("add-nokey")) {
        // schema 里没有 videoPaths（用户机器上的真实状态）：必须明确失败，不能静默
        check(!data.addVideo(url),
              QStringLiteral("schema 缺 videoPaths 时 addVideo 返回失败（不假装成功）"));
        check(!data.lastError().isEmpty(), QStringLiteral("给出错误原因"), data.lastError());
        check(data.lastError().contains(QLatin1String("videoPaths")),
              QStringLiteral("原因指向缺失的配置项"), data.lastError());
        check(data.videoPaths().isEmpty(), QStringLiteral("列表确实没变"),
              QStringLiteral("-> [%1]").arg(data.videoPaths().join(QLatin1Char(','))));
    } else if (mode == QLatin1String("add-badfile")) {
        check(!data.addVideo(url), QStringLiteral("读不了的文件必须失败"));
        check(!data.lastError().isEmpty(), QStringLiteral("给出错误原因"), data.lastError());
    } else {
        say(QStringLiteral("  FAIL 未知模式 %1").arg(mode));
        return 1;
    }

    say(failures == 0 ? QStringLiteral("全部通过")
                      : QStringLiteral("有 %1 项失败").arg(failures));
    return failures == 0 ? 0 : 1;
}
