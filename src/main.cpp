#include "appearance/AppearanceConfig.h"
#include "auth/PamAuthenticator.h"
#include "power/PowerService.h"
#include "power/PowerSession.h"
#include "screen/ScreenManager.h"
#include "session/LockService.h"
#include "session/LockSession.h"
#include "session/dbusnames.h"
#include "wallpaper/WallpaperConfig.h"
#include "wallpaper/WallpaperManager.h"

#include <QCommandLineParser>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusInterface>
#include <QGuiApplication>
#include <QQmlEngine>
#include <QScreen>
#include <QTimer>
#include <QUrl>

#ifdef __GLIBC__
#include <malloc.h>
#endif

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("lumina-lock"));
    QGuiApplication::setOrganizationName(QStringLiteral("lumina"));
    // The lock keeps running until an explicit quit, not until windows close.
    QGuiApplication::setQuitOnLastWindowClosed(false);

    QCommandLineParser parser;
    parser.setApplicationDescription(
        QStringLiteral("Lumina Lock — a minimal, modern Linux lock screen "
                       "(UI & authentication prototype; dde-lock compatible)"));
    parser.addHelpOption();
    parser.addVersionOption();

    const QCommandLineOption wallpaperOpt(
        QStringLiteral("wallpaper"),
        QStringLiteral("Static wallpaper image path."),
        QStringLiteral("file"));
    const QCommandLineOption videoOpt(
        QStringLiteral("video"),
        QStringLiteral("Video wallpaper path (looped, muted)."),
        QStringLiteral("file"));
    const QCommandLineOption posterOpt(
        QStringLiteral("poster"),
        QStringLiteral("Poster/cover image shown before the video starts."),
        QStringLiteral("file"));
    const QCommandLineOption serviceOpt(
        QStringLiteral("pam-service"),
        QStringLiteral("PAM service name to authenticate against (default: login)."),
        QStringLiteral("service"));
    const QCommandLineOption userOpt(
        QStringLiteral("user"),
        QStringLiteral("User to authenticate (default: current user)."),
        QStringLiteral("user"));
    const QCommandLineOption testExitOpt(
        QStringLiteral("test-exit-ms"),
        QStringLiteral("Auto-exit after N ms (smoke testing only)."),
        QStringLiteral("ms"));
    // dde-lock compatible invocation flags.
    const QCommandLineOption daemonOpt(
        QStringLiteral("daemon"),
        QStringLiteral("Run as the resident lock service (start hidden, wait for Show())."));
    const QCommandLineOption lockOpt(
        {QStringLiteral("l"), QStringLiteral("lock")},
        QStringLiteral("Lock the screen now."));
    const QCommandLineOption showUserListOpt(
        QStringLiteral("show-user-list"),
        QStringLiteral("Show the user list (mapped to showing the lock)."));

    parser.addOption(wallpaperOpt);
    parser.addOption(videoOpt);
    parser.addOption(posterOpt);
    parser.addOption(serviceOpt);
    parser.addOption(userOpt);
    parser.addOption(testExitOpt);
    parser.addOption(daemonOpt);
    parser.addOption(lockOpt);
    parser.addOption(showUserListOpt);
    parser.process(app);

    WallpaperManager wallpaper;
    WallpaperConfig wallpaperConfig; // DConfig-backed settings (control-center)
    AppearanceConfig appearanceConfig;
    if (parser.isSet(videoOpt)) {
        wallpaper.setVideo(QUrl::fromLocalFile(parser.value(videoOpt)),
                           parser.isSet(posterOpt)
                               ? QUrl::fromLocalFile(parser.value(posterOpt))
                               : QUrl());
    } else if (parser.isSet(wallpaperOpt)) {
        wallpaper.setStaticImage(QUrl::fromLocalFile(parser.value(wallpaperOpt)));
    } else {
        wallpaperConfig.applyTo(wallpaper);
        // Live reload: pick up control-center changes in the resident lock.
        QObject::connect(&wallpaperConfig, &WallpaperConfig::changed, &wallpaper,
                         [&wallpaperConfig, &wallpaper] { wallpaperConfig.applyTo(wallpaper); });
    }

    PamAuthenticator auth;
    if (parser.isSet(serviceOpt))
        auth.setPamService(parser.value(serviceOpt));

    LockSession session(&auth);
    if (parser.isSet(userOpt))
        session.setUser(parser.value(userOpt));

    // Single-instance is enforced by owning dde-lock's D-Bus name. A second
    // invocation forwards its request to the running instance and exits — the
    // same hand-off dde-lock does for `dde-lock -l` & co.
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerService(LOCK_FRONT_SERVICE)) {
        QDBusInterface ifc(LOCK_FRONT_SERVICE, LOCK_FRONT_PATH, LOCK_FRONT_INTERFACE, bus);
        if (parser.isSet(showUserListOpt))
            ifc.asyncCall(QStringLiteral("ShowUserList"));
        else if (!parser.isSet(daemonOpt))
            ifc.asyncCall(QStringLiteral("Show"));
        return 0;
    }

    // Resident daemon starts hidden and waits for Show() (matches dde-lock's
    // --daemon behaviour); a plain/`-l` launch locks immediately.
    const bool startHidden = parser.isSet(daemonOpt);
    if (startHidden)
        session.setLocked(false);

    LockService lockService(&session); // dde-lock compatible adaptor (child of session)

    // Created before the QML engine on purpose: the `Screens` singleton handed
    // to the engine has to outlive it, and a stack object built first is
    // destroyed last.
    ScreenManager screens;
    QQmlEngine engine;
    screens.setEngine(&engine);

    // The power menu: behaviour here, surface in qml/PowerScreen.qml, both
    // reached from QML through the `Power` singleton.
    PowerSession powerSession;
    powerSession.setLockSession(&session);
    powerSession.setScreenManager(&screens);
    PowerService powerService(&powerSession);

    qmlRegisterSingletonInstance("Lumina", 1, 0, "WallpaperManager", &wallpaper);
    qmlRegisterSingletonInstance("Lumina", 1, 0, "LockSession", &session);
    qmlRegisterSingletonInstance("Lumina", 1, 0, "LockAppearance", &appearanceConfig);
    qmlRegisterSingletonInstance("Lumina", 1, 0, "Screens", &screens);
    qmlRegisterSingletonInstance("Lumina", 1, 0, "Power", &powerSession);
    qmlRegisterSingletonType(QUrl(QStringLiteral("qrc:/qml/Theme.qml")),
                             "Lumina", 1, 0, "Theme");

    // Every screen runs the same surface; which one carries the password field
    // is decided at runtime (see ScreenManager).
    screens.setSurfaceUrl(QUrl(QStringLiteral("qrc:/qml/LockScreen.qml")));
    screens.setPowerUrl(QUrl(QStringLiteral("qrc:/qml/PowerWindow.qml")));

    // Resident service: unlocking hides the surfaces, locking shows them again.
    QObject::connect(&session, &LockSession::lockedChanged, &app, [&screens](bool locked) {
        if (locked)
            screens.showAll();
        else
            screens.hideAll();
    });

#ifdef __GLIBC__
    // Hand the decoder's freed heap back to the OS once it is gone. libavcodec's
    // per-thread frame buffers (16 threads on this 16-core box, one glibc arena
    // each) and the arenas themselves stay resident after the QML Loader
    // destroys the MediaPlayer, so without this the resident lock ratcheted
    // ~55 MB per lock/unlock cycle with a 4K video wallpaper (measured over four
    // cycles: unlocked 622 → 808 MB, locked 773 → 911 MB, still climbing) instead
    // of settling. The trim runs after the loader has had a frame or two to tear
    // the decoder down; with it the unlocked footprint settles at ~460 MB and
    // consecutive cycles stop growing.
    QObject::connect(&session, &LockSession::lockedChanged, &app, [](bool locked) {
        if (locked)
            return;
        QTimer::singleShot(1500, qApp, [] { malloc_trim(0); });
    });
#endif

    // ShowAuth(true) comes from the session (dock, hotkey, …): the prompt
    // belongs on the primary screen unless the user is working elsewhere.
    QObject::connect(&session, &LockSession::showAuthRequested, &app, [&screens] {
        if (QScreen *primary = QGuiApplication::primaryScreen())
            screens.activateAuthForScreen(primary->name());
    });

    QObject::connect(&session, &LockSession::quitRequested, &app, &QCoreApplication::quit);

    // dde-lock compatible surface.
    bus.registerObject(LOCK_FRONT_PATH, &session, QDBusConnection::ExportAdaptors);

    // The power menu's surface. DDE reaches it through the ShutdownFront1
    // .service file, which activates this same binary, so the dock's power
    // button, the launcher's and a session-issued request all land here.
    if (!bus.registerService(POWER_FRONT_SERVICE)) {
        qWarning().noquote() << "Failed to own" << POWER_FRONT_SERVICE << ":"
                             << bus.lastError().message();
    }
    bus.registerObject(POWER_FRONT_PATH, &powerSession, QDBusConnection::ExportAdaptors);

    // Our own control surface (quit / relock for testing).
    if (!bus.registerService(QStringLiteral("org.lumina.Lock"))) {
        qWarning() << "Failed to register D-Bus service org.lumina.Lock:"
                   << bus.lastError().message();
    }
    bus.registerObject(QStringLiteral("/org/lumina/Lock"), &session,
                       QDBusConnection::ExportAllSlots
                           | QDBusConnection::ExportAllSignals
                           | QDBusConnection::ExportAllProperties);

    if (parser.isSet(testExitOpt)) {
        bool ok = false;
        const int ms = parser.value(testExitOpt).toInt(&ok);
        QTimer::singleShot(ok ? ms : 2000, &app, &QCoreApplication::quit);
    }

    screens.start(/*visible=*/!startHidden);
    return app.exec();
}
