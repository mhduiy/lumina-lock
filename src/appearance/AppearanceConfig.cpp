#include "AppearanceConfig.h"

#include <DConfig>

#include <QHash>
#include <QSet>

#include <algorithm>

namespace {
const QString kAppId = QStringLiteral("org.lumina.lock");
const QString kClockWeightKey = QStringLiteral("clockWeight");
const QString kDateWeightKey = QStringLiteral("dateWeight");
const QString kClockSizeKey = QStringLiteral("clockFontSize");
const QString kDateSizeKey = QStringLiteral("dateFontSize");

// Reference pixels at a 1080px-tall screen. Bounds are enforced here rather
// than trusted from the config: a hand-edited value must not be able to shrink
// the clock into illegibility or push the date off the screen.
constexpr int kClockSizeDefault = 150;
constexpr int kClockSizeMin = 80;
constexpr int kClockSizeMax = 240;
constexpr int kDateSizeDefault = 27;
constexpr int kDateSizeMin = 14;
constexpr int kDateSizeMax = 48;

int clamped(int value, int lo, int hi)
{
    return std::max(lo, std::min(hi, value));
}

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
    const int clockSize = clamped(m_config->value(kClockSizeKey, kClockSizeDefault).toInt(),
                                  kClockSizeMin, kClockSizeMax);
    const int dateSize = clamped(m_config->value(kDateSizeKey, kDateSizeDefault).toInt(),
                                 kDateSizeMin, kDateSizeMax);
    if (clock == m_clockWeight && date == m_dateWeight
        && clockSize == m_clockFontSize && dateSize == m_dateFontSize)
        return;

    m_clockWeight = clock;
    m_dateWeight = date;
    m_clockFontSize = clockSize;
    m_dateFontSize = dateSize;
    emit changed();
}

void AppearanceConfig::onValueChanged(const QString &key)
{
    static const QSet<QString> watched{
        kClockWeightKey, kDateWeightKey, kClockSizeKey, kDateSizeKey,
    };
    if (watched.contains(key))
        reload();
}
