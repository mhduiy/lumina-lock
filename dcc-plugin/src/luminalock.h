// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef LUMINALOCK_H
#define LUMINALOCK_H

#include <QObject>
#include <QString>
#include <QUrl>

namespace Dtk::Core {
class DConfig;
}

/**
 * Control-center plugin backend ("dccData" in QML) for the Lumina Lock
 * settings page. Reads/writes the org.lumina.lock DConfig that the lock itself
 * consumes — the lock wallpaper and the clock typography. QML owns the dialogs;
 * this backend only validates and persists selected local files.
 */
class Luminalock : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString wallpaperType READ wallpaperType NOTIFY wallpaperTypeChanged)
    Q_PROPERTY(QString wallpaperPath READ wallpaperPath NOTIFY wallpaperPathChanged)
    Q_PROPERTY(QString videoPath READ videoPath NOTIFY videoPathChanged)
    Q_PROPERTY(QString posterPath READ posterPath NOTIFY posterPathChanged)
    Q_PROPERTY(QString clockWeight READ clockWeight NOTIFY clockWeightChanged)
    Q_PROPERTY(QString dateWeight READ dateWeight NOTIFY dateWeightChanged)

public:
    explicit Luminalock(QObject *parent = nullptr);

    QString wallpaperType() const { return m_wallpaperType; }
    QString wallpaperPath() const { return m_wallpaperPath; }
    QString videoPath() const { return m_videoPath; }
    QString posterPath() const { return m_posterPath; }
    QString clockWeight() const { return m_clockWeight; }
    QString dateWeight() const { return m_dateWeight; }

    Q_INVOKABLE void setType(const QString &type);
    Q_INVOKABLE bool setFile(const QString &kind, const QUrl &url);
    Q_INVOKABLE void setClockWeight(const QString &weight);
    Q_INVOKABLE void setDateWeight(const QString &weight);
    Q_INVOKABLE void resetToDefault();

Q_SIGNALS:
    void wallpaperTypeChanged(const QString &type);
    void wallpaperPathChanged(const QString &path);
    void videoPathChanged(const QString &path);
    void posterPathChanged(const QString &path);
    void clockWeightChanged(const QString &weight);
    void dateWeightChanged(const QString &weight);

private:
    void reload();
    void setConfigValue(const QString &key, const QVariant &value);

    Dtk::Core::DConfig *m_config = nullptr;
    QString m_wallpaperType;
    QString m_wallpaperPath;
    QString m_videoPath;
    QString m_posterPath;
    QString m_clockWeight;
    QString m_dateWeight;
};

#endif // LUMINALOCK_H
