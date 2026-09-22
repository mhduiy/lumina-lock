#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QString>
#include <QUrl>

class QQmlEngine;
class QKeyEvent;
class QQuickWindow;
class QScreen;
class QTimer;

/**
 * Creates and owns one fullscreen window per physical screen.
 *
 * Every screen runs the *same* surface. Which screen carries the interactive
 * authentication UI (the password field) is a single global choice:
 *
 *   - one screen at a time is "active", and only that screen leaves its Idle
 *     state — it compacts the clock and reveals the password field;
 *   - the active screen is chosen by where the user interacts: a click on a
 *     screen activates that screen, and a key press activates the screen the
 *     pointer is on (the X11 keyboard grab delivers keys to one window, so the
 *     pointer is the only reliable hint of which screen the user is looking
 *     at);
 *   - the keyboard grab follows the active screen, because the grab window is
 *     the one that receives keystrokes.
 *
 * The choice is exposed to QML as the `Screens` singleton
 * (`Screens.authScreenName`, `Screens.activateAuthForScreen()`, …), so the
 * surface itself stays free of any screen-topology logic.
 */
class ScreenManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString authScreenName READ authScreenName NOTIFY authScreenChanged)
    /**
     * Which screen carries the power menu's controls. Every screen shows the
     * menu's dimming — the whole desktop darkens, not just one monitor — but
     * only this one shows anything to press. It follows the pointer.
     */
    Q_PROPERTY(QString powerControlScreenName READ powerControlScreenName NOTIFY powerControlScreenChanged)

public:
    explicit ScreenManager(QObject *parent = nullptr);

    /**
     * The QML engine is handed over after construction on purpose: the
     * singleton instance registered with the engine has to outlive it, and a
     * stack object created *before* the engine is destroyed *after* it.
     */
    void setEngine(QQmlEngine *engine);

    /** The single QML surface every screen runs. */
    void setSurfaceUrl(const QUrl &url) { m_surfaceUrl = url; }

    /** The power menu's own surface (see qml/PowerWindow.qml). */
    void setPowerUrl(const QUrl &url) { m_powerUrl = url; }

    /**
     * Show/hide the power menu's window. It is a window of its own rather than a
     * layer on the lock's: the lock's windows are hidden and re-shown around
     * every unlock, and a surface drawn into one of them inherits whatever state
     * that leaves behind.
     */
    void showPowerMenu();
    void hidePowerMenu();

    /** Name of the screen carrying the authentication UI, empty when none. */
    QString authScreenName() const;

    /** Name of the screen carrying the power menu's controls, empty when none. */
    QString powerControlScreenName() const;

public slots:
    void start(bool visible = true);
    void showAll();
    void hideAll();
    void setInputGrabbed(bool grabbed);

    /**
     * Give the authentication UI to this screen (a click on it, or a
     * session-issued ShowAuth). No-op when that screen is already active, so
     * callers can use it to "make sure".
     */
    Q_INVOKABLE void activateAuthForScreen(const QString &screenName);

    /**
     * Key press path: the keys arrive on whichever window holds the grab, so
     * the screen the user is looking at is derived from the pointer. The first
     * printable character of the wake is carried over to the field that is
     * about to be focused (see takePendingText()).
     */
    Q_INVOKABLE void activateAuthForPointerScreen(const QString &initialText);

    /** Reads and clears the character a keyboard wake wants to hand over. */
    Q_INVOKABLE QString takePendingText();

    /** Drop the active screen (Escape): no screen shows the password field. */
    Q_INVOKABLE void clearAuth();

    /**
     * The pointer moved onto this screen while the menu is up: the controls
     * belong there now. Called from every power window's backdrop, which is why
     * it is a no-op when that screen already has them.
     */
    Q_INVOKABLE void activatePowerForScreen(const QString &screenName);

    /**
     * False from the moment a successful unlock starts its exit animation until
     * the next lock resets the scene: keystrokes in that window belong to the
     * desktop that is about to appear, not to the lock.
     */
    Q_INVOKABLE void setInteractive(bool interactive);

signals:
    /** The screen carrying the authentication UI changed (empty: none). */
    void authScreenChanged();

    /**
     * The screen carrying the power menu's controls changed. dx and dy are the
     * direction from the old screen to the new one, as -1, 0 or 1: the controls
     * leave one screen by the side they arrive on the other, which is what makes
     * the two halves of the handoff read as one panel being carried across.
     */
    void powerControlScreenChanged(const QString &screenName, int dx, int dy);

protected:
    /**
     * Key presses arrive on whichever window holds the X11 grab, but whether a
     * keystroke belongs to the password field depends on where the user is
     * looking, which only the pointer can tell. Installed on every lock window
     * (never application-wide: the same key event is offered to the window, the
     * focused item and its parents in turn).
     */
    bool eventFilter(QObject *watched, QEvent *event) override;

private slots:
    void onScreenAdded(QScreen *screen);
    void onScreenRemoved(QScreen *screen);

private:
    void createWindowForScreen(QScreen *screen);
    void destroyWindowForScreen(QScreen *screen);
    void createPowerWindowForScreen(QScreen *screen);
    void destroyPowerWindowForScreen(QScreen *screen);
    void setPowerControlScreen(QScreen *screen);
    QQuickWindow *windowForScreen(const QScreen *screen) const;
    QScreen *screenByName(const QString &name) const;
    void setAuthScreen(QScreen *screen);
    void chooseGrabWindow();
    void applyKeyboardGrab();
    static QString printableText(const QKeyEvent *event);

    /**
     * Screen geometry and scale changes.
     *
     * Every window here is sized from its screen rather than by the window
     * manager — they are override-redirect, so nothing else will resize them —
     * which means a resolution or scale change leaves them drawing into the size
     * the screen used to have until someone says otherwise. One watcher per
     * screen; both the lock's window and the menu's follow it.
     */
    void watchScreenGeometry(QScreen *screen);
    void onScreenGeometryChanged(QScreen *screen);
    void applyScreenGeometry(QScreen *screen);
    void settleScreenGeometry();

    QQmlEngine *m_engine = nullptr;
    QUrl m_surfaceUrl;
    QUrl m_powerUrl;
    /** One power-menu window per screen: all of them dim, one of them has the
     *  controls. */
    QHash<QScreen *, QPointer<QQuickWindow>> m_powerWindows;
    /** Screen carrying the power menu's controls; nullptr while it is down. */
    QScreen *m_powerControlScreen = nullptr;
    QHash<QScreen *, QQuickWindow *> m_windows;
    /** Screen carrying the password field; nullptr while the lock is idle. */
    QScreen *m_authScreen = nullptr;
    /** Window holding the X11 keyboard grab, and the keys with it. */
    QPointer<QQuickWindow> m_grabWindow;
    QString m_pendingText;
    int m_grabRetries = 0;
    /** Screens whose geometry changes are watched. */
    QSet<QScreen *> m_watchedScreens;
    /** Re-asserts the windows' geometry while a screen change settles. */
    QTimer *m_geometrySettleTimer = nullptr;
    int m_geometrySettleTicks = 0;
    bool m_visible = true;
    bool m_grabInput = false;
    bool m_interactive = true;
};
