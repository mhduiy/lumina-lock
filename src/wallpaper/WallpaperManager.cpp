#include "WallpaperManager.h"

#include <QFileInfo>
#include <QSet>

namespace {
const QSet<QString> &videoExtensions()
{
    static const QSet<QString> ext{
        QStringLiteral("mp4"), QStringLiteral("mov"), QStringLiteral("webm"),
        QStringLiteral("mkv"),  QStringLiteral("m4v"), QStringLiteral("avi"),
        QStringLiteral("ogv"),  QStringLiteral("mpg"), QStringLiteral("mpeg"),
    };
    return ext;
}
} // namespace

WallpaperManager::WallpaperManager(QObject *parent)
    : QObject(parent)
{
}

bool WallpaperManager::isVideoPath(const QString &path)
{
    const QString suffix = QFileInfo(path).suffix().toLower();
    return videoExtensions().contains(suffix);
}

bool WallpaperManager::loadFile(const QString &path, const QString &posterPath)
{
    if (path.isEmpty())
        return false;

    const QUrl url = QUrl::fromLocalFile(path);
    if (isVideoPath(path)) {
        setVideo(url, posterPath.isEmpty() ? QUrl() : QUrl::fromLocalFile(posterPath));
    } else {
        setStaticImage(url);
    }
    return true;
}

void WallpaperManager::setStaticImage(const QUrl &url)
{
    m_type = QStringLiteral("static");
    m_source = url;
    m_poster = QUrl();
    emit wallpaperChanged();
}

void WallpaperManager::setVideo(const QUrl &url, const QUrl &poster)
{
    m_type = QStringLiteral("video");
    m_source = url;
    m_poster = poster;
    emit wallpaperChanged();
}

void WallpaperManager::clear()
{
    m_type = QStringLiteral("none");
    m_source = QUrl();
    m_poster = QUrl();
    emit wallpaperChanged();
}
