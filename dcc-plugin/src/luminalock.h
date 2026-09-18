// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef LUMINALOCK_H
#define LUMINALOCK_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariant>

namespace Dtk::Core {
class DConfig;
}

/**
 * Control-center plugin backend ("dccData" in QML) for the Lumina Lock
 * settings page. Reads/writes the org.lumina.lock DConfig that the lock itself
 * consumes — the lock wallpaper and the clock typography. QML owns the dialogs;
 * this backend only validates and persists selected local files.
 *
 * The random-video pool is a plain list of local paths (`videoPaths`): the lock
 * re-draws from it on every lock, so nothing here has to decide which video
 * wins. Adding an entry switches the wallpaper type over to `video-random`,
 * mirroring how picking a single video switches it to `video`.
 */
class Luminalock : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString wallpaperType READ wallpaperType NOTIFY wallpaperTypeChanged)
    Q_PROPERTY(QString wallpaperPath READ wallpaperPath NOTIFY wallpaperPathChanged)
    Q_PROPERTY(QString videoPath READ videoPath NOTIFY videoPathChanged)
    Q_PROPERTY(QString posterPath READ posterPath NOTIFY posterPathChanged)
    Q_PROPERTY(QStringList videoPaths READ videoPaths NOTIFY videoPathsChanged)
    Q_PROPERTY(int clockPositionX READ clockPositionX NOTIFY clockPositionXChanged)
    Q_PROPERTY(int clockPositionY READ clockPositionY NOTIFY clockPositionYChanged)
    Q_PROPERTY(QString clockWeight READ clockWeight NOTIFY clockWeightChanged)
    Q_PROPERTY(QString dateWeight READ dateWeight NOTIFY dateWeightChanged)
    Q_PROPERTY(int clockFontSize READ clockFontSize NOTIFY clockFontSizeChanged)
    Q_PROPERTY(int dateFontSize READ dateFontSize NOTIFY dateFontSizeChanged)
    /**
     * Why the last action failed, in a form fit for the dialog to show. Empty
     * after a successful one. Needed because DConfig::setValue() returns void in
     * dtk6: a key the installed schema does not have is refused by the daemon
     * *silently*, so without a read-back an add would look like it worked and the
     * list would just stay empty.
     */
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit Luminalock(QObject *parent = nullptr);

    QString wallpaperType() const { return m_wallpaperType; }
    QString wallpaperPath() const { return m_wallpaperPath; }
    QString videoPath() const { return m_videoPath; }
    QString posterPath() const { return m_posterPath; }
    QStringList videoPaths() const { return m_videoPaths; }
    int clockPositionX() const { return m_clockPositionX; }
    int clockPositionY() const { return m_clockPositionY; }
    QString clockWeight() const { return m_clockWeight; }
    QString dateWeight() const { return m_dateWeight; }
    int clockFontSize() const { return m_clockFontSize; }
    int dateFontSize() const { return m_dateFontSize; }
    QString lastError() const { return m_lastError; }

    Q_INVOKABLE void setType(const QString &type);
    Q_INVOKABLE bool setFile(const QString &kind, const QUrl &url);
    /** Append a video to the random pool; false when the file cannot be used. */
    Q_INVOKABLE bool addVideo(const QUrl &url);
    /** Drop one entry from the random pool. */
    Q_INVOKABLE void removeVideo(const QString &path);
    Q_INVOKABLE void setClockPositionX(int percent);
    Q_INVOKABLE void setClockPositionY(int percent);
    Q_INVOKABLE void setClockWeight(const QString &weight);
    Q_INVOKABLE void setDateWeight(const QString &weight);
    Q_INVOKABLE void setClockFontSize(int size);
    Q_INVOKABLE void setDateFontSize(int size);
    Q_INVOKABLE void resetToDefault();

Q_SIGNALS:
    void wallpaperTypeChanged(const QString &type);
    void wallpaperPathChanged(const QString &path);
    void videoPathChanged(const QString &path);
    void posterPathChanged(const QString &path);
    void videoPathsChanged(const QStringList &paths);
    void clockPositionXChanged(int percent);
    void clockPositionYChanged(int percent);
    void clockWeightChanged(const QString &weight);
    void dateWeightChanged(const QString &weight);
    void clockFontSizeChanged(int size);
    void dateFontSizeChanged(int size);
    void lastErrorChanged(const QString &error);

private:
    void reload();
    void setConfigValue(const QString &key, const QVariant &value);
    /** True when the installed schema knows this key at all. */
    bool configKeyAvailable(const QString &key) const;
    /**
     * Read a key, or the fallback when the installed schema does not have it.
     *
     * The availability check is not belt-and-braces: dtk6's
     * DConfigFile::value() dereferences a null pointer for a key the meta file
     * does not have, so on the file backend a plain read of a missing key takes
     * the whole process down. Never call value() without asking first.
     */
    QVariant configValue(const QString &key, const QVariant &fallback) const;
    /** Write a key; false (and lastError) when the schema does not have it. */
    bool writeConfig(const QString &key, const QVariant &value);
    void setLastError(const QString &error);

    Dtk::Core::DConfig *m_config = nullptr;
    QString m_wallpaperType;
    QString m_wallpaperPath;
    QString m_videoPath;
    QString m_posterPath;
    QStringList m_videoPaths;
    int m_clockPositionX = 50;
    int m_clockPositionY = 50;
    QString m_clockWeight;
    QString m_dateWeight;
    int m_clockFontSize = 150;
    int m_dateFontSize = 27;
    QString m_lastError;
};

#endif // LUMINALOCK_H
