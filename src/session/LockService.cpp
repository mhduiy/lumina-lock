#include "LockService.h"

#include "LockSession.h"

LockService::LockService(LockSession *parent)
    : QDBusAbstractAdaptor(parent)
{
    // Relay LockSession's Visible(bool) / ChangKey(QString) signals verbatim.
    setAutoRelaySignals(true);
}

bool LockService::visible() const
{
    return static_cast<LockSession *>(parent())->visible();
}

void LockService::Show()
{
    static_cast<LockSession *>(parent())->show();
}

void LockService::ShowUserList()
{
    static_cast<LockSession *>(parent())->showUserList();
}

void LockService::ShowAuth(bool active)
{
    static_cast<LockSession *>(parent())->showAuth(active);
}

void LockService::Suspend(bool enable)
{
    static_cast<LockSession *>(parent())->suspend(enable);
}

void LockService::Hibernate(bool enable)
{
    static_cast<LockSession *>(parent())->hibernate(enable);
}
