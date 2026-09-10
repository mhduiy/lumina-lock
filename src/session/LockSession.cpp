#include "LockSession.h"

#include "auth/PamAuthenticator.h"

#include <QCoreApplication>

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
    emit unlocked();
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
    }
    emit authenticationFinished(success, message);
}
