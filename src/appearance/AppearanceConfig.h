#pragma once

#include <QFont>
#include <QObject>

namespace Dtk::Core {
class DConfig;
}

/**
 * Reads the lock screen's typography settings from DConfig (app id
 * `org.lumina.lock`) and exposes them to QML as numeric QFont weights plus the
 * clock/date font sizes.
 *
 * Same contract as WallpaperConfig: the control-center plugin writes the keys
 * and the resident lock picks them up live, so the clock's type can be tuned
 * without restarting the session.
 */
class AppearanceConfig : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int clockWeight READ clockWeight NOTIFY changed)
    Q_PROPERTY(int dateWeight READ dateWeight NOTIFY changed)
    Q_PROPERTY(int clockFontSize READ clockFontSize NOTIFY changed)
    Q_PROPERTY(int dateFontSize READ dateFontSize NOTIFY changed)

public:
    explicit AppearanceConfig(QObject *parent = nullptr);

    int clockWeight() const { return m_clockWeight; }
    int dateWeight() const { return m_dateWeight; }
    /** Reference pixels at a 1080px-tall screen; QML scales to the real one. */
    int clockFontSize() const { return m_clockFontSize; }
    int dateFontSize() const { return m_dateFontSize; }

signals:
    void changed();

private:
    void reload();
    void onValueChanged(const QString &key);

    Dtk::Core::DConfig *m_config = nullptr;
    int m_clockWeight = QFont::Light;
    int m_dateWeight = QFont::Medium;
    int m_clockFontSize = 150;
    int m_dateFontSize = 27;
};
