// 探针：把真的 VideoListDialog.qml 加载起来，用桩 dccData 提供 2 条视频，
// 看列表到底有没有渲染（count / 尺寸）以及有没有 QML 报错。
// 用于「添加了却看不到列表」这类只能靠实际渲染才能定性的问题。
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QTimer>
#include <QUrl>
#include <QVariant>
#include <cstdio>

class StubData : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList videoPaths READ videoPaths NOTIFY videoPathsChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
public:
    explicit StubData(QObject *parent = nullptr) : QObject(parent)
    {
        m_paths << QStringLiteral("/home/u/Videos/aaa.mp4")
                << QStringLiteral("/home/u/Videos/bbb.mp4");
    }
    QStringList videoPaths() const { return m_paths; }
    QString lastError() const { return m_error; }
    Q_INVOKABLE bool addVideo(const QUrl &) { return true; }
    Q_INVOKABLE void removeVideo(const QString &) {}
Q_SIGNALS:
    void videoPathsChanged();
    void lastErrorChanged();
private:
    QStringList m_paths;
    QString m_error;
};

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    StubData stub;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("dccData"), &stub);

    int failures = 0;
    auto say = [&failures](bool ok, const QString &what, const QString &detail = QString()) {
        std::fprintf(stderr, "%s %s %s\n", ok ? "  PASS" : "  FAIL", qPrintable(what),
                     qPrintable(detail));
        std::fflush(stderr);
        if (!ok) ++failures;
    };

    QObject::connect(&engine, &QQmlApplicationEngine::warnings, [&failures](const QList<QQmlError> &ws) {
        for (const QQmlError &w : ws) {
            std::fprintf(stderr, "  QML 警告: %s\n", qPrintable(w.toString()));
            if (w.description().contains(QLatin1String("anchors"))
                || w.description().contains(QLatin1String("Layout")))
                ++failures;
        }
    });

    engine.load(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if (engine.rootObjects().isEmpty()) {
        std::fprintf(stderr, "  FAIL 对话框加载失败\n");
        return 1;
    }

    QTimer::singleShot(1500, [&] {
        QQuickItem *list = nullptr;
        for (QObject *o : engine.rootObjects())
            for (QQuickItem *v : o->findChildren<QQuickItem *>())
                if (QString::fromLatin1(v->metaObject()->className()).contains(QLatin1String("ListView")))
                    list = v;  // 弹窗里只有一个列表
        if (!list) {
            say(false, QStringLiteral("找到了 ListView"));
        } else {
            const int count = list->property("count").toInt();
            say(count == 2, QStringLiteral("列表里有 2 条（桩数据）"),
                QStringLiteral("-> count=%1").arg(count));
            say(list->width() > 0 && list->height() > 0,
                QStringLiteral("列表有可见尺寸（不是 0×0 被挤没）"),
                QStringLiteral("-> %1x%2").arg(int(list->width())).arg(int(list->height())));
        }
        say(failures == 0, failures == 0 ? QStringLiteral("全部通过")
                                        : QStringLiteral("有问题"));
        app.exit(failures == 0 ? 0 : 1);
    });
    return app.exec();
}

#include "main.moc"
