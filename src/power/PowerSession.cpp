#include "PowerSession.h"

#include "screen/ScreenManager.h"
#include "session/LockSession.h"
#include "session/dbusnames.h"

#include <QDBusConnection>
#include <QTimer>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>

namespace {

QDBusInterface *sessionManager()
{
    return new QDBusInterface(SESSION_MGR_SERVICE, SESSION_MGR_PATH,
                              SESSION_MGR_INTERFACE, QDBusConnection::sessionBus());
}

QDBusInterface *lastore()
{
    return new QDBusInterface(LASTORE_SERVICE, LASTORE_PATH, LASTORE_INTERFACE,
                              QDBusConnection::systemBus());
}

// One entry per action this machine can actually perform. Anything unavailable
// is left out entirely rather than greyed: a disabled control advertises
// something that cannot happen.
QVariantMap row(const QString &key, const QString &label, const QString &icon,
                const QString &kind)
{
    QVariantMap map;
    map.insert(QStringLiteral("key"), key);
    map.insert(QStringLiteral("label"), label);
    map.insert(QStringLiteral("icon"), icon);
    map.insert(QStringLiteral("kind"), kind);
    return map;
}

} // namespace

PowerSession::PowerSession(QObject *parent)
    : QObject(parent)
{
    rebuildOptions();
    refreshAvailability(); // warm the cache so the first menu is already accurate
}

// A dry run keeps this menu from taking the machine down while it is being
// developed or tested. It can only ever *prevent* an action, so it is safe to
// leave in: nothing sets it unless someone goes looking for it.
bool PowerSession::dryRun()
{
    return qEnvironmentVariableIsSet("LUMINA_POWER_DRY_RUN");
}

void PowerSession::queryCan(const QString &method, bool *slot)
{
    QDBusInterface ifc(SESSION_MGR_SERVICE, SESSION_MGR_PATH, SESSION_MGR_INTERFACE,
                       QDBusConnection::sessionBus());
    if (!ifc.isValid())
        return; // nothing to ask: leave the permissive default in place

    auto *watcher = new QDBusPendingCallWatcher(ifc.asyncCall(method), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, slot] {
        const QDBusPendingReply<QVariant> reply = *watcher;
        watcher->deleteLater();
        const bool allowed = reply.isValid() ? reply.value().toBool() : true;
        if (*slot == allowed)
            return;
        *slot = allowed;
        rebuildOptions();
    });
}

void PowerSession::queryUpdateMode()
{
    // lastore's CheckUpdateMode is read asynchronously for the same reason as
    // the Can* flags: reading it synchronously from here can block.
    QDBusInterface props(LASTORE_SERVICE, LASTORE_PATH,
                         QStringLiteral("org.freedesktop.DBus.Properties"),
                         QDBusConnection::systemBus());
    if (!props.isValid())
        return;

    auto *watcher = new QDBusPendingCallWatcher(
        props.asyncCall(QStringLiteral("Get"), LASTORE_INTERFACE,
                        QStringLiteral("CheckUpdateMode")),
        this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        const QDBusPendingReply<QVariant> reply = *watcher;
        watcher->deleteLater();
        if (!reply.isValid())
            return;
        QVariant value = reply.value();
        if (value.canConvert<QDBusVariant>())
            value = value.value<QDBusVariant>().variant();
        m_updateMode = value.toInt(); // the mode the upgrade request wants
    });
}

void PowerSession::queryUpdateState()
{
    // lastore publishes what it would install; an empty list is the only
    // honest "nothing to do here".
    QDBusInterface props(LASTORE_SERVICE, LASTORE_PATH,
                         QStringLiteral("org.freedesktop.DBus.Properties"),
                         QDBusConnection::systemBus());
    if (!props.isValid())
        return;

    auto *watcher = new QDBusPendingCallWatcher(
        props.asyncCall(QStringLiteral("Get"), LASTORE_INTERFACE,
                        QStringLiteral("UpgradableApps")),
        this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        const QDBusPendingReply<QVariant> reply = *watcher;
        watcher->deleteLater();
        if (!reply.isValid())
            return;
        QVariant value = reply.value();
        if (value.canConvert<QDBusVariant>())
            value = value.value<QDBusVariant>().variant();
        const bool pending = value.toList().size() > 0;
        if (pending == m_updatesPending)
            return;
        m_updatesPending = pending;
        rebuildOptions(); // the two power rows are worded from this
    });
}

void PowerSession::refreshAvailability()
{
    QDBusConnectionInterface *systemIfc = QDBusConnection::systemBus().interface();
    m_updatesAvailable = systemIfc && systemIfc->isServiceRegistered(LASTORE_SERVICE);

    queryCan(QStringLiteral("CanShutdown"), &m_canShutdown);
    queryCan(QStringLiteral("CanReboot"), &m_canReboot);
    queryCan(QStringLiteral("CanLogout"), &m_canLogout);
    queryCan(QStringLiteral("CanSuspend"), &m_canSuspend);
    queryCan(QStringLiteral("CanHibernate"), &m_canHibernate);
    if (m_updatesAvailable) {
        queryUpdateMode();
        queryUpdateState();
    }

    rebuildOptions(); // the update rows are known now; the Can* land later
}

void PowerSession::setDimProgress(qreal progress)
{
    const qreal clamped = qBound(qreal(0), progress, qreal(1));
    if (qFuzzyCompare(clamped, m_dimProgress))
        return;
    m_dimProgress = clamped;
    Q_EMIT dimProgressChanged();
}

void PowerSession::rebuildOptions()
{
    // Only what this machine can do. Anything unavailable is left out entirely
    // rather than greyed: a control that cannot be pressed should not be there
    // to press.
    //
    // The order is the order the menu draws: everything that can be taken back
    // first, then everything that cannot. Shutting down is the slider, so it is
    // not in either row.
    QVariantList list;
    // Locking is meaningless while the lock is already the thing on screen.
    if (!m_lockSession || !m_lockSession->locked())
        list << row(QStringLiteral("lock"), tr("锁定"), QStringLiteral("lock"),
                    QStringLiteral("normal"));
    if (m_canSuspend)
        list << row(QStringLiteral("suspend"), tr("待机"), QStringLiteral("moon"),
                    QStringLiteral("normal"));
    if (m_canHibernate)
        list << row(QStringLiteral("hibernate"), tr("休眠"), QStringLiteral("snow"),
                    QStringLiteral("normal"));
    // Logging out is recoverable — you log back in — so it is not a hold.
    if (m_canLogout)
        list << row(QStringLiteral("logout"), tr("注销"), QStringLiteral("logout"),
                    QStringLiteral("normal"));

    // Restart is the other one that cannot be taken back, and it sits with the
    // update variants rather than with the reversible actions.
    if (m_canReboot)
        list << row(QStringLiteral("reboot"), tr("重启"), QStringLiteral("restart"),
                    QStringLiteral("danger"));

    // The update variants are entries of their own, and they exist only when
    // there is something to install: lastore runs the upgrade and then takes the
    // machine down itself, so they are not the same thing as a plain restart or
    // shut down, and offering them with nothing to install would be a lie.
    if (m_updatesPending) {
        if (m_canReboot)
            list << row(QStringLiteral("updateReboot"), tr("更新并重启"),
                        QStringLiteral("update"), QStringLiteral("danger"));
        if (m_canShutdown)
            list << row(QStringLiteral("updateShutdown"), tr("更新并关机"),
                        QStringLiteral("update"), QStringLiteral("danger"));
    }

    if (m_canShutdown)
        list << row(QStringLiteral("shutdown"), tr("关机"), QStringLiteral("power"),
                    QStringLiteral("danger"));

    m_options = list;
    Q_EMIT optionsChanged();
}

void PowerSession::show()
{
    qWarning().nospace() << "Power: show() visible=" << m_visible
                         << " locked=" << (m_lockSession ? m_lockSession->locked() : false);
    if (m_visible)
        return;

    // Over an unlocked session the lock surfaces are hidden. The menu draws on
    // them and needs the input the desktop currently has, so bring them up — and
    // remember to put them back down when the menu closes.
    // The menu draws in a window of its own: it used to be a layer on the lock's
    // surfaces, but those are hidden and re-shown around every unlock and do not
    // always come back cleanly, so the menu could end up with a surface that is
    // up, mapped, and drawing nothing.
    m_overDesktop = m_lockSession && !m_lockSession->locked();
    if (m_screens)
        m_screens->showPowerMenu();

    refreshAvailability();
    // The slide starts where the last menu left it otherwise: every screen reads
    // this, and the one that has the controls writes it.
    setDimProgress(0);
    m_visible = true;
    qWarning().nospace() << "Power: show() done overDesktop=" << m_overDesktop
                         << " options=" << m_options.size()
                         << " updatesAvailable=" << m_updatesAvailable;
    Q_EMIT Visible(true);
}

void PowerSession::dismiss()
{
    qWarning().nospace() << "Power: dismiss() visible=" << m_visible
                         << " overDesktop=" << m_overDesktop;
    if (!m_visible)
        return;

    m_visible = false;
    Q_EMIT Visible(false);

    // The scene fades out over the desktop — the window is transparent, so that
    // is a real dissolve and not a window close. Hiding the window here would cut
    // it off at the first frame, which is why cancelling the menu looked
    // instant. The scene reports when it has finished; the timer is the fallback
    // for a scene that never reports, because a window left up would hold the
    // keyboard grab with nothing on screen.
    if (m_screens)
        QTimer::singleShot(1500, this, [this] { exitFinished(); });
    m_overDesktop = false;
}

void PowerSession::exitFinished()
{
    if (!m_screens || m_visible)
        return; // dismissed and not re-opened since
    m_screens->hidePowerMenu();
}

void PowerSession::requestSessionMethod(const QString &method)
{
    if (dryRun()) {
        qWarning().noquote() << "PowerSession: dry run, would call" << method;
        return;
    }

    QDBusInterface ifc(SESSION_MGR_SERVICE, SESSION_MGR_PATH, SESSION_MGR_INTERFACE,
                       QDBusConnection::sessionBus());
    if (!ifc.isValid()) {
        qWarning().noquote() << "PowerSession:" << SESSION_MGR_SERVICE << "is not available";
        Q_EMIT failed(tr("会话管理器不可用"));
        return;
    }

    dismiss();
    ifc.asyncCall(method);
}

void PowerSession::requestUpdate(bool powerOff)
{
    if (dryRun()) {
        qWarning().noquote() << "PowerSession: dry run, would update and"
                             << (powerOff ? "shut down" : "restart");
        return;
    }

    QDBusInterface ifc(LASTORE_SERVICE, LASTORE_PATH, LASTORE_INTERFACE,
                       QDBusConnection::systemBus());
    if (!ifc.isValid()) {
        qWarning().noquote() << "PowerSession:" << LASTORE_SERVICE << "is not available";
        Q_EMIT failed(tr("本机未安装更新服务"));
        return;
    }

    // The same request dde-lock makes: lastore runs the upgrade and then takes
    // the machine down itself, so there is nothing for us to wait for. The mode
    // comes from the cache refreshed when the menu opened.
    QJsonObject content;
    content.insert(QStringLiteral("DoUpgradeMode"), m_updateMode);
    content.insert(QStringLiteral("IsPowerOff"), powerOff);

    dismiss();
    ifc.asyncCall(QStringLiteral("PrepareFullScreenUpgrade"),
                  QString::fromUtf8(QJsonDocument(content).toJson()));
}

void PowerSession::shutdown() { show(); Q_EMIT armRequested(QStringLiteral("shutdown")); }
void PowerSession::restart() { show(); Q_EMIT armRequested(QStringLiteral("reboot")); }
void PowerSession::logout() { show(); Q_EMIT armRequested(QStringLiteral("logout")); }
void PowerSession::suspend() { show(); Q_EMIT armRequested(QStringLiteral("suspend")); }
void PowerSession::hibernate() { show(); Q_EMIT armRequested(QStringLiteral("hibernate")); }
void PowerSession::updateAndShutdown() { show(); Q_EMIT armRequested(QStringLiteral("updateShutdown")); }
void PowerSession::updateAndReboot() { show(); Q_EMIT armRequested(QStringLiteral("updateReboot")); }
// One implementation for both entry points: the lock screen's button and the
// D-Bus SwitchUser land in LockSession, which is the object that knows about the
// session rather than about this menu.
void PowerSession::switchUser()
{
    if (m_lockSession)
        m_lockSession->showUserList();
}

void PowerSession::lock()
{
    dismiss();
    if (m_lockSession)
        m_lockSession->lock();
}

void PowerSession::highlight(const QString &key)
{
    Q_EMIT ChangKey(key);
}

void PowerSession::activate(const QString &key)
{
    if (key == QLatin1String("shutdown"))
        requestSessionMethod(SESSION_MGR_REQUEST_SHUTDOWN);
    else if (key == QLatin1String("reboot"))
        requestSessionMethod(SESSION_MGR_REQUEST_REBOOT);
    else if (key == QLatin1String("updateShutdown"))
        requestUpdate(true);
    else if (key == QLatin1String("updateReboot"))
        requestUpdate(false);
    else if (key == QLatin1String("logout"))
        requestSessionMethod(SESSION_MGR_REQUEST_LOGOUT);
    else if (key == QLatin1String("suspend"))
        requestSessionMethod(SESSION_MGR_REQUEST_SUSPEND);
    else if (key == QLatin1String("hibernate"))
        requestSessionMethod(SESSION_MGR_REQUEST_HIBERNATE);
    else if (key == QLatin1String("lock"))
        lock();
    else
        qWarning().noquote() << "PowerSession: unknown action" << key;
}
