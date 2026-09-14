#pragma once

#include <QObject>
#include <QUrl>

class WallpaperManager;

namespace Dtk::Core {
class DConfig;
}

/**
 * Reads the lock wallpaper settings from DConfig (app id `org.lumina.lock`)
 * and applies them to a WallpaperManager. This is the runtime half of the
 * control-center integration: the dcc plugin writes the same keys, and the
 * resident lock picks them up — on startup, and live via DConfig change
 * notifications.
 *
 * The wall between "config" and "content" mirrors WallpaperManager's own
 * boundary: this class never touches rendering or authentication data.
 */
class WallpaperConfig : public QObject
{
    Q_OBJECT

public:
    explicit WallpaperConfig(QObject *parent = nullptr);

    /** Apply the DConfig state to `wm`; falls back to the built-in wallpaper. */
    void applyTo(WallpaperManager &wm);

signals:
    /** Emitted when any wallpaper key changes in DConfig. */
    void changed();

private:
    void onValueChanged(const QString &key);

    Dtk::Core::DConfig *m_config = nullptr;
};
