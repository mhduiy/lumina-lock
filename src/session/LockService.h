#pragma once

#include <QDBusAbstractAdaptor>
#include <QString>

class LockSession;

/**
 * D-Bus adaptor exposing dde-lock's `lockFront` interface so other DDE
 * components (session manager, startdde, dde-shell, …) can keep driving the
 * lock screen unchanged.
 *
 * Mirrors DBusLockFrontService from dde-session-shell.
 */
class LockService : public QDBusAbstractAdaptor
{
    Q_OBJECT
#ifdef DSS_SNIPE
    Q_CLASSINFO("D-Bus Interface", "org.deepin.dde.LockFront1")
#else
    Q_CLASSINFO("D-Bus Interface", "com.deepin.dde.lockFront")
#endif

public:
    explicit LockService(LockSession *parent);

    Q_PROPERTY(bool Visible READ visible)
    bool visible() const;

public slots: // METHODS
    void Show();
    void ShowUserList();
    void ShowAuth(bool active);
    void Suspend(bool enable);
    void Hibernate(bool enable);

signals:
    void ChangKey(QString key);
    void Visible(bool visible);
};
