#pragma once

#include <QObject>
#include <QVariant>

class LockSession;
class ScreenManager;

// The session power menu.
//
// dde-lock provides this as `org.deepin.dde.ShutdownFront1`: the dock, the
// launcher and the power key all reach it over D-Bus, and its .service file
// activates the very same binary as the lock. This class is that service's
// behaviour; the surface it drives is qml/PowerScreen.qml, drawn in a window of
// its own (see ScreenManager::showPowerMenu) so that it never inherits the lock
// window's lifecycle.
class PowerSession : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool visible READ visible NOTIFY Visible)
    Q_PROPERTY(QVariantList options READ options NOTIFY optionsChanged)

public:
    explicit PowerSession(QObject *parent = nullptr);

    void setLockSession(LockSession *session) { m_lockSession = session; }
    void setScreenManager(ScreenManager *screens) { m_screens = screens; }

    bool visible() const { return m_visible; }
    QVariantList options() const { return m_options; }

    // --- the dde-lock surface (org.deepin.dde.ShutdownFront1) ---------------
    // Each of these opens the menu with its row armed, so a request that came
    // from elsewhere still gives the person at the machine a beat to cancel.
    //
    // These two are Q_INVOKABLE because the lock screen's own corner buttons
    // call them: a plain public method is not reachable from QML. The D-Bus
    // adaptor is unaffected — it declares its own slots and forwards here.
    Q_INVOKABLE void show();
    void shutdown();
    void restart();
    void logout();
    void suspend();
    void hibernate();
    void lock();
    // Switching users does not open this menu: it hands the seat to the greeter.
    Q_INVOKABLE void switchUser();
    void updateAndShutdown();
    void updateAndReboot();

    Q_INVOKABLE void dismiss();
    // Called by the scene when its exit animation has played; the window is
    // hidden then, not when dismiss() is called.
    Q_INVOKABLE void exitFinished();
    // Runs one row. The scene only calls this once its row is armed.
    Q_INVOKABLE void activate(const QString &key);
    // Relays the D-Bus ChangKey the way dde-lock does when the highlight moves.
    Q_INVOKABLE void highlight(const QString &key);

Q_SIGNALS:
    // Relayed verbatim to D-Bus by PowerService (see setAutoRelaySignals).
    void Visible(bool visible);
    void ChangKey(const QString &key);

    void optionsChanged();
    // The scene should arm this row (used when a request arrives over D-Bus).
    void armRequested(const QString &key);
    // The menu could not act, and stays up. Shown inline, then it fades.
    void failed(const QString &reason);

private:
    void rebuildOptions();
    // Availability is *cached*, never fetched on the show path: this runs inside
    // a D-Bus method handler (something called Show), so a synchronous call to
    // the session manager can deadlock against whoever is waiting for our reply
    // — and it holds the keyboard grab while it waits, which looks exactly like
    // a frozen session. Everything here is asynchronous and the menu is built
    // from the last known answers.
    void refreshAvailability();
    void queryCan(const QString &method, bool *slot);
    void queryUpdateMode();
    void queryUpdateState();
    void requestSessionMethod(const QString &method);
    void requestUpdate(bool powerOff);
    static bool dryRun();

    LockSession *m_lockSession = nullptr;
    ScreenManager *m_screens = nullptr;

    bool m_visible = false;
    // Last known answers; the defaults allow everything until told otherwise.
    bool m_canShutdown = true;
    bool m_canReboot = true;
    bool m_canLogout = true;
    bool m_canSuspend = true;
    bool m_canHibernate = true;
    bool m_updatesAvailable = false;
    int m_updateMode = 0;
    // Whether lastore has anything to install — *not* whether it is in some
    // update mode. CheckUpdateMode is a policy setting (5 on a machine with
    // nothing to install, so it says nothing), while UpgradableApps is the list
    // itself. The power rows are worded from this, so it has to mean what it
    // says.
    bool m_updatesPending = false;
    // True when the menu brought the lock surfaces up over an unlocked session,
    // and therefore has to put them back down when it closes.
    bool m_overDesktop = false;

    QVariantList m_options;
};
