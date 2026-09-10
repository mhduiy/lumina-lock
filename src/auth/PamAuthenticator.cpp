#include "PamAuthenticator.h"

#include <QMetaObject>
#include <QDebug>

#include <security/pam_appl.h>

#include <cstdlib>
#include <cstring>

namespace {

// Wipe memory in a way the compiler is not allowed to optimise away.
void secureZero(void *ptr, std::size_t n)
{
    if (!ptr || n == 0)
        return;
    volatile unsigned char *p = static_cast<volatile unsigned char *>(ptr);
    while (n--)
        *p++ = 0;
}

} // namespace

PamAuthenticator::PamAuthenticator(QObject *parent)
    : QObject(parent)
{
}

PamAuthenticator::~PamAuthenticator()
{
    // Never destroy while the worker thread may still be touching members.
    joinThread();
}

void PamAuthenticator::authenticate(const QString &user, const QByteArray &password)
{
    if (m_busy.load())
        return;

    qDebug() << "PAM: authenticate() requested for user" << user;

    auto job = std::make_shared<Job>();
    job->user = user.toStdString();
    job->password.assign(password.constData(), static_cast<std::size_t>(password.size()));

    // Copy the service name before handing off to the thread so the worker
    // never reads a mutable member concurrently.
    const std::string service = m_service.toStdString();

    m_busy.store(true);
    m_cancelled.store(false);
    emit busyChanged();

    m_thread = std::make_unique<std::thread>([this, job, service]() {
        const int rc = runPam(*job, service);
        secureZero(job->password.data(), job->password.size());
        const bool cancelled = m_cancelled.load();
        const QString message = QString::fromStdString(job->message);

        // Marshal back to the thread that owns this QObject.
        QMetaObject::invokeMethod(this, [this, rc, message, cancelled]() {
            m_busy.store(false);
            emit busyChanged();
            if (!cancelled)
                emit finished(rc == PAM_SUCCESS, message);
        }, Qt::QueuedConnection);
    });
}

void PamAuthenticator::cancel()
{
    m_cancelled.store(true);
}

int PamAuthenticator::conversation(int numMsg, const pam_message **msg,
                                   pam_response **resp, void *appdata)
{
    auto *job = static_cast<Job *>(appdata);
    if (!job || numMsg <= 0 || numMsg > PAM_MAX_NUM_MSG)
        return PAM_CONV_ERR;

    auto *reply = static_cast<pam_response *>(
        std::calloc(static_cast<std::size_t>(numMsg), sizeof(pam_response)));
    if (!reply)
        return PAM_BUF_ERR;
    *resp = reply;

    for (int i = 0; i < numMsg; ++i) {
        const char *text = (msg[i] && msg[i]->msg) ? msg[i]->msg : "";
        switch (msg[i]->msg_style) {
        case PAM_PROMPT_ECHO_OFF:
        case PAM_PROMPT_ECHO_ON:
            reply[i].resp = strdup(job->password.c_str());
            reply[i].resp_retcode = 0;
            break;
        case PAM_ERROR_MSG:
            job->message = text;
            break;
        case PAM_TEXT_INFO:
            if (job->message.empty())
                job->message = text;
            break;
        default:
            break;
        }
    }
    return PAM_SUCCESS;
}

int PamAuthenticator::runPam(Job &job, const std::string &service)
{
    pam_handle_t *handle = nullptr;
    pam_conv conv{&PamAuthenticator::conversation, &job};

    int rc = pam_start(service.c_str(), job.user.c_str(), &conv, &handle);
    qDebug() << "PAM: pam_start rc" << rc;
    if (rc != PAM_SUCCESS) {
        const char *raw = handle ? pam_strerror(handle, rc) : nullptr;
        job.message = friendlyError(rc, raw ? std::string(raw) : std::string()).toStdString();
        if (handle)
            pam_end(handle, rc);
        return rc;
    }

    rc = pam_authenticate(handle, 0);
    qDebug() << "PAM: pam_authenticate rc" << rc;

    if (rc != PAM_SUCCESS)
        job.message = friendlyError(rc, job.message).toStdString();

    pam_end(handle, rc);
    return rc;
}

QString PamAuthenticator::friendlyError(int rc, const std::string &fallback)
{
    switch (rc) {
    case PAM_AUTH_ERR:            return QStringLiteral("Wrong password");
    case PAM_MAXTRIES:            return QStringLiteral("Too many failed attempts");
    case PAM_NEW_AUTHTOK_REQD:    return QStringLiteral("Password change required");
    case PAM_ACCT_EXPIRED:        return QStringLiteral("Account expired");
    case PAM_CRED_INSUFFICIENT:   return QStringLiteral("Insufficient credentials");
    case PAM_AUTHINFO_UNAVAIL:    return QStringLiteral("Authentication information unavailable");
    case PAM_USER_UNKNOWN:        return QStringLiteral("Unknown user");
    case PAM_PERM_DENIED:         return QStringLiteral("Permission denied");
    case PAM_ABORT:               return QStringLiteral("Authentication cancelled");
    case PAM_CONV_ERR:            return QStringLiteral("Authentication conversation error");
    default:
        if (!fallback.empty())
            return QString::fromStdString(fallback);
        return QStringLiteral("Authentication failed");
    }
}

void PamAuthenticator::joinThread()
{
    if (m_thread && m_thread->joinable()) {
        m_thread->join();
        m_thread.reset();
    }
}
