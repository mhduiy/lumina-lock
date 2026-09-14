#include "ScreenManager.h"

#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QScreen>
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

} // namespace

ScreenManager::ScreenManager(QQmlEngine *engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
{
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
    }
    setInputGrabbed(true);
}

void ScreenManager::hideAll()
{
    m_visible = false;
    // Release before hiding. Unmapping a window implicitly drops its grabs, but
    // being explicit guarantees the desktop is usable even if a hide is missed.
    setInputGrabbed(false);
    for (QQuickWindow *window : std::as_const(m_windows))
        window->hide();
}

void ScreenManager::setInputGrabbed(bool grabbed)
{
    m_grabInput = grabbed;
    if (!m_primaryWindow)
        return;

    // Only the primary surface grabs: there can be exactly one X11 keyboard and
    // pointer grab, and that is the screen carrying the authentication UI.
    // X11 refuses the grab until the window is viewable, so this is also
    // re-applied from the window's visible/scene-graph signals below.
    const bool keyboard = m_primaryWindow->setKeyboardGrabEnabled(grabbed);
    const bool mouse = m_primaryWindow->setMouseGrabEnabled(grabbed);
    if (grabbed && !(keyboard && mouse)) {
        qWarning() << "ScreenManager: input grab refused (X11-only feature)"
                   << "keyboard:" << keyboard << "mouse:" << mouse;
    }
}

void ScreenManager::onScreenAdded(QScreen *screen)
{
    createWindowForScreen(screen);
}

void ScreenManager::onScreenRemoved(QScreen *screen)
{
    destroyWindowForScreen(screen);
}

void ScreenManager::createWindowForScreen(QScreen *screen)
{
    if (!screen || m_windows.contains(screen))
        return;

    const bool primary = (m_primaryWindow == nullptr);
    const QUrl &url = primary ? m_primaryUrl : m_secondaryUrl;

    QQmlComponent component(m_engine, url, this);
    if (component.isError()) {
        qWarning().noquote() << "ScreenManager: failed to load" << url.toString();
        const auto errors = component.errors();
        for (const QQmlError &error : errors)
            qWarning().noquote() << "  " << error.toString();
        return;
    }

    QObject *obj = component.create();
    QQuickWindow *window = qobject_cast<QQuickWindow *>(obj);
    if (!window) {
        qWarning().noquote() << "ScreenManager: root of" << url.toString()
                             << "is not a Window";
        delete obj;
        return;
    }

    window->setTitle(QStringLiteral("Lumina Lock"));
    window->setColor(Qt::black);
    window->setFlag(Qt::FramelessWindowHint, true);
    // dde-lock parity: on X11 the lock windows are unmanaged and always on
    // top; the deepin WM recognises them via the _DEEPIN_LOCK_SCREEN property.
    if (!qEnvironmentVariableIsSet("XDG_SESSION_TYPE")
        || qEnvironmentVariable("XDG_SESSION_TYPE") != QLatin1String("wayland")) {
        window->setFlag(Qt::WindowStaysOnTopHint, true);
        window->setFlag(Qt::X11BypassWindowManagerHint, true);
    }
    window->setScreen(screen);
    window->setGeometry(screen->geometry());
    markAsLockWindow(window);
    if (m_visible) {
        window->showFullScreen();
        window->raise();
        window->requestActivate();
    }

    m_windows.insert(screen, window);
    if (primary) {
        m_primaryWindow = window;
        // X11 refuses a grab until the window is actually viewable, which only
        // happens after showFullScreen() has been round-tripped to the server.
        // Re-apply once the surface is on screen.
        connect(window, &QQuickWindow::visibleChanged, this, [this](bool visible) {
            if (visible && m_grabInput)
                setInputGrabbed(true);
        });
        connect(window, &QQuickWindow::sceneGraphInitialized, this, [this] {
            if (m_grabInput)
                setInputGrabbed(true);
        });
    }
}

void ScreenManager::destroyWindowForScreen(QScreen *screen)
{
    auto it = m_windows.find(screen);
    if (it == m_windows.end())
        return;

    QQuickWindow *window = it.value();
    m_windows.erase(it);
    if (window == m_primaryWindow)
        m_primaryWindow = nullptr;

    window->close();
    window->deleteLater();
}
