#include "WallpaperConfig.h"

#include "WallpaperManager.h"

#include <DConfig>

#include <QSet>
#include <QUrl>

namespace {
const QString kAppId = QStringLiteral("org.lumina.lock");
const QString kTypeKey = QStringLiteral("wallpaperType");
const QString kImageKey = QStringLiteral("wallpaperPath");
const QString kVideoKey = QStringLiteral("videoPath");
const QString kPosterKey = QStringLiteral("posterPath");

QUrl localOrNull(const QString &path)
{
    return path.isEmpty() ? QUrl() : QUrl::fromLocalFile(path);
}
} // namespace

WallpaperConfig::WallpaperConfig(QObject *parent)
    : QObject(parent)
    , m_config(Dtk::Core::DConfig::create(kAppId, kAppId, QString(), this))
{
    if (m_config) {
        connect(m_config, &Dtk::Core::DConfig::valueChanged,
                this, &WallpaperConfig::onValueChanged);
    }
}

void WallpaperConfig::applyTo(WallpaperManager &wm)
{
    const QString type = m_config && m_config->isValid()
        ? m_config->value(kTypeKey, QStringLiteral("none")).toString()
        : QStringLiteral("none");

    if (type == QLatin1String("video")) {
        const QString video = m_config->value(kVideoKey).toString();
        if (!video.isEmpty()) {
            wm.setVideo(localOrNull(video), localOrNull(m_config->value(kPosterKey).toString()));
            return;
        }
    } else if (type == QLatin1String("static")) {
        const QString image = m_config->value(kImageKey).toString();
        if (!image.isEmpty()) {
            wm.setStaticImage(QUrl::fromLocalFile(image));
            return;
        }
    }

    // No configured wallpaper: built-in default.
    wm.setStaticImage(QUrl(QStringLiteral("qrc:/assets/wallpapers/default.jpg")));
}

void WallpaperConfig::onValueChanged(const QString &key)
{
    static const QSet<QString> watched{kTypeKey, kImageKey, kVideoKey, kPosterKey};
    if (watched.contains(key))
        emit changed();
}
