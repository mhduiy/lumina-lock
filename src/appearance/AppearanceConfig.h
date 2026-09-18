#pragma once

#include <QFont>
#include <QObject>
#include <QString>
#include <QVariant>

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
    /**
     * Where the clock-and-date block sits, as a fraction of the room it has
     * (0 = flush with the left/top edge, 0.5 = centred, 1 = flush with the
     * right/bottom edge). One position for the pair: they are one column, and
     * moving the time away from its date is not a setting anyone asked for.
     */
    Q_PROPERTY(qreal clockPositionX READ clockPositionX NOTIFY changed)
    Q_PROPERTY(qreal clockPositionY READ clockPositionY NOTIFY changed)

public:
    explicit AppearanceConfig(QObject *parent = nullptr);

    int clockWeight() const { return m_clockWeight; }
    int dateWeight() const { return m_dateWeight; }
    /** Reference pixels at a 1080px-tall screen; QML scales to the real one. */
    int clockFontSize() const { return m_clockFontSize; }
    int dateFontSize() const { return m_dateFontSize; }
    qreal clockPositionX() const { return m_clockPositionX; }
    qreal clockPositionY() const { return m_clockPositionY; }

signals:
    void changed();

private:
    void reload();
    void onValueChanged(const QString &key);
    /**
     * Read a key, or the fallback when the installed schema does not have it.
     *
     * Asking first is not optional: dtk6's DConfigFile::value() dereferences a
     * null pointer for a key the meta file does not have, so a lock package
     * installed next to an older schema would take the lock down with it.
     */
    QVariant configValue(const QString &key, const QVariant &fallback) const;

    Dtk::Core::DConfig *m_config = nullptr;
    int m_clockWeight = QFont::Light;
    int m_dateWeight = QFont::Medium;
    int m_clockFontSize = 150;
    int m_dateFontSize = 27;
    qreal m_clockPositionX = 0.5;
    qreal m_clockPositionY = 0.5;
};
