#include "PowerService.h"

#include "PowerSession.h"

PowerService::PowerService(PowerSession *parent)
    : QDBusAbstractAdaptor(parent)
{
    // Relay PowerSession's Visible(bool) / ChangKey(QString) verbatim.
    setAutoRelaySignals(true);
}

bool PowerService::visible() const
{
    return static_cast<PowerSession *>(parent())->visible();
}

void PowerService::Show()
{
    static_cast<PowerSession *>(parent())->show();
}

void PowerService::Shutdown()
{
    static_cast<PowerSession *>(parent())->shutdown();
}

void PowerService::Restart()
{
    static_cast<PowerSession *>(parent())->restart();
}

void PowerService::Logout()
{
    static_cast<PowerSession *>(parent())->logout();
}

void PowerService::Suspend()
{
    static_cast<PowerSession *>(parent())->suspend();
}

void PowerService::Hibernate()
{
    static_cast<PowerSession *>(parent())->hibernate();
}

void PowerService::SwitchUser()
{
    static_cast<PowerSession *>(parent())->switchUser();
}

void PowerService::Lock()
{
    static_cast<PowerSession *>(parent())->lock();
}

void PowerService::UpdateAndShutdown()
{
    static_cast<PowerSession *>(parent())->updateAndShutdown();
}

void PowerService::UpdateAndReboot()
{
    static_cast<PowerSession *>(parent())->updateAndReboot();
}
