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
const QString kClockWeightKey = QStringLiteral("clockWeight");
const QString kDateWeightKey = QStringLiteral("dateWeight");
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
    m_wallpaperType = m_config->value(kTypeKey, QStringLiteral("none")).toString();
    m_wallpaperPath = m_config->value(kImageKey).toString();
    m_videoPath = m_config->value(kVideoKey).toString();
    m_posterPath = m_config->value(kPosterKey).toString();
    m_clockWeight = m_config->value(kClockWeightKey, QStringLiteral("light")).toString();
    m_dateWeight = m_config->value(kDateWeightKey, QStringLiteral("medium")).toString();
    Q_EMIT wallpaperTypeChanged(m_wallpaperType);
    Q_EMIT wallpaperPathChanged(m_wallpaperPath);
    Q_EMIT videoPathChanged(m_videoPath);
    Q_EMIT posterPathChanged(m_posterPath);
    Q_EMIT clockWeightChanged(m_clockWeight);
    Q_EMIT dateWeightChanged(m_dateWeight);
}

void Luminalock::setConfigValue(const QString &key, const QVariant &value)
{
    if (m_config)
        m_config->setValue(key, value);
    reload();
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

void Luminalock::setClockWeight(const QString &weight)
{
    setConfigValue(kClockWeightKey, weight);
}

void Luminalock::setDateWeight(const QString &weight)
{
    setConfigValue(kDateWeightKey, weight);
}

void Luminalock::resetToDefault()
{
    m_config->setValue(kTypeKey, QStringLiteral("none"));
    m_config->setValue(kImageKey, QString());
    m_config->setValue(kVideoKey, QString());
    m_config->setValue(kPosterKey, QString());
    m_config->setValue(kClockWeightKey, QStringLiteral("light"));
    m_config->setValue(kDateWeightKey, QStringLiteral("medium"));
    reload();
}

DCC_FACTORY_CLASS(Luminalock)
#include "luminalock.moc"
