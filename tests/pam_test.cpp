// Standalone PAM backend test: verifies the PamAuthenticator worker-thread /
// conversation / result-marshalling path without any GUI.
//
// Usage:  echo "<password>" | lumina-pam-test [user]
// The password is read from stdin (never from argv) so it does not show up in
// the process list. Exit code: 0 = accepted, 1 = rejected, 2 = timeout.

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
    if (argc > 1) {
        user = QString::fromLocal8Bit(argv[1]);
    } else if (const struct passwd *pw = getpwuid(getuid())) {
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

    QObject::connect(&auth, &PamAuthenticator::finished,
                     &app, [&app](bool ok, const QString &message) {
                         std::printf("PAM %s: %s\n", ok ? "ACCEPT" : "REJECT",
                                     qPrintable(message));
                         std::fflush(stdout);
                         app.exit(ok ? 0 : 1);
                     });

    // Safety net in case PAM blocks unexpectedly.
    QTimer::singleShot(5000, &app, [&app]() {
        std::printf("PAM TIMEOUT\n");
        std::fflush(stdout);
        app.exit(2);
    });

    auth.authenticate(user, password);
    password.fill('\0');

    return app.exec();
}
