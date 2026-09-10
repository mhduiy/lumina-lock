// Standalone PAM backend test: verifies the PamAuthenticator worker-thread /
// conversation / result-marshalling path without any GUI.
//
// Usage:  echo "<password>" | lumina-pam-test [user] [--twice]
// The password is read from stdin (never from argv) so it does not show up in
// the process list. `--twice` runs two sequential attempts as a regression
// test for worker-thread reaping (the second attempt used to trip
// std::terminate). Exit code: 0 = accepted, 1 = rejected, 2 = timeout.

#include "auth/PamAuthenticator.h"

#include <QCoreApplication>
#include <QTimer>

#include <cstdio>
#include <pwd.h>
#include <unistd.h>

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);

    QString user;
    bool twice = false;
    for (int i = 1; i < argc; ++i) {
        const QString arg = QString::fromLocal8Bit(argv[i]);
        if (arg == QLatin1String("--twice"))
            twice = true;
        else
            user = arg;
    }
    if (user.isEmpty()) {
        if (const struct passwd *pw = getpwuid(getuid()))
            user = QString::fromLocal8Bit(pw->pw_name);
    }
    if (user.isEmpty()) {
        std::fprintf(stderr, "cannot determine user\n");
        return 2;
    }

    QByteArray password;
    char buf[512];
    while (std::fgets(buf, sizeof(buf), stdin))
        password.append(buf);
    while (!password.isEmpty()
           && (password.endsWith('\n') || password.endsWith('\r')))
        password.chop(1);

    PamAuthenticator auth;
    const int total = twice ? 2 : 1;
    int attempt = 0;

    QObject::connect(&auth, &PamAuthenticator::finished, &app,
                     [&](bool ok, const QString &message) {
                         std::printf("PAM attempt %d %s: %s\n", attempt + 1,
                                     ok ? "ACCEPT" : "REJECT",
                                     qPrintable(message));
                         std::fflush(stdout);
                         ++attempt;
                         if (attempt >= total) {
                             password.fill('\0');
                             app.exit(ok ? 0 : 1);
                         } else {
                             // A second attempt must not crash even though the
                             // first worker thread has already returned.
                             auth.authenticate(user, password);
                         }
                     });

    // Safety net in case PAM blocks unexpectedly. Generous on purpose: the
    // login service may apply a per-failure delay (pam_faildelay).
    QTimer::singleShot(15000, &app, [&app]() {
        std::printf("PAM TIMEOUT\n");
        std::fflush(stdout);
        app.exit(2);
    });

    auth.authenticate(user, password);

    return app.exec();
}
