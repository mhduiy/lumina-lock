#pragma once

#include <QObject>
#include <QByteArray>
#include <QString>

#include <security/pam_appl.h>

#include <atomic>
#include <memory>
#include <string>
#include <thread>

/**
 * Performs PAM authentication off the GUI thread.
 *
 * PAM is inherently a blocking C API, so the actual pam_start /
 * pam_authenticate / pam_end sequence runs on a detached worker thread.
 * Results are marshalled back to the GUI thread through a queued signal.
 *
 * The plain-text password only ever lives in a Job struct that is owned by
 * the worker thread; it is wiped from memory as soon as the PAM exchange is
 * done. It is never logged and never copied back to QML.
 */
class PamAuthenticator : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit PamAuthenticator(QObject *parent = nullptr);
    ~PamAuthenticator() override;

    bool busy() const { return m_busy.load(); }

    QString pamService() const { return m_service; }
    void setPamService(const QString &service) { m_service = service; }

    /** Start an asynchronous authentication attempt. No-op if already busy. */
    Q_INVOKABLE void authenticate(const QString &user, const QByteArray &password);

    /** Best-effort cancellation of an in-flight attempt. */
    Q_INVOKABLE void cancel();

signals:
    void busyChanged();
    /** @param success true when PAM accepted the credentials. */
    void finished(bool success, const QString &message);

private:
    struct Job
    {
        std::string user;
        std::string password;
        std::string message; // captured PAM error / info text
    };

    static int conversation(int numMsg, const pam_message **msg,
                            pam_response **resp, void *appdata);
    static int runPam(Job &job, const std::string &service);
    static QString friendlyError(int rc, const std::string &fallback);

    void joinThread();

    std::atomic_bool m_busy{false};
    std::atomic_bool m_cancelled{false};
    std::unique_ptr<std::thread> m_thread;
    QString m_service = QStringLiteral("login");
};
