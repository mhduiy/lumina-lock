#include "auth/PamAuthenticator.h"
#include "screen/ScreenManager.h"
#include "session/LockSession.h"
#include "wallpaper/WallpaperManager.h"

#include <QCommandLineParser>
#include <QGuiApplication>
#include <QQmlEngine>
#include <QTimer>
#include <QUrl>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("lumina-lock"));
    QGuiApplication::setOrganizationName(QStringLiteral("lumina"));
    // The lock keeps running until an explicit unlock, not until windows close.
    QGuiApplication::setQuitOnLastWindowClosed(false);

    QCommandLineParser parser;
    parser.setApplicationDescription(
        QStringLiteral("Lumina Lock — a minimal, modern Linux lock screen "
                       "(UI & authentication prototype)"));
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

    parser.addOption(wallpaperOpt);
    parser.addOption(videoOpt);
    parser.addOption(posterOpt);
    parser.addOption(serviceOpt);
    parser.addOption(userOpt);
    parser.addOption(testExitOpt);
    parser.process(app);

    WallpaperManager wallpaper;
    if (parser.isSet(videoOpt)) {
        wallpaper.setVideo(QUrl::fromLocalFile(parser.value(videoOpt)),
                           parser.isSet(posterOpt)
                               ? QUrl::fromLocalFile(parser.value(posterOpt))
                               : QUrl());
    } else if (parser.isSet(wallpaperOpt)) {
        wallpaper.setStaticImage(QUrl::fromLocalFile(parser.value(wallpaperOpt)));
    } else {
        wallpaper.setStaticImage(QUrl(QStringLiteral("qrc:/assets/wallpapers/default.jpg")));
    }

    PamAuthenticator auth;
    if (parser.isSet(serviceOpt))
        auth.setPamService(parser.value(serviceOpt));

    LockSession session(&auth);
    if (parser.isSet(userOpt))
        session.setUser(parser.value(userOpt));

    QQmlEngine engine;

    qmlRegisterSingletonInstance("Lumina", 1, 0, "WallpaperManager", &wallpaper);
    qmlRegisterSingletonInstance("Lumina", 1, 0, "LockSession", &session);
    qmlRegisterSingletonType(QUrl(QStringLiteral("qrc:/qml/Theme.qml")),
                             "Lumina", 1, 0, "Theme");

    ScreenManager screens(&engine);
    screens.setPrimaryUrl(QUrl(QStringLiteral("qrc:/qml/LockScreen.qml")));
    screens.setSecondaryUrl(QUrl(QStringLiteral("qrc:/qml/SecondaryScreen.qml")));

    QObject::connect(&session, &LockSession::unlocked, &app, [&screens, &app]() {
        screens.shutdown();
        app.quit();
    });

    if (parser.isSet(testExitOpt)) {
        bool ok = false;
        const int ms = parser.value(testExitOpt).toInt(&ok);
        QTimer::singleShot(ok ? ms : 2000, &app, &QCoreApplication::quit);
    }

    screens.start();
    return app.exec();
}
