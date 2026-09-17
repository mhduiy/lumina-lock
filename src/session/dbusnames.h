#pragma once

#include <QString>

// D-Bus names matching dde-lock so other DDE components keep working when this
// lock replaces dde-lock.
//
// Deepin 6.x (the "snipe" generation, e.g. dde-session-shell 6.0.66) uses the
// org.deepin.dde.*1 naming; classic DDE used com.deepin.dde.*. Select with
// -DDSS_SNIPE=ON/OFF at configure time. Default matches the deployed system.
#ifdef DSS_SNIPE
#  define LOCK_FRONT_SERVICE   QStringLiteral("org.deepin.dde.LockFront1")
#  define LOCK_FRONT_PATH      QStringLiteral("/org/deepin/dde/LockFront1")
#  define LOCK_FRONT_INTERFACE QStringLiteral("org.deepin.dde.LockFront1")
#  define LOCK_POWER_SERVICE   QStringLiteral("org.deepin.dde.Power1")
#  define LOCK_POWER_PATH      QStringLiteral("/org/deepin/dde/Power1")
#else
#  define LOCK_FRONT_SERVICE   QStringLiteral("com.deepin.dde.lockFront")
#  define LOCK_FRONT_PATH      QStringLiteral("/com/deepin/dde/lockFront")
#  define LOCK_FRONT_INTERFACE QStringLiteral("com.deepin.dde.lockFront")
#  define LOCK_POWER_SERVICE   QStringLiteral("com.deepin.dde.Power")
#  define LOCK_POWER_PATH      QStringLiteral("/com/deepin/dde/Power")
#endif

// The power menu only targets the 6.x generation: that is what is deployed, and
// there is nothing else to support. These names are used verbatim (as literals,
// where moc needs one) rather than behind the DSS_SNIPE switch above.
#define POWER_FRONT_SERVICE   QStringLiteral("org.deepin.dde.ShutdownFront1")
#define POWER_FRONT_PATH      QStringLiteral("/org/deepin/dde/ShutdownFront1")
#define POWER_FRONT_INTERFACE QStringLiteral("org.deepin.dde.ShutdownFront1")
#define SESSION_MGR_SERVICE   QStringLiteral("org.deepin.dde.SessionManager1")
#define SESSION_MGR_PATH      QStringLiteral("/org/deepin/dde/SessionManager1")
#define SESSION_MGR_INTERFACE QStringLiteral("org.deepin.dde.SessionManager1")

// Session-manager methods used by the power menu. In the 6.x generation these
// live on org.deepin.dde.SessionManager1; RequestShutdown/RequestReboot are the
// same names the lock's power actions use.
#define SESSION_MGR_REQUEST_SHUTDOWN  QStringLiteral("RequestShutdown")
#define SESSION_MGR_REQUEST_REBOOT    QStringLiteral("RequestReboot")
#define SESSION_MGR_REQUEST_LOGOUT    QStringLiteral("RequestLogout")
#define SESSION_MGR_REQUEST_SUSPEND   QStringLiteral("RequestSuspend")
#define SESSION_MGR_REQUEST_HIBERNATE QStringLiteral("RequestHibernate")

// "Update and shut down" / "update and restart" are the update daemon's
// business, not the session's: lastore takes a JSON request and brings the
// machine down itself once the upgrade has run. Both live on the system bus.
#define LASTORE_SERVICE   QStringLiteral("com.deepin.lastore")
#define LASTORE_PATH      QStringLiteral("/com/deepin/lastore")
#define LASTORE_INTERFACE QStringLiteral("com.deepin.lastore.Manager")
#define SYS_POWER_SERVICE QStringLiteral("com.deepin.system.Power")
#define SYS_POWER_PATH    QStringLiteral("/com/deepin/system/Power")
