#pragma once

#include <QObject>
#include <QString>

class PamAuthenticator;

/**
 * Session-facing facade for the lock screen.
 *
 * QML talks exclusively to this object: it owns the user identity, forwards
 * authentication requests to the PAM backend and turns results into UI-level
 * signals. QML never touches PAM directly.
 */
class LockSession : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString userName READ userName CONSTANT)
    Q_PROPERTY(QString displayName READ displayName CONSTANT)
    Q_PROPERTY(QString hostName READ hostName CONSTANT)
    Q_PROPERTY(bool authenticating READ authenticating NOTIFY authenticatingChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)

public:
    explicit LockSession(PamAuthenticator *auth, QObject *parent = nullptr);

    QString userName() const { return m_userName; }
    QString displayName() const { return m_displayName; }
    QString hostName() const { return m_hostName; }
    bool authenticating() const { return m_authenticating; }
    QString errorMessage() const { return m_errorMessage; }

    /** Override the target user (CLI --user). */
    void setUser(const QString &user);

    /** Ask PAM to verify the password for the current user. */
    Q_INVOKABLE void authenticate(const QString &password);

    /** Signal the system that the session has been unlocked. */
    Q_INVOKABLE void unlock();

    Q_INVOKABLE void clearError();

signals:
    void authenticatingChanged();
    void errorMessageChanged();
    void authenticationFinished(bool success, const QString &message);
    void unlocked();

private:
    void onAuthFinished(bool success, const QString &message);

    PamAuthenticator *m_auth = nullptr;
    QString m_userName;
    QString m_displayName;
    QString m_hostName;
    bool m_authenticating = false;
    QString m_errorMessage;
};
