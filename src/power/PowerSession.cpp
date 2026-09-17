#include "PowerSession.h"

#include "screen/ScreenManager.h"
#include "session/LockSession.h"
#include "session/dbusnames.h"

#include <QDBusConnection>
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

QVariantMap row(const QString &key, const QString &label, const QString &sub,
                const QString &kind, bool enabled, const QString &note = QString())
{
    QVariantMap map;
    map.insert(QStringLiteral("key"), key);
    map.insert(QStringLiteral("label"), label);
    map.insert(QStringLiteral("sub"), sub);
    map.insert(QStringLiteral("kind"), kind);
    map.insert(QStringLiteral("enabled"), enabled);
    map.insert(QStringLiteral("note"), note);
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
        m_updateMode = reply.value().value<QDBusVariant>().variant().toInt();
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
    if (m_updatesAvailable)
        queryUpdateMode();

    rebuildOptions(); // the update rows are known now; the Can* land later
}

void PowerSession::rebuildOptions()
{
    // Asking the session manager what it can actually do is the difference
    // between a menu that lies and one that shows five rows on a machine that
    // supports five. The update rows depend on the update daemon being there at
    // all, which is a property of the installed system rather than of the
    // session.
    const bool updates = m_updatesAvailable;

    QVariantList list;
    list << row(QStringLiteral("shutdown"), QStringLiteral("关机"), QStringLiteral("Shut down"),
                QStringLiteral("danger"), m_canShutdown)
         << row(QStringLiteral("reboot"), QStringLiteral("重启"), QStringLiteral("Restart"),
                QStringLiteral("danger"), m_canReboot)
         << row(QStringLiteral("updateShutdown"), QStringLiteral("更新并关机"),
                QStringLiteral("Update, then shut down"), QStringLiteral("update"), updates,
                updates ? QString() : tr("本机未安装更新服务"))
         << row(QStringLiteral("updateReboot"), QStringLiteral("更新并重启"),
                QStringLiteral("Update, then restart"), QStringLiteral("update"), updates,
                updates ? QString() : tr("本机未安装更新服务"))
         << row(QStringLiteral("suspend"), QStringLiteral("待机"), QStringLiteral("Suspend"),
                QStringLiteral("normal"), m_canSuspend)
         << row(QStringLiteral("hibernate"), QStringLiteral("休眠"), QStringLiteral("Hibernate"),
                QStringLiteral("normal"), m_canHibernate)
         << row(QStringLiteral("logout"), QStringLiteral("注销"), QStringLiteral("Log out"),
                QStringLiteral("danger"), m_canLogout);

    // Locking is meaningless while the lock is already the thing on screen.
    if (!m_lockSession || !m_lockSession->locked())
        list << row(QStringLiteral("lock"), QStringLiteral("锁定"), QStringLiteral("Lock"),
                    QStringLiteral("normal"), true);

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

    if (m_screens)
        m_screens->hidePowerMenu();
    m_overDesktop = false;
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
void PowerSession::switchUser() { show(); }

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
    else if (key == QLatin1String("logout"))
        requestSessionMethod(SESSION_MGR_REQUEST_LOGOUT);
    else if (key == QLatin1String("suspend"))
        requestSessionMethod(SESSION_MGR_REQUEST_SUSPEND);
    else if (key == QLatin1String("hibernate"))
        requestSessionMethod(SESSION_MGR_REQUEST_HIBERNATE);
    else if (key == QLatin1String("updateShutdown"))
        requestUpdate(true);
    else if (key == QLatin1String("updateReboot"))
        requestUpdate(false);
    else if (key == QLatin1String("lock"))
        lock();
    else
        qWarning().noquote() << "PowerSession: unknown action" << key;
}
