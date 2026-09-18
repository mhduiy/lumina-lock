#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariant>
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
 *
 * This is also where the one *policy* lives that the manager should not have to
 * know about: `video-random` selects a video out of a pool instead of naming
 * one, so the choice is resolved here and the manager is only ever handed a
 * concrete video. A new lock re-rolls it (see pickForNewLock), which is what
 * makes "a different video every time the screen locks" work without touching
 * the render path.
 */
class WallpaperConfig : public QObject
{
    Q_OBJECT

public:
    explicit WallpaperConfig(QObject *parent = nullptr);

    /** Apply the DConfig state to `wm`; falls back to the built-in wallpaper. */
    void applyTo(WallpaperManager &wm);

    /**
     * Re-roll the random video for a fresh lock. A no-op unless the configured
     * type is `video-random`; the draw never repeats the video currently set,
     * so two locks in a row cannot look the same.
     */
    void pickForNewLock(WallpaperManager &wm);

signals:
    /** Emitted when any wallpaper key changes in DConfig. */
    void changed();

private:
    void onValueChanged(const QString &key);

    /** The configured type verbatim; `none` when DConfig is unavailable. */
    QString configuredType() const;

    /** Pool entries that exist and are readable, in configured order. */
    QStringList videoPool() const;

    /** Apply `video-random`: pick from the pool, or fall back to the default. */
    void applyRandomVideo(WallpaperManager &wm);

    /**
     * Read a key, or the fallback when the installed schema does not have it.
     *
     * Asking first is not optional: dtk6's DConfigFile::value() dereferences a
     * null pointer for a key the meta file does not have, so a lock package
     * installed next to an older schema would take the lock down with it. A
     * missing key means "this package is newer than the schema", which is a
     * fallback, not a crash.
     */
    QVariant configValue(const QString &key, const QVariant &fallback) const;

    Dtk::Core::DConfig *m_config = nullptr;
    /** Last video handed to the manager, to avoid repeating it on the next draw. */
    QString m_lastRandomVideo;
};
