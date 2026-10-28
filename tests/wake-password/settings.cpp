// The real settings Switch page and backend, without starting control-center.
#include "luminalock.h"

#include <DConfig>
#include <QFile>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTest>
#include <QTimer>
#include <cstdio>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc < 2)
        return 1;
    const QString repo = QString::fromLocal8Bit(argv[1]);
    const bool missing = argc > 2 && QString::fromLocal8Bit(argv[2]) == "missing";
    int failures = 0;
    auto check = [&](bool ok, const char *what) {
        std::fprintf(stderr, "  %s %s\n", ok ? "PASS" : "FAIL", what);
        if (!ok)
            ++failures;
    };

    Luminalock data;
    auto *config = data.findChild<Dtk::Core::DConfig *>();
    const QString key = QStringLiteral("wakeFillPassword");
    if (!config || !config->isValid() || config->keyList().contains(key) == missing) {
        check(false, "isolated settings schema matches the test mode");
        return 1;
    }
    check(data.wakeFillPassword(), "settings default is enabled");
    int reloads = 0;
    QObject::connect(&data, &Luminalock::wakeFillPasswordChanged, &app, [&] { ++reloads; });

    // Extract the actual page so handler changes are tested, not copied here.
    QFile source(repo + "/dcc-plugin/qml/LuminalockMain.qml");
    if (!source.open(QIODevice::ReadOnly))
        return 1;
    const QByteArray qml = source.readAll();
    const int start = qml.indexOf("D.Switch {", qml.indexOf("name: \"wakeFillPassword\""));
    const int end = qml.indexOf("\n        }", start);
    if (start < 0 || end < 0)
        return 1;
    QQmlEngine engine;
    engine.rootContext()->setContextProperty("dccData", &data);
    QQmlComponent component(&engine);
    component.setData("import QtQuick\nimport org.deepin.dtk 1.0 as D\n"
                      "Item { id: root; property string selectionError: \"\"\n"
                      + qml.mid(start, end - start + 10) + "\n}",
                      QUrl::fromLocalFile(source.fileName()));
    QQuickWindow window;
    auto *root = qobject_cast<QQuickItem *>(component.create());
    if (!root) {
        for (const QQmlError &error : component.errors())
            std::fprintf(stderr, "%s\n", qPrintable(error.toString()));
        return 1;
    }
    root->setParentItem(window.contentItem());
    root->setSize(QSizeF(140, 80));
    QQuickItem *toggle = nullptr;
    for (QQuickItem *item : root->findChildren<QQuickItem *>()) {
        if (item->metaObject()->indexOfProperty("checkable") >= 0)
            toggle = item;
    }
    if (!toggle)
        return 1;
    toggle->setPosition(QPointF(10, 10));
    toggle->setSize(QSizeF(100, 40));
    window.resize(140, 80);
    window.show();

    QTimer::singleShot(0, &app, [&] {
        check(toggle->property("checked").toBool(), "switch displays the enabled default");
        check(reloads == 0, "opening the switch does not invoke save/reload");
        auto click = [&] {
            QTest::mouseClick(&window, Qt::LeftButton, Qt::NoModifier, QPoint(30, 30));
            QCoreApplication::processEvents();
        };
        if (!missing) {
            data.addVideo(QUrl(QStringLiteral("https://example.invalid/video.mp4")));
            check(!data.lastError().isEmpty(), "an earlier operation has a save error");
        }
        click();
        if (missing) {
            check(data.wakeFillPassword() && toggle->property("checked").toBool(),
                  "unsupported setting does not falsely appear disabled");
            check(!data.lastError().isEmpty()
                      && root->property("selectionError").toString() == data.lastError(),
                  "unsupported setting exposes the save error to the page");
        } else {
            check(!data.wakeFillPassword() && !config->value(key).toBool()
                      && !toggle->property("checked").toBool(),
                  "mouse click saves the disabled setting");
            check(data.lastError().isEmpty() && root->property("selectionError").toString().isEmpty(),
                  "successful setting change clears stale save errors");
            data.resetToDefault();
            QCoreApplication::processEvents();
            check(data.wakeFillPassword() && config->value(key).toBool()
                      && toggle->property("checked").toBool(),
                  "reset restores the enabled setting and switch");
            toggle->forceActiveFocus();
            QTest::keyClick(&window, Qt::Key_Space);
            check(!data.wakeFillPassword() && !toggle->property("checked").toBool(),
                  "keyboard toggle saves the disabled setting");
            config->setValue(key, true);
            QCoreApplication::processEvents();
            check(data.wakeFillPassword() && toggle->property("checked").toBool(),
                  "configuration notification refreshes the settings switch");
            config->setValue(key, false);
            QCoreApplication::processEvents();
            check(!data.wakeFillPassword() && !toggle->property("checked").toBool(),
                  "configuration notifications also refresh disabled state");
        }
        std::fprintf(stderr, "Settings failures: %d\n", failures);
        app.exit(failures ? 1 : 0);
    });
    QTimer::singleShot(10000, &app, [&] { app.exit(1); });
    return app.exec();
}
