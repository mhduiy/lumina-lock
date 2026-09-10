#pragma once

#include <QHash>
#include <QObject>
#include <QUrl>

class QQmlEngine;
class QQuickWindow;
class QScreen;

/**
 * Creates and owns one fullscreen window per physical screen.
 *
 * The primary screen hosts the full lock UI (clock + authentication); every
 * additional screen hosts a lightweight wallpaper-only surface so that no
 * area of the desktop is left uncovered and — importantly — video wallpaper
 * decoding is not duplicated per screen.
 */
class ScreenManager : public QObject
{
    Q_OBJECT

public:
    explicit ScreenManager(QQmlEngine *engine, QObject *parent = nullptr);

    void setPrimaryUrl(const QUrl &url) { m_primaryUrl = url; }
    void setSecondaryUrl(const QUrl &url) { m_secondaryUrl = url; }

    QQuickWindow *primaryWindow() const { return m_primaryWindow; }

public slots:
    void start();
    void shutdown();

private slots:
    void onScreenAdded(QScreen *screen);
    void onScreenRemoved(QScreen *screen);

private:
    void createWindowForScreen(QScreen *screen);
    void destroyWindowForScreen(QScreen *screen);

    QQmlEngine *m_engine = nullptr;
    QUrl m_primaryUrl;
    QUrl m_secondaryUrl;
    QHash<QScreen *, QQuickWindow *> m_windows;
    QQuickWindow *m_primaryWindow = nullptr;
};
