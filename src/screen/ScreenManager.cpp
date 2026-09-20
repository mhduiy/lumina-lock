#include "ScreenManager.h"

#include <QCursor>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QScreen>
#include <QTimer>
#include <QDebug>

#include <xcb/xproto.h>

#include <cstdlib>
#include <cstring>
#include <utility>

namespace {

// dde-lock parity: the deepin window manager special-cases windows that carry
// these X11 properties — keeps them on top / focused while the screen is
// locked and plays the lock-start animation (value 16 == LOCK_START_EFFECT).
xcb_atom_t internAtom(xcb_connection_t *connection, const char *name)
{
    xcb_intern_atom_cookie_t cookie =
        xcb_intern_atom(connection, false, static_cast<uint16_t>(std::strlen(name)), name);
    xcb_intern_atom_reply_t *reply = xcb_intern_atom_reply(connection, cookie, nullptr);
    if (!reply)
        return XCB_NONE;
    const xcb_atom_t atom = reply->atom;
    std::free(reply);
    return atom;
}

void markAsLockWindow(QQuickWindow *window)
{
    QNativeInterface::QX11Application *x11 =
        qGuiApp->nativeInterface<QNativeInterface::QX11Application>();
    if (!x11)
        return; // Wayland: no X11 lock-screen integration
    xcb_connection_t *connection = x11->connection();
    if (!connection)
        return;

    const xcb_window_t wid = static_cast<xcb_window_t>(window->winId());
    xcb_atom_t lockScreen = internAtom(connection, "_DEEPIN_LOCK_SCREEN");
    xcb_change_property(connection, XCB_PROP_MODE_REPLACE, wid, lockScreen,
                        XCB_ATOM_ATOM, 32, 1, &lockScreen);
    const quint32 startupEffect = 16; // LOCK_START_EFFECT (dde-lock)
    xcb_atom_t startup = internAtom(connection, "_DEEPIN_NET_STARTUP");
    xcb_change_property(connection, XCB_PROP_MODE_REPLACE, wid, startup,
                        XCB_ATOM_CARDINAL, 32, 1, &startupEffect);
    xcb_flush(connection);
}

// The X11 grab is refused until the window is actually viewable, which is only
// true a round trip or two after showFullScreen(). Retry a bounded number of
// times instead of dropping the grab for good on the first refusal.
constexpr int kMaxGrabRetries = 10;
constexpr int kGrabRetryIntervalMs = 120;

} // namespace

ScreenManager::ScreenManager(QObject *parent)
    : QObject(parent)
{
    // Key handling is a per-window event filter; see createWindowForScreen()
    // and eventFilter() for why it must not be installed application-wide.
}

void ScreenManager::setEngine(QQmlEngine *engine)
{
    m_engine = engine;
}

QString ScreenManager::authScreenName() const
{
    return m_authScreen ? m_authScreen->name() : QString();
}

void ScreenManager::start(bool visible)
{
    m_visible = visible;
    const QList<QScreen *> screens = QGuiApplication::screens();
    for (QScreen *screen : screens)
        createWindowForScreen(screen);

    connect(qGuiApp, &QGuiApplication::screenAdded,
            this, &ScreenManager::onScreenAdded);
    connect(qGuiApp, &QGuiApplication::screenRemoved,
            this, &ScreenManager::onScreenRemoved);

    // Somewhere for the keys to land while the lock is idle: the screen that
    // carries the authentication UI takes them over as soon as one is chosen.
    chooseGrabWindow();
    if (m_visible)
        setInputGrabbed(true);
}

void ScreenManager::showAll()
{
    m_visible = true;
    for (QQuickWindow *window : std::as_const(m_windows)) {
        window->showFullScreen();
        window->raise();
        window->requestActivate();
        // A window that was hidden and is mapped again does not necessarily get
        // painted: Qt drops the scene graph when a window is hidden, and the
        // rebuild is not guaranteed until something asks for a frame. Without
        // this the surface is up, mapped, and shows nothing.
        window->requestUpdate();
    }
    chooseGrabWindow();
    setInputGrabbed(true);

    // The state each surface ended up in. "Shown but never mapped" and "mapped
    // but never painted" look identical from the outside, and the caller that
    // asked for them has no other way to tell which one it got.
    for (QQuickWindow *window : std::as_const(m_windows)) {
        qWarning().nospace() << "ScreenManager: showAll window visible=" << window->isVisible()
                             << " visibility=" << static_cast<int>(window->visibility())
                             << " exposed=" << window->isExposed()
                             << " bypassWM=" << bool(window->flags() & Qt::X11BypassWindowManagerHint)
                             << " geometry=" << window->geometry().width() << "x"
                             << window->geometry().height();
    }
}

void ScreenManager::createPowerWindowForScreen(QScreen *screen)
{
    if (!screen || m_powerWindows.contains(screen))
        return;
    if (m_powerUrl.isEmpty() || !m_engine) {
        qWarning() << "ScreenManager: no power surface configured";
        return;
    }

    QQmlComponent component(m_engine, m_powerUrl, this);
    if (component.isError()) {
        qWarning().noquote() << "ScreenManager: failed to load" << m_powerUrl.toString();
        const auto errors = component.errors();
        for (const QQmlError &error : errors)
            qWarning().noquote() << "  " << error.toString();
        return;
    }

    QQuickWindow *window = qobject_cast<QQuickWindow *>(component.create());
    if (!window) {
        qWarning().noquote() << "ScreenManager: root of" << m_powerUrl.toString()
                             << "is not a Window";
        return;
    }

    // Flags and colour are declared in qml/PowerWindow.qml so that they are in
    // place before any native window exists; setting them here would recreate
    // the native window and race the mapping.
    //
    // Sized from the screen the way the lock's windows are: a window that is
    // only asked to go fullscreen keeps whatever geometry it was created with
    // until the window manager answers, and until then the menu draws into a
    // 160x160 corner.
    window->setScreen(screen);
    window->setGeometry(screen->geometry());
    window->installEventFilter(this);
    m_powerWindows.insert(screen, window);
}

void ScreenManager::destroyPowerWindowForScreen(QScreen *screen)
{
    auto it = m_powerWindows.find(screen);
    if (it == m_powerWindows.end())
        return;

    QQuickWindow *window = it.value();
    m_powerWindows.erase(it);
    if (window == m_grabWindow)
        m_grabWindow = nullptr;
    if (window)
        window->deleteLater();
}

QString ScreenManager::powerControlScreenName() const
{
    return m_powerControlScreen ? m_powerControlScreen->name() : QString();
}

void ScreenManager::setPowerControlScreen(QScreen *screen)
{
    if (screen == m_powerControlScreen)
        return;

    QScreen *previous = m_powerControlScreen;
    m_powerControlScreen = screen;

    // The direction from the old screen to the new one. Only the sign matters:
    // each surface multiplies it by its own travel. The side the controls leave
    // by on one screen is the side they arrive by on the other.
    int dx = 0;
    int dy = 0;
    if (previous && screen) {
        dx = screen->geometry().x() - previous->geometry().x();
        dy = screen->geometry().y() - previous->geometry().y();
        dx = dx == 0 ? 0 : (dx > 0 ? 1 : -1);
        dy = dy == 0 ? 0 : (dy > 0 ? 1 : -1);
    }

    emit powerControlScreenChanged(powerControlScreenName(), dx, dy);

    // The keys follow the controls, the same way they follow the password field.
    if (QQuickWindow *window = m_powerWindows.value(screen)) {
        m_grabWindow = window;
        m_grabInput = true;
        applyKeyboardGrab();
    }

    qWarning().nospace() << "ScreenManager: power controls on " << powerControlScreenName()
                         << " direction " << dx << "," << dy;
}

void ScreenManager::activatePowerForScreen(const QString &screenName)
{
    setPowerControlScreen(screenByName(screenName));
}

void ScreenManager::showPowerMenu()
{
    // A window per screen, so the whole desktop dims rather than one monitor,
    // and so the controls can be carried from one to another. Only the screen
    // under the pointer draws anything to press.
    const QList<QScreen *> screens = QGuiApplication::screens();
    for (QScreen *screen : screens)
        createPowerWindowForScreen(screen);

    for (QQuickWindow *window : std::as_const(m_powerWindows)) {
        window->showFullScreen();
        window->raise();
        window->requestActivate();
        // A window that was hidden and is mapped again does not necessarily get
        // painted; without this it is up, mapped, and shows nothing.
        window->requestUpdate();
    }

    QScreen *control = QGuiApplication::screenAt(QCursor::pos());
    if (!control)
        control = m_authScreen ? m_authScreen : QGuiApplication::primaryScreen();
    setPowerControlScreen(control);

    qWarning().nospace() << "ScreenManager: showPowerMenu windows=" << m_powerWindows.size()
                         << " controls=" << powerControlScreenName();
}

void ScreenManager::hidePowerMenu()
{
    // Give the keyboard back to the lock before taking the menu away. The menu
    // took the grab when it opened and the lock is still up behind it, and the
    // lock's windows are unmanaged — the grab is the only way they ever see a
    // keystroke — so leaving it unheld means the password field silently stops
    // accepting input the moment the menu is dismissed.
    m_grabInput = false;
    applyKeyboardGrab(); // releases on the power window, which still holds it
    m_grabWindow = nullptr;
    chooseGrabWindow(); // one of the lock's own windows again
    m_grabInput = m_visible;
    applyKeyboardGrab();

    // Destroyed rather than hidden: they are mapped onto specific screens, and
    // the screens can change between one showing and the next.
    const auto windows = m_powerWindows;
    m_powerWindows.clear();
    m_powerControlScreen = nullptr;
    for (QQuickWindow *window : windows) {
        if (!window)
            continue;
        window->hide();
        window->deleteLater();
    }

    qWarning().nospace() << "ScreenManager: hidePowerMenu visible=" << m_visible
                         << " grabWindow="
                         << (m_grabWindow ? m_grabWindow->title() : QStringLiteral("none"))
                         << " grabbed=" << m_grabInput;
}

void ScreenManager::hideAll()
{
    qWarning().nospace() << "ScreenManager: hideAll windows=" << m_windows.size();
    for (QQuickWindow *window : std::as_const(m_windows)) {
        qWarning().nospace() << "ScreenManager: hideAll window visible=" << window->isVisible()
                             << " visibility=" << static_cast<int>(window->visibility());
    }
    m_visible = false;
    // Release before hiding. Unmapping a window implicitly drops its grabs, but
    // being explicit guarantees the desktop is usable even if a hide is missed.
    setInputGrabbed(false);
    // The next lock starts from Idle on every screen; the surfaces stay alive.
    setAuthScreen(nullptr);
    for (QQuickWindow *window : std::as_const(m_windows))
        window->hide();

    // Logged *after* the hide, on purpose: the state before it says nothing
    // about whether the surfaces actually went away, and "still visible here"
    // is exactly what an empty window left over the desktop looks like.
    for (QQuickWindow *window : std::as_const(m_windows)) {
        qWarning().nospace() << "ScreenManager: hideAll after visible=" << window->isVisible()
                             << " visibility=" << static_cast<int>(window->visibility());
    }
}

void ScreenManager::setInputGrabbed(bool grabbed)
{
    m_grabInput = grabbed;
    applyKeyboardGrab();
}

void ScreenManager::applyKeyboardGrab()
{
    if (!m_grabWindow)
        chooseGrabWindow();
    if (!m_grabWindow)
        return;

    if (!m_grabInput) {
        m_grabWindow->setKeyboardGrabEnabled(false);
        m_grabRetries = 0;
        return;
    }

    // Only the keyboard is grabbed, and only on the screen that carries the
    // password field. The keyboard grab is what keeps the window-manager
    // shortcuts (Alt+Tab, Super, …) from switching away from the lock, and it
    // has to sit on the window that owns the focused password field — X
    // delivers grabbed keys to that one window.
    //
    // The pointer is deliberately *not* grabbed: with one window per screen
    // every screen covers its own area, so clicks already land on the lock, and
    // a pointer grab would funnel every click into the grab window — which is
    // exactly what would stop "click the screen you are looking at" from
    // working.
    if (m_grabWindow->setKeyboardGrabEnabled(true)) {
        m_grabRetries = 0;
        return;
    }

    if (++m_grabRetries > kMaxGrabRetries) {
        qWarning() << "ScreenManager: keyboard grab refused (X11-only feature)"
                   << "- giving up after" << kMaxGrabRetries << "attempts";
        m_grabRetries = 0;
        return;
    }
    QTimer::singleShot(kGrabRetryIntervalMs, this, [this] {
        if (m_grabInput)
            applyKeyboardGrab();
    });
}

void ScreenManager::activateAuthForScreen(const QString &screenName)
{
    setAuthScreen(screenByName(screenName));
}

void ScreenManager::activateAuthForPointerScreen(const QString &initialText)
{
    QScreen *screen = QGuiApplication::screenAt(QCursor::pos());
    if (!screen)
        screen = m_authScreen ? m_authScreen : QGuiApplication::primaryScreen();
    if (!screen)
        return;

    // The surface that is about to wake reads this back while it focuses its
    // password field, so the keystroke that woke the lock is not swallowed.
    m_pendingText = initialText;
    setAuthScreen(screen);
}

QString ScreenManager::takePendingText()
{
    const QString text = m_pendingText;
    m_pendingText.clear();
    return text;
}

void ScreenManager::clearAuth()
{
    // The grab stays where it is: keys still have to reach a lock window so the
    // next keystroke can wake the screen the pointer is on.
    setAuthScreen(nullptr);
}

void ScreenManager::setInteractive(bool interactive)
{
    qWarning().nospace() << "ScreenManager: setInteractive " << interactive;
    m_interactive = interactive;
}

QString ScreenManager::printableText(const QKeyEvent *event)
{
    const QString text = event->text();
    if (text.isEmpty())
        return QString();
    if (event->modifiers() & (Qt::ControlModifier | Qt::AltModifier | Qt::MetaModifier))
        return QString();
    for (const QChar &character : text) {
        if (character.unicode() < 0x20 || character.unicode() == 0x7f)
            return QString();
    }
    return text;
}

bool ScreenManager::eventFilter(QObject *watched, QEvent *event)
{
    if (event->type() != QEvent::KeyPress || !m_visible || !m_interactive)
        return QObject::eventFilter(watched, event);

    // The power menu owns the keyboard while it is up: it holds the grab and its
    // own item has the focus, and its keys are its own — Escape closes it. The
    // routing below would take them instead, because with no screen picked for
    // authentication yet (the idle lock) the target is never the auth screen, so
    // every key was consumed as "wake this screen up" and Escape reached the
    // lock rather than the menu. That left the menu with no keyboard way out.
    for (QQuickWindow *window : std::as_const(m_powerWindows)) {
        if (window && window->isVisible())
            return QObject::eventFilter(watched, event);
    }

    auto *keyEvent = static_cast<QKeyEvent *>(event);

    // The X11 keyboard grab delivers every keystroke to a single window — the
    // one that carries the password field — but that is not necessarily the
    // screen the user is looking at. The pointer is the only signal for where
    // "here" is, so a keystroke aimed at another screen hands the interactive
    // UI over there (seeded with the key that woke it) instead of being typed
    // into the field the user cannot see.
    QScreen *target = QGuiApplication::screenAt(QCursor::pos());
    if (!target || target == m_authScreen)
        return QObject::eventFilter(watched, event);

    m_pendingText = printableText(static_cast<QKeyEvent *>(event));
    setAuthScreen(target);
    return true; // consumed: not for the previous screen's field
}

void ScreenManager::setAuthScreen(QScreen *screen)
{
    qWarning().nospace() << "ScreenManager: setAuthScreen "
                         << (screen ? screen->name() : QStringLiteral("none"));
    if (screen == m_authScreen)
        return;

    m_authScreen = screen;
    emit authScreenChanged();

    if (!screen)
        return;

    if (m_visible) {
        if (QQuickWindow *window = windowForScreen(screen)) {
            window->raise();
            window->requestActivate();
        }
    }

    // The keys follow the password field.
    m_grabWindow = windowForScreen(screen);
    applyKeyboardGrab();
}

void ScreenManager::chooseGrabWindow()
{
    if (m_grabWindow && m_windows.values().contains(m_grabWindow))
        return;

    QQuickWindow *window = windowForScreen(m_authScreen);
    if (!window)
        window = windowForScreen(QGuiApplication::primaryScreen());
    if (!window && !m_windows.isEmpty())
        window = *m_windows.constBegin();
    m_grabWindow = window;
}

void ScreenManager::onScreenAdded(QScreen *screen)
{
    createWindowForScreen(screen);
    if (!m_grabWindow) {
        chooseGrabWindow();
        applyKeyboardGrab();
    }
}

void ScreenManager::onScreenRemoved(QScreen *screen)
{
    destroyWindowForScreen(screen);
    destroyPowerWindowForScreen(screen);

    if (screen == m_powerControlScreen) {
        // The screen carrying the menu's controls is gone. Hand them to whatever
        // screen the pointer is on rather than leaving the menu with nothing to
        // press.
        m_powerControlScreen = nullptr;
        if (!m_powerWindows.isEmpty())
            setPowerControlScreen(QGuiApplication::screenAt(QCursor::pos()));
    }

    if (screen == m_authScreen) {
        // The screen that carried the password field is gone: fall back to
        // "no screen is active" rather than leaving the lock with an
        // unreachable authentication UI. Every remaining screen can take it
        // over again (click, or any key press).
        m_authScreen = nullptr;
        emit authScreenChanged();
    }

    // Any remaining screen must be able to hand the lock over, even when the
    // screen that held the grab (or the whole primary screen) just went away.
    chooseGrabWindow();
    applyKeyboardGrab();
}

void ScreenManager::createWindowForScreen(QScreen *screen)
{
    if (!screen || m_windows.contains(screen))
        return;

    QQmlComponent component(m_engine, m_surfaceUrl, this);
    if (component.isError()) {
        qWarning().noquote() << "ScreenManager: failed to load" << m_surfaceUrl.toString();
        const auto errors = component.errors();
        for (const QQmlError &error : errors)
            qWarning().noquote() << "  " << error.toString();
        return;
    }

    QObject *obj = component.create();
    QQuickWindow *window = qobject_cast<QQuickWindow *>(obj);
    if (!window) {
        qWarning().noquote() << "ScreenManager: root of" << m_surfaceUrl.toString()
                             << "is not a Window";
        delete obj;
        return;
    }

    window->setTitle(QStringLiteral("Lumina Lock"));
    // Flags and colour are declared in qml/LockScreen.qml so that they are in
    // place before any native window exists; setting them here would recreate
    // the native window and race the mapping.
    window->setScreen(screen);
    window->setGeometry(screen->geometry());
    markAsLockWindow(window);
    if (m_visible) {
        window->showFullScreen();
        window->raise();
        window->requestActivate();
    }

    m_windows.insert(screen, window);
    if (!m_grabWindow)
        chooseGrabWindow();

    // Key presses are watched per window, not application-wide: Qt offers the
    // *same* QKeyEvent to the window, then to the focused item, then up that
    // item's parent chain, so an application-wide filter would see one physical
    // key press several times — and act on it more than once. The window-level
    // delivery is the first and only reliable one.
    window->installEventFilter(this);

    // X11 refuses a grab until the window is actually viewable, which only
    // happens after showFullScreen() has been round-tripped to the server.
    // Re-apply once the surface is on screen (the grab window is the one that
    // needs it; the others never hold a grab).
    connect(window, &QQuickWindow::visibleChanged, this, [this, window](bool visible) {
        if (visible && m_grabInput && window == m_grabWindow)
            applyKeyboardGrab();
    });
    connect(window, &QQuickWindow::sceneGraphInitialized, this, [this, window] {
        if (m_grabInput && window == m_grabWindow)
            applyKeyboardGrab();
    });
}

void ScreenManager::destroyWindowForScreen(QScreen *screen)
{
    auto it = m_windows.find(screen);
    if (it == m_windows.end())
        return;

    QQuickWindow *window = it.value();
    m_windows.erase(it);
    if (window == m_grabWindow)
        m_grabWindow = nullptr;

    window->close();
    window->deleteLater();
}

QQuickWindow *ScreenManager::windowForScreen(const QScreen *screen) const
{
    if (!screen)
        return nullptr;
    return m_windows.value(const_cast<QScreen *>(screen));
}

QScreen *ScreenManager::screenByName(const QString &name) const
{
    if (name.isEmpty())
        return nullptr;
    const QList<QScreen *> screens = QGuiApplication::screens();
    for (QScreen *screen : screens) {
        if (screen->name() == name)
            return screen;
    }
    return nullptr;
}
