#include "AppearanceConfig.h"

#include <DConfig>

#include <QHash>
#include <QSet>

namespace {
const QString kAppId = QStringLiteral("org.lumina.lock");
const QString kClockWeightKey = QStringLiteral("clockWeight");
const QString kDateWeightKey = QStringLiteral("dateWeight");

// DConfig keeps these human-readable for the control center; QML wants the
// numeric QFont::Weight. An unknown name falls back rather than throwing, so a
// hand-edited config cannot break the lock.
int weightFromName(const QString &name, int fallback)
{
    static const QHash<QString, int> weights{
        {QStringLiteral("thin"), QFont::Thin},
        {QStringLiteral("extralight"), QFont::ExtraLight},
        {QStringLiteral("light"), QFont::Light},
        {QStringLiteral("normal"), QFont::Normal},
        {QStringLiteral("medium"), QFont::Medium},
        {QStringLiteral("demibold"), QFont::DemiBold},
        {QStringLiteral("bold"), QFont::Bold},
    };
    const auto it = weights.constFind(name.trimmed().toLower());
    return it == weights.constEnd() ? fallback : it.value();
}
} // namespace

AppearanceConfig::AppearanceConfig(QObject *parent)
    : QObject(parent)
    , m_config(Dtk::Core::DConfig::create(kAppId, kAppId, QString(), this))
{
    if (m_config) {
        connect(m_config, &Dtk::Core::DConfig::valueChanged,
                this, &AppearanceConfig::onValueChanged);
    }
    reload();
}

void AppearanceConfig::reload()
{
    if (!m_config || !m_config->isValid())
        return;

    const int clock = weightFromName(m_config->value(kClockWeightKey).toString(),
                                     QFont::Light);
    const int date = weightFromName(m_config->value(kDateWeightKey).toString(),
                                    QFont::Medium);
    if (clock == m_clockWeight && date == m_dateWeight)
        return;

    m_clockWeight = clock;
    m_dateWeight = date;
    emit changed();
}

void AppearanceConfig::onValueChanged(const QString &key)
{
    static const QSet<QString> watched{kClockWeightKey, kDateWeightKey};
    if (watched.contains(key))
        reload();
}
