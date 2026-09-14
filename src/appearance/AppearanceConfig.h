#pragma once

#include <QFont>
#include <QObject>

namespace Dtk::Core {
class DConfig;
}

/**
 * Reads the lock screen's typography settings from DConfig (app id
 * `org.lumina.lock`) and exposes them to QML as numeric QFont weights.
 *
 * Same contract as WallpaperConfig: the control-center plugin writes the keys
 * and the resident lock picks them up live, so the clock's stroke weight can be
 * tuned without restarting the session.
 */
class AppearanceConfig : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int clockWeight READ clockWeight NOTIFY changed)
    Q_PROPERTY(int dateWeight READ dateWeight NOTIFY changed)

public:
    explicit AppearanceConfig(QObject *parent = nullptr);

    int clockWeight() const { return m_clockWeight; }
    int dateWeight() const { return m_dateWeight; }

signals:
    void changed();

private:
    void reload();
    void onValueChanged(const QString &key);

    Dtk::Core::DConfig *m_config = nullptr;
    int m_clockWeight = QFont::Light;
    int m_dateWeight = QFont::Medium;
};
