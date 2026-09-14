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
