// SPDX-License-Identifier: MIT
//
// The lock-state report dde-quick-login depends on (LockSession::reportLockState).
//
// Quick login starts the lock with `-lq` and only sends READY=1 to systemd
// (cancelling the timer that would log the user straight back out) once
// LockedChanged(true) arrives from org.deepin.dde.SessionManager1. A lock that
// never reports leaves the session looking unlocked and gets the login thrown
// away, so this contract is worth pinning down: it is the one part of the fix
// that cannot be caught by a compile or a smoke test.
//
// Two roles in one binary, because the two halves must not share a process:
// LockSession reaches the session manager through QDBusInterface, whose
// introspection call is synchronous, and a synchronous call to a name owned by
// the same thread deadlocks. So run.sh starts `--stub` as its own process and
// then runs the driver against it.
//
//     tests/lock-state-report/run.sh

#include "auth/PamAuthenticator.h"
#include "session/LockSession.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>
#include <QElapsedTimer>

#include <cstdio>

namespace {

class SessionManagerRecorder : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.deepin.dde.SessionManager1")

public:
    using QObject::QObject;

public slots:
    void SetLocked(bool locked)
    {
        std::printf("SetLocked(%s)\n", locked ? "true" : "false");
        std::fflush(stdout);
    }
};

// The reports are asyncCall()s, so the loop has to turn for them to leave and
// come back.
void spin(int ms)
{
    QElapsedTimer timer;
    timer.start();
    while (timer.elapsed() < ms)
        QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
}

// Be the session manager and print every SetLocked that arrives.
int runStub()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    SessionManagerRecorder recorder;
    if (!bus.registerService(QStringLiteral("org.deepin.dde.SessionManager1"))
        || !bus.registerObject(QStringLiteral("/org/deepin/dde/SessionManager1"), &recorder,
                               QDBusConnection::ExportAllSlots)) {
        qWarning().noquote() << "cannot own the session manager name:"
                             << bus.lastError().message();
        return 77; // no session bus to test against
    }

    std::printf("stub ready\n");
    std::fflush(stdout);
    return QCoreApplication::exec();
}

// Drive the transitions quick login cares about. run.sh compares what the stub
// received with the sequence below, in this order:
//
//   true   the startup report — a `-lq` launch starts locked and never
//          transitions, so this is the only chance to send the `true`
//   false  unlock
//   true   lock again
//   false  unlock again
//
// The second reportLockState() must add nothing: a repeat that moved no state
// should stay off the bus.
int runDriver()
{
    PamAuthenticator auth;
    LockSession session(&auth);

    session.reportLockState();
    spin(300);
    session.reportLockState();
    spin(300);
    session.unlock();
    spin(300);
    session.lock();
    spin(300);
    session.unlock();
    spin(300);

    std::printf("driver done\n");
    return 0;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    return (argc > 1 && QString::fromLocal8Bit(argv[1]) == QLatin1String("--stub"))
               ? runStub()
               : runDriver();
}

#include "main.moc"
