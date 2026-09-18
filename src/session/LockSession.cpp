#include "LockSession.h"

#include "auth/PamAuthenticator.h"
#include "session/dbusnames.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QFileInfo>
#include <QUrl>
#include <QDebug>

#include <pwd.h>
#include <unistd.h>

namespace {
QString gecosDisplayName(const struct passwd *pw)
{
    const QString gecos = QString::fromLocal8Bit(pw->pw_gecos);
    const QString first = gecos.section(QLatin1Char(','), 0, 0).trimmed();
    return first.isEmpty() ? QString::fromLocal8Bit(pw->pw_name) : first;
}
} // namespace

LockSession::LockSession(PamAuthenticator *auth, QObject *parent)
    : QObject(parent)
    , m_auth(auth)
{
    if (const struct passwd *pw = getpwuid(getuid())) {
        m_userName = QString::fromLocal8Bit(pw->pw_name);
        m_displayName = gecosDisplayName(pw);
    } else {
        m_userName = QString::fromLocal8Bit(qgetenv("USER"));
        m_displayName = m_userName;
    }

    char host[256] = {0};
    if (gethostname(host, sizeof(host) - 1) == 0)
        m_hostName = QString::fromLocal8Bit(host);

    connect(m_auth, &PamAuthenticator::finished,
            this, &LockSession::onAuthFinished);

    fetchAvatar();
}

// dde-lock reads the account picture from the accounts service on the *system*
// bus: IconFile on /org/deepin/dde/Accounts1/User<uid>, and it accepts the answer
// only if the file exists and is not empty. Same source, same check; the scene
// falls back to the letter avatar when there is nothing to show. Fetched
// asynchronously because this is the lock's startup path — a service that is slow
// to answer must not delay the first frame.
void LockSession::fetchAvatar()
{
    const QString path = QStringLiteral("/org/deepin/dde/Accounts1/User%1").arg(getuid());
    // The property has to be read through the Properties interface, not by
    // giving asyncCall a dotted "Properties.Get" as the method name on the user
    // interface: that builds an invalid member and libdbus aborts the process.
    QDBusInterface props(QStringLiteral("org.deepin.dde.Accounts1"), path,
                         QStringLiteral("org.freedesktop.DBus.Properties"),
                         QDBusConnection::systemBus());
    if (!props.isValid())
        return; // no accounts service on this system: the initial stands

    auto *watcher = new QDBusPendingCallWatcher(
        props.asyncCall(QStringLiteral("Get"), QStringLiteral("org.deepin.dde.Accounts1.User"),
                        QStringLiteral("IconFile")),
        this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        const QDBusPendingReply<QVariant> reply = *watcher;
        watcher->deleteLater();
        if (!reply.isValid())
            return;

        // Properties.Get answers with a variant, and Qt may or may not have
        // already unwrapped it depending on how the reply was built. Unwrap only
        // when there is something to unwrap, instead of assuming one shape.
        QVariant value = reply.value();
        if (value.canConvert<QDBusVariant>())
            value = value.value<QDBusVariant>().variant();
        const QString url = value.toString();
        const QString file = url.startsWith(QLatin1String("file://")) ? QUrl(url).toLocalFile() : url;
        const QFileInfo info(file);
        if (file.isEmpty() || !info.exists() || !info.isFile() || info.size() <= 0)
            return; // nothing set for this account

        // Handed to QML as a URL: Image.source does not take a bare filesystem
        // path (a leading slash is resolved as a resource path there).
        const QString url2 = QUrl::fromLocalFile(file).toString();
        if (m_avatarPath == url2)
            return;
        m_avatarPath = url2;
        qWarning().noquote() << "LockSession: account avatar" << m_avatarPath;
        Q_EMIT avatarPathChanged();
    });
}

void LockSession::setUser(const QString &user)
{
    m_userName = user;
    m_displayName = user;
}

void LockSession::authenticate(const QString &password)
{
    if (m_authenticating)
        return;

    m_authenticating = true;
    emit authenticatingChanged();
    clearError();

    QByteArray bytes = password.toUtf8();
    m_auth->authenticate(m_userName, bytes);
    bytes.fill('\0'); // minimise the lifetime of our own copy
}

void LockSession::unlock()
{
    if (!m_locked)
        return;
    m_locked = false;
    emit lockedChanged(false);
    emit Visible(false);
    emit unlocked();
}

void LockSession::lock()
{
    if (m_locked)
        return;
    m_locked = true;
    emit lockedChanged(true);
    emit Visible(true);
}

void LockSession::show()
{
    lock();
}

void LockSession::showUserList()
{
    // The user list lives in the greeter, not in the lock: the standard
    // interface hands the seat over to it, which is where a person picks another
    // account. This is also where dde-lock's own "switch user" ends up, so the
    // D-Bus surface keeps meaning what it meant.
    if (qEnvironmentVariableIsSet("LUMINA_POWER_DRY_RUN")) {
        qWarning() << "LockSession: dry run, would switch to the greeter";
        return;
    }

    QDBusInterface seat(DISPLAY_MANAGER_SERVICE, DISPLAY_MANAGER_SEAT_PATH,
                        DISPLAY_MANAGER_SEAT_INTERFACE, QDBusConnection::systemBus());
    if (seat.isValid() == false) {
        qWarning() << "LockSession:" << DISPLAY_MANAGER_SERVICE
                   << "has no seat; cannot switch user";
        return;
    }
    seat.asyncCall(QStringLiteral("SwitchToGreeter"));
}

void LockSession::showAuth(bool active)
{
    lock();
    if (active)
        emit showAuthRequested();
}

void LockSession::suspend(bool enable)
{
    // Resume from suspend: dde-lock only re-engages the lock when the power
    // daemon's SleepLock is on; honour that setting (missing service → lock,
    // which is the safe default).
    if (!enable) {
        QDBusInterface power(LOCK_POWER_SERVICE, LOCK_POWER_PATH,
                             LOCK_POWER_SERVICE, QDBusConnection::sessionBus());
        const QVariant sleepLock = power.property("SleepLock");
        if (sleepLock.isValid() && !sleepLock.toBool())
            return; // sleep-lock disabled: resume straight to the desktop
    }
    lock();
}

void LockSession::hibernate(bool /*enable*/)
{
    lock();
}

void LockSession::quit()
{
    emit quitRequested();
}

void LockSession::clearError()
{
    if (!m_errorMessage.isEmpty()) {
        m_errorMessage.clear();
        emit errorMessageChanged();
    }
}

void LockSession::onAuthFinished(bool success, const QString &message)
{
    m_authenticating = false;
    emit authenticatingChanged();

    if (!success) {
        m_errorMessage = message.isEmpty() ? tr("Authentication failed") : message;
        emit errorMessageChanged();
        // Failure audit (message only — never the password).
        qWarning().noquote() << "Authentication failed:" << m_errorMessage;
    }
    emit authenticationFinished(success, message);
}
