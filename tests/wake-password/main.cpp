// Real ScreenManager + LockScreen.qml input regression, on a named offscreen screen.
// Uses dummy key text only; never calls PAM or registers the session lock service.
#include "appearance/AppearanceConfig.h"
#include "auth/PamAuthenticator.h"
#include "power/PowerSession.h"
#include "screen/ScreenManager.h"
#include "session/LockSession.h"
#include "wallpaper/WallpaperManager.h"

#include <DConfig>
#include <QCursor>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QScreen>
#include <QTimer>
#include <cstdio>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc != 2)
        return 1;
    const QString repo = QString::fromLocal8Bit(argv[1]);
    int failures = 0;
    auto check = [&](bool ok, const char *what) {
        std::fprintf(stderr, "  %s %s\n", ok ? "PASS" : "FAIL", what);
        if (!ok)
            ++failures;
    };

    AppearanceConfig appearance;
    auto *config = appearance.findChild<Dtk::Core::DConfig *>();
    if (!config || !config->isValid()
        || !config->keyList().contains(QStringLiteral("wakeFillPassword"))) {
        check(false, "test schema provides wakeFillPassword");
        return 1;
    }
    check(appearance.wakeFillPassword(), "default is enabled");

    ScreenManager screens;
    QCursor::setPos(QGuiApplication::primaryScreen()->geometry().center());
    screens.setWakeFillPassword(false);
    screens.activateAuthForPointerScreen(QStringLiteral("1"));
    check(screens.takePendingText().isEmpty(), "disabled pointer wake carries no text");
    screens.clearAuth();
    screens.setWakeFillPassword(true);
    screens.activateAuthForPointerScreen(QStringLiteral("1"));
    check(screens.takePendingText() == QStringLiteral("1"), "enabled pointer wake carries the key");
    check(screens.takePendingText().isEmpty(), "pending key is consumed exactly once");
    screens.clearAuth();

    PamAuthenticator pam;
    LockSession session(&pam);
    WallpaperManager wallpaper;
    PowerSession power;
    QQmlEngine engine;
    screens.setEngine(&engine);
    screens.setWakeFillPassword(appearance.wakeFillPassword());
    QObject::connect(&appearance, &AppearanceConfig::changed, &screens, [&] {
        screens.setWakeFillPassword(appearance.wakeFillPassword());
    });
    qmlRegisterSingletonInstance("Lumina", 1, 0, "LockAppearance", &appearance);
    qmlRegisterSingletonInstance("Lumina", 1, 0, "LockSession", &session);
    qmlRegisterSingletonInstance("Lumina", 1, 0, "WallpaperManager", &wallpaper);
    qmlRegisterSingletonInstance("Lumina", 1, 0, "Screens", &screens);
    qmlRegisterSingletonInstance("Lumina", 1, 0, "Power", &power);
    qmlRegisterSingletonType(QUrl::fromLocalFile(repo + "/qml/Theme.qml"),
                             "Lumina", 1, 0, "Theme");
    screens.setSurfaceUrl(QUrl::fromLocalFile(repo + "/qml/LockScreen.qml"));
    screens.start();
    screens.setInputGrabbed(false);

    QQuickWindow *window = nullptr;
    for (QWindow *candidate : QGuiApplication::allWindows()) {
        if (candidate->title() == QStringLiteral("Lumina Lock"))
            window = qobject_cast<QQuickWindow *>(candidate);
    }
    if (!window) {
        check(false, "real LockScreen.qml loaded");
        return 1;
    }
    QQuickItem *input = nullptr;
    for (QQuickItem *item : window->findChildren<QQuickItem *>()) {
        if (item->metaObject()->indexOfProperty("echoMode") >= 0)
            input = item;
    }
    if (!input) {
        check(false, "real password TextInput exists");
        return 1;
    }

    QTimer::singleShot(0, &app, [&] {
        auto key = [&](int code, const QString &text = QString(),
                       Qt::KeyboardModifiers modifiers = Qt::NoModifier) {
            QKeyEvent press(QEvent::KeyPress, code, modifiers, text);
            QCoreApplication::sendEvent(window, &press);
            QKeyEvent release(QEvent::KeyRelease, code, modifiers, text);
            QCoreApplication::sendEvent(window, &release);
        };
        for (bool enabled : {true, false, true, false}) {
            config->setValue(QStringLiteral("wakeFillPassword"), enabled);
            check(appearance.wakeFillPassword() == enabled, "configuration reloads live");
            screens.clearAuth();
            key(Qt::Key_1, QStringLiteral("1"));
            check(window->property("isAuthScreen").toBool(), "wake key reveals authentication");
            check(input->hasActiveFocus(), "wake focuses the password field");
            check(input->property("text").toString() == (enabled ? "1" : ""),
                  enabled ? "enabled: wake key is inserted once" : "disabled: wake opens an empty field");
            key(Qt::Key_2, QStringLiteral("2"));
            check(input->property("text").toString() == (enabled ? "12" : "2"),
                  "subsequent password keys are not swallowed");
            key(Qt::Key_Escape);
            check(!window->property("isAuthScreen").toBool()
                      && input->property("text").toString().isEmpty(),
                  "Escape returns to idle and clears the password");
        }
        for (bool enabled : {true, false}) {
            config->setValue(QStringLiteral("wakeFillPassword"), enabled);
            screens.clearAuth();
            check(QMetaObject::invokeMethod(window, "wake", Q_ARG(QVariant, QVariant())),
                  "click/swipe wake path is callable");
            check(window->property("isAuthScreen").toBool()
                      && input->property("text").toString().isEmpty(),
                  "click/swipe opens an empty password field");
        }
        config->setValue(QStringLiteral("wakeFillPassword"), true);
        screens.clearAuth();
        key(Qt::Key_1, QStringLiteral("1"), Qt::ControlModifier);
        check(window->property("isAuthScreen").toBool()
                  && input->property("text").toString().isEmpty(),
              "shortcut wake does not insert a printable character");
        screens.hideAll();
        std::fprintf(stderr, "Failures: %d\n", failures);
        app.exit(failures ? 1 : 0);
    });
    QTimer::singleShot(10000, &app, [&] { app.exit(1); });
    return app.exec();
}
