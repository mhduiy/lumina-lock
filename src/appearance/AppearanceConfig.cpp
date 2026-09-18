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
const QString kPositionXKey = QStringLiteral("clockPositionX");
const QString kPositionYKey = QStringLiteral("clockPositionY");

// Reference pixels at a 1080px-tall screen. Bounds are enforced here rather
// than trusted from the config: a hand-edited value must not be able to shrink
// the clock into illegibility or push the date off the screen.
constexpr int kClockSizeDefault = 150;
constexpr int kClockSizeMin = 80;
constexpr int kClockSizeMax = 240;
constexpr int kDateSizeDefault = 27;
constexpr int kDateSizeMin = 14;
constexpr int kDateSizeMax = 48;

// Where the clock-and-date block sits, as whole percent: 0 = flush with the
// left/top edge, 50 = centred (the behaviour before this was configurable),
// 100 = flush with the right/bottom edge.
constexpr int kPositionDefault = 50;
constexpr int kPositionMin = 0;
constexpr int kPositionMax = 100;

int clamped(int value, int lo, int hi)
{
    return std::max(lo, std::min(hi, value));
}

qreal positionFactor(int percent)
{
    return qreal(clamped(percent, kPositionMin, kPositionMax)) / kPositionMax;
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

    const int clock = weightFromName(configValue(kClockWeightKey, QString()).toString(),
                                     QFont::Light);
    const int date = weightFromName(configValue(kDateWeightKey, QString()).toString(),
                                    QFont::Medium);
    const int clockSize = clamped(configValue(kClockSizeKey, kClockSizeDefault).toInt(),
                                  kClockSizeMin, kClockSizeMax);
    const int dateSize = clamped(configValue(kDateSizeKey, kDateSizeDefault).toInt(),
                                 kDateSizeMin, kDateSizeMax);
    const qreal posX = positionFactor(configValue(kPositionXKey, kPositionDefault).toInt());
    const qreal posY = positionFactor(configValue(kPositionYKey, kPositionDefault).toInt());
    if (clock == m_clockWeight && date == m_dateWeight
        && clockSize == m_clockFontSize && dateSize == m_dateFontSize
        && qFuzzyCompare(posX, m_clockPositionX) && qFuzzyCompare(posY, m_clockPositionY))
        return;

    m_clockWeight = clock;
    m_dateWeight = date;
    m_clockFontSize = clockSize;
    m_dateFontSize = dateSize;
    m_clockPositionX = posX;
    m_clockPositionY = posY;
    emit changed();
}

QVariant AppearanceConfig::configValue(const QString &key, const QVariant &fallback) const
{
    // dtk6 的 DConfigFile::value() 遇到 meta 里没有的键会空指针崩溃（文件后端），
    // 所以先问 keyList()：装了旧 schema（没有 clockPosition*）时必须回退，而不是崩。
    if (!m_config || !m_config->isValid() || !m_config->keyList().contains(key))
        return fallback;
    return m_config->value(key, fallback);
}

void AppearanceConfig::onValueChanged(const QString &key)
{
    static const QSet<QString> watched{
        kClockWeightKey, kDateWeightKey, kClockSizeKey, kDateSizeKey,
        kPositionXKey, kPositionYKey,
    };
    if (watched.contains(key))
        reload();
}
