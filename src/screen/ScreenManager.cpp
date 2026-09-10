#include "ScreenManager.h"

#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QScreen>
#include <QDebug>

#include <utility>

ScreenManager::ScreenManager(QQmlEngine *engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
{
}

void ScreenManager::start()
{
    const QList<QScreen *> screens = QGuiApplication::screens();
    for (QScreen *screen : screens)
        createWindowForScreen(screen);

    connect(qGuiApp, &QGuiApplication::screenAdded,
            this, &ScreenManager::onScreenAdded);
    connect(qGuiApp, &QGuiApplication::screenRemoved,
            this, &ScreenManager::onScreenRemoved);
}

void ScreenManager::showAll()
{
    for (QQuickWindow *window : std::as_const(m_windows)) {
        window->showFullScreen();
        window->raise();
        window->requestActivate();
    }
}

void ScreenManager::hideAll()
{
    for (QQuickWindow *window : std::as_const(m_windows))
        window->hide();
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
    window->setScreen(screen);
    window->setGeometry(screen->geometry());
    window->showFullScreen();
    window->raise();
    window->requestActivate();

    m_windows.insert(screen, window);
    if (primary)
        m_primaryWindow = window;
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
