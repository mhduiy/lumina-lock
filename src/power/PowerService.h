#pragma once

#include <QDBusAbstractAdaptor>

class PowerSession;

// The `org.deepin.dde.ShutdownFront1` surface, with the same method and signal
// names dde-lock exposes — the dock's power button, the launcher and the power
// key all call into this. The interface name is a literal because Q_CLASSINFO
// needs one.
class PowerService : public QDBusAbstractAdaptor
{
    Q_OBJECT

    Q_CLASSINFO("D-Bus Interface", "org.deepin.dde.ShutdownFront1")
    Q_PROPERTY(bool Visible READ visible)

public:
    explicit PowerService(PowerSession *parent);

    bool visible() const;

public Q_SLOTS:
    void Show();
    void Shutdown();
    void Restart();
    void Logout();
    void Suspend();
    void Hibernate();
    void SwitchUser();
    void Lock();
    void UpdateAndShutdown();
    void UpdateAndReboot();
};
