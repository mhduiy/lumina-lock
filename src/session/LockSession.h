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
    Q_CLASSINFO("D-Bus Interface", "org.lumina.Lock")
    Q_PROPERTY(QString userName READ userName CONSTANT)
    Q_PROPERTY(QString displayName READ displayName CONSTANT)
    Q_PROPERTY(QString hostName READ hostName CONSTANT)
    // The account's picture, or empty when there is none worth showing. Read
    // from the same place dde-lock reads it (see fetchAvatar()).
    Q_PROPERTY(QString avatarPath READ avatarPath NOTIFY avatarPathChanged)
    Q_PROPERTY(bool authenticating READ authenticating NOTIFY authenticatingChanged)
    Q_PROPERTY(bool locked READ locked NOTIFY lockedChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)

public:
    explicit LockSession(PamAuthenticator *auth, QObject *parent = nullptr);

    QString userName() const { return m_userName; }
    QString displayName() const { return m_displayName; }
    QString avatarPath() const { return m_avatarPath; }
    QString hostName() const { return m_hostName; }
    bool authenticating() const { return m_authenticating; }
    bool locked() const { return m_locked; }
    bool visible() const { return m_locked; }
    QString errorMessage() const { return m_errorMessage; }

    /** Set the initial lock state before the UI is created (startup only). */
    void setLocked(bool locked) { m_locked = locked; }

    /**
     * Tell the session manager whether this session is locked.
     *
     * org.deepin.dde.SessionManager1 is the authority the rest of DDE reads:
     * logind, power management, and dde-quick-login — which starts the lock with
     * `-lq` and only reports the login as good once LockedChanged(true) arrives.
     * dde-lock does this from LockWorker::setLocked(); without it the session
     * stays "unlocked" for DDE while the screen is covered.
     *
     * Sent on every lock/unlock transition. main() also calls it once the lock
     * front is owned, because a quick-login launch *starts* locked and so never
     * transitions.
     */
    void reportLockState();

    /** Override the target user (CLI --user). */
    void setUser(const QString &user);

    /** Ask PAM to verify the password for the current user. */
    Q_INVOKABLE void authenticate(const QString &password);

    /**
     * Mark the session as unlocked. Called by QML *after* the exit animation.
     * Hides the surfaces but keeps the process resident (the lock is a
     * long-running service, not a one-shot window).
     */
    Q_INVOKABLE void unlock();

    Q_INVOKABLE void clearError();

    // dde-lock `lockFront` semantics (driven by the LockService adaptor).
    void show();
    void showUserList();
    void showAuth(bool active);
    void suspend(bool enable);
    void hibernate(bool enable);

public slots:
    /** Re-engage the lock (exposed on D-Bus for session integration). */
    void lock();

    /** Gracefully shut the resident process down (D-Bus). */
    void quit();

signals:
    void authenticatingChanged();
    void errorMessageChanged();
    void avatarPathChanged();
    void lockedChanged(bool locked);
    void authenticationFinished(bool success, const QString &message);
    void unlocked();
    void quitRequested();

    // Emitted so QML can jump straight to the auth state when ShowAuth(true)
    // arrives from the session.
    void showAuthRequested();

    // dde-lock-compatible signals (relayed by the LockService adaptor).
    void Visible(bool visible);
    void ChangKey(QString key);

private:
    void onAuthFinished(bool success, const QString &message);

    PamAuthenticator *m_auth = nullptr;
    QString m_userName;
    QString m_displayName;
    QString m_avatarPath;
    void fetchAvatar();
    QString m_hostName;
    bool m_authenticating = false;
    bool m_locked = true;
    // The state the session manager was last told about, so a transition that
    // does not move it (and the startup call on top of one) stays quiet.
    int m_reportedLockState = -1;
    QString m_errorMessage;
};
