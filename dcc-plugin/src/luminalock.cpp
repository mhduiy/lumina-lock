// SPDX-License-Identifier: GPL-3.0-or-later
#include "luminalock.h"

#include "dccfactory.h"

#include <DConfig>

#include <QFileInfo>
#include <QVariant>

namespace {
const QString kAppId = QStringLiteral("org.lumina.lock");
const QString kTypeKey = QStringLiteral("wallpaperType");
const QString kImageKey = QStringLiteral("wallpaperPath");
const QString kVideoKey = QStringLiteral("videoPath");
const QString kPosterKey = QStringLiteral("posterPath");
const QString kVideoPoolKey = QStringLiteral("videoPaths");
const QString kClockPositionXKey = QStringLiteral("clockPositionX");
const QString kClockPositionYKey = QStringLiteral("clockPositionY");
const QString kClockWeightKey = QStringLiteral("clockWeight");
const QString kDateWeightKey = QStringLiteral("dateWeight");
const QString kClockSizeKey = QStringLiteral("clockFontSize");
const QString kDateSizeKey = QStringLiteral("dateFontSize");

constexpr int kPositionDefault = 50;
} // namespace

Luminalock::Luminalock(QObject *parent)
    : QObject(parent)
    , m_config(Dtk::Core::DConfig::create(kAppId, kAppId, QString(), this))
{
    reload();
}

void Luminalock::reload()
{
    if (!m_config || !m_config->isValid())
        return;
    // Reads go through configValue() so that a key the installed schema does not
    // have is never handed to DConfig at all — see its comment for why that
    // matters (dtk6 crashes rather than returning the fallback on the file
    // backend). A control center running ahead of the installed lock package must
    // show "the setting is not there", not die.
    m_wallpaperType = configValue(kTypeKey, QStringLiteral("none")).toString();
    m_wallpaperPath = configValue(kImageKey, QString()).toString();
    m_videoPath = configValue(kVideoKey, QString()).toString();
    m_posterPath = configValue(kPosterKey, QString()).toString();
    m_videoPaths = configValue(kVideoPoolKey, QStringList()).toStringList();
    m_clockPositionX = configValue(kClockPositionXKey, kPositionDefault).toInt();
    m_clockPositionY = configValue(kClockPositionYKey, kPositionDefault).toInt();
    m_clockWeight = configValue(kClockWeightKey, QStringLiteral("light")).toString();
    m_dateWeight = configValue(kDateWeightKey, QStringLiteral("medium")).toString();
    m_clockFontSize = configValue(kClockSizeKey, 150).toInt();
    m_dateFontSize = configValue(kDateSizeKey, 27).toInt();
    Q_EMIT wallpaperTypeChanged(m_wallpaperType);
    Q_EMIT wallpaperPathChanged(m_wallpaperPath);
    Q_EMIT videoPathChanged(m_videoPath);
    Q_EMIT posterPathChanged(m_posterPath);
    Q_EMIT videoPathsChanged(m_videoPaths);
    Q_EMIT clockPositionXChanged(m_clockPositionX);
    Q_EMIT clockPositionYChanged(m_clockPositionY);
    Q_EMIT clockWeightChanged(m_clockWeight);
    Q_EMIT dateWeightChanged(m_dateWeight);
    Q_EMIT clockFontSizeChanged(m_clockFontSize);
    Q_EMIT dateFontSizeChanged(m_dateFontSize);
}

void Luminalock::setConfigValue(const QString &key, const QVariant &value)
{
    writeConfig(key, value);
    reload();
}

bool Luminalock::configKeyAvailable(const QString &key) const
{
    return m_config && m_config->isValid() && m_config->keyList().contains(key);
}

QVariant Luminalock::configValue(const QString &key, const QVariant &fallback) const
{
    // Never hand a missing key to DConfig: on the file backend dtk6 dereferences
    // a null pointer instead of returning the fallback, so this is the difference
    // between "the setting is not there" and a dead control center.
    if (!configKeyAvailable(key))
        return fallback;
    return m_config->value(key, fallback);
}

bool Luminalock::writeConfig(const QString &key, const QVariant &value)
{
    if (!m_config || !m_config->isValid())
        return false;
    if (!configKeyAvailable(key)) {
        // dtk6's setValue() returns void, and the daemon refuses a key the
        // installed schema does not have without saying so. Left at that, every
        // control on the page would move and change nothing.
        qWarning().noquote() << "luminalock: config key not in the installed schema:" << key;
        setLastError(tr("当前安装的锁屏包没有 %1 配置项（schema 未升级），设置未生效。").arg(key));
        return false;
    }
    m_config->setValue(key, value);
    return true;
}

void Luminalock::setLastError(const QString &error)
{
    if (m_lastError == error)
        return;
    m_lastError = error;
    Q_EMIT lastErrorChanged(m_lastError);
}

void Luminalock::setType(const QString &type)
{
    setConfigValue(kTypeKey, type);
}

bool Luminalock::setFile(const QString &kind, const QUrl &url)
{
    if (!m_config || !m_config->isValid() || !url.isLocalFile())
        return false;

    const QFileInfo file(url.toLocalFile());
    if (!file.isAbsolute() || !file.isFile() || !file.isReadable())
        return false;

    QString key;
    if (kind == QLatin1String("static"))
        key = kImageKey;
    else if (kind == QLatin1String("video"))
        key = kVideoKey;
    else if (kind == QLatin1String("poster"))
        key = kPosterKey;
    else
        return false;

    m_config->setValue(key, file.absoluteFilePath());
    if (kind != QLatin1String("poster"))
        m_config->setValue(kTypeKey, kind);
    reload();
    return true;
}

bool Luminalock::addVideo(const QUrl &url)
{
    if (!m_config || !m_config->isValid()) {
        setLastError(tr("无法访问锁屏配置（org.lumina.lock）。"));
        return false;
    }
    if (!url.isLocalFile()) {
        setLastError(tr("只能添加本地视频文件。"));
        return false;
    }

    const QFileInfo file(url.toLocalFile());
    if (!file.isAbsolute() || !file.isFile() || !file.isReadable()) {
        setLastError(tr("无法读取该文件，请检查路径与权限。"));
        return false;
    }
    if (!configKeyAvailable(kVideoPoolKey)) {
        setLastError(tr("当前安装的锁屏包没有 videoPaths 配置项（schema 未升级），视频列表存不进去。"));
        return false;
    }

    // Adding switches the wallpaper over to the pool, the same way picking a
    // single video switches it to `video`: the list being built is what the user
    // wants to see. Re-adding an entry that is already in the list is a no-op
    // rather than a duplicate, so the draw cannot be weighted by accident.
    QStringList paths = m_videoPaths;
    if (!paths.contains(file.absoluteFilePath()))
        paths.append(file.absoluteFilePath());
    writeConfig(kVideoPoolKey, paths);
    writeConfig(kTypeKey, QStringLiteral("video-random"));

    reload();
    // setValue() returns void, so the only proof the entry landed is reading it
    // back: the daemon refuses unknown keys silently, and a dialog that closes
    // with an empty list is exactly what that looks like from the outside.
    if (!m_videoPaths.contains(file.absoluteFilePath())) {
        setLastError(tr("写入 videoPaths 失败，视频列表没有保存。"));
        return false;
    }
    setLastError(QString());
    return true;
}

void Luminalock::removeVideo(const QString &path)
{
    if (!m_config || !m_config->isValid() || !configKeyAvailable(kVideoPoolKey))
        return;

    QStringList paths = m_videoPaths;
    if (!paths.removeAll(path))
        return;

    writeConfig(kVideoPoolKey, paths);
    // An emptied pool has nothing to play; stepping back to the built-in
    // wallpaper beats leaving the lock pointed at a video it can no longer load.
    if (paths.isEmpty() && m_wallpaperType == QLatin1String("video-random"))
        writeConfig(kTypeKey, QStringLiteral("none"));
    reload();
    if (m_videoPaths.contains(path))
        setLastError(tr("写入 videoPaths 失败，这一条没有删掉。"));
    else
        setLastError(QString());
}

void Luminalock::setClockPositionX(int percent)
{
    setConfigValue(kClockPositionXKey, percent);
}

void Luminalock::setClockPositionY(int percent)
{
    setConfigValue(kClockPositionYKey, percent);
}

void Luminalock::setClockWeight(const QString &weight)
{
    setConfigValue(kClockWeightKey, weight);
}

void Luminalock::setDateWeight(const QString &weight)
{
    setConfigValue(kDateWeightKey, weight);
}

void Luminalock::setClockFontSize(int size)
{
    setConfigValue(kClockSizeKey, size);
}

void Luminalock::setDateFontSize(int size)
{
    setConfigValue(kDateSizeKey, size);
}

void Luminalock::resetToDefault()
{
    m_config->setValue(kTypeKey, QStringLiteral("none"));
    m_config->setValue(kImageKey, QString());
    m_config->setValue(kVideoKey, QString());
    m_config->setValue(kPosterKey, QString());
    m_config->setValue(kVideoPoolKey, QStringList());
    m_config->setValue(kClockPositionXKey, kPositionDefault);
    m_config->setValue(kClockPositionYKey, kPositionDefault);
    m_config->setValue(kClockWeightKey, QStringLiteral("light"));
    m_config->setValue(kDateWeightKey, QStringLiteral("medium"));
    m_config->setValue(kClockSizeKey, 150);
    m_config->setValue(kDateSizeKey, 27);
    reload();
}

DCC_FACTORY_CLASS(Luminalock)
#include "luminalock.moc"
