#include "Preferences.hpp"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QGuiApplication>
#include <QProcess>
#include <QSettings>
#include <QStringList>
#include <QUrl>

#include "AccentPalette.hpp"
#include "Settings.hpp"
#include "devices/DeviceStorage.hpp"

namespace Hesh {

namespace {

// Preference keys are relative to Settings::preferenceSettingsKey().
constexpr auto newDeviceNameKey = "deviceDefaults/name";
constexpr auto newDeviceUrlKey = "deviceDefaults/url";
constexpr auto newDeviceProfileKey = "deviceDefaults/profile";
constexpr auto allowUpscaleKey = "preview/allowUpscale";
constexpr auto showDevToolsKey = "preview/showDevTools";
constexpr auto openInStandaloneKey = "preview/openInStandalone";
constexpr auto showMetricsKey = "preview/showMetrics";
constexpr auto accentKey = "appearance/accent";
constexpr auto extraChromiumFlagsKey = "advanced/extraChromiumFlags";

// Defaults are the values the UI shipped with before preferences existed, so an
// untouched install looks and behaves exactly as it did.
const QString defaultNewDeviceName = QStringLiteral("Pixel 7 Development");
const QString defaultNewDeviceUrl = QStringLiteral("http://localhost:3000");
const QString defaultNewDeviceProfile = QStringLiteral("Pixel 7");

QString normalizedOr(const QString& value, const QString& fallback)
{
    const auto trimmed = value.trimmed();
    return trimmed.isEmpty() ? fallback : trimmed;
}

} // namespace

Preferences::Preferences(Settings* settings, QObject* parent)
    : QObject(parent)
    , m_settings(settings)
{
    reloadFromStorage();
    // The process started Chromium with whatever was stored at launch, so an
    // edit compares against that captured value rather than against the file.
    m_appliedChromiumFlags = m_extraChromiumFlags;
}

QString Preferences::newDeviceName() const
{
    return m_newDeviceName;
}

void Preferences::setNewDeviceName(const QString& name)
{
    const auto normalized = normalizedOr(name, defaultNewDeviceName);
    if (normalized == m_newDeviceName) {
        return;
    }
    m_newDeviceName = normalized;
    write(QLatin1String(newDeviceNameKey), m_newDeviceName);
    emit newDeviceNameChanged();
}

QString Preferences::newDeviceUrl() const
{
    return m_newDeviceUrl;
}

void Preferences::setNewDeviceUrl(const QString& url)
{
    const auto normalized = normalizedOr(url, defaultNewDeviceUrl);
    if (normalized == m_newDeviceUrl) {
        return;
    }
    m_newDeviceUrl = normalized;
    write(QLatin1String(newDeviceUrlKey), m_newDeviceUrl);
    emit newDeviceUrlChanged();
}

QString Preferences::newDeviceProfile() const
{
    return m_newDeviceProfile;
}

void Preferences::setNewDeviceProfile(const QString& profileName)
{
    // An unknown profile name is harmless: DeviceProfile::fromName() falls back
    // to the first catalog entry when the device is created, and the dialog
    // selects the first entry when the name is not in the model.
    const auto normalized = normalizedOr(profileName, defaultNewDeviceProfile);
    if (normalized == m_newDeviceProfile) {
        return;
    }
    m_newDeviceProfile = normalized;
    write(QLatin1String(newDeviceProfileKey), m_newDeviceProfile);
    emit newDeviceProfileChanged();
}

bool Preferences::allowUpscale() const
{
    return m_allowUpscale;
}

void Preferences::setAllowUpscale(bool allow)
{
    if (allow == m_allowUpscale) {
        return;
    }
    m_allowUpscale = allow;
    write(QLatin1String(allowUpscaleKey), m_allowUpscale);
    emit allowUpscaleChanged();
}

bool Preferences::showDevToolsOnOpen() const
{
    return m_showDevToolsOnOpen;
}

void Preferences::setShowDevToolsOnOpen(bool show)
{
    if (show == m_showDevToolsOnOpen) {
        return;
    }
    m_showDevToolsOnOpen = show;
    write(QLatin1String(showDevToolsKey), m_showDevToolsOnOpen);
    emit showDevToolsOnOpenChanged();
}

bool Preferences::openInStandalone() const
{
    return m_openInStandalone;
}

void Preferences::setOpenInStandalone(bool open)
{
    if (open == m_openInStandalone) {
        return;
    }
    m_openInStandalone = open;
    write(QLatin1String(openInStandaloneKey), m_openInStandalone);
    emit openInStandaloneChanged();
}

bool Preferences::showMetrics() const
{
    return m_showMetrics;
}

void Preferences::setShowMetrics(bool show)
{
    if (show == m_showMetrics) {
        return;
    }
    m_showMetrics = show;
    write(QLatin1String(showMetricsKey), m_showMetrics);
    emit showMetricsChanged();
}

QString Preferences::accentName() const
{
    return m_accentName;
}

void Preferences::setAccentName(const QString& name)
{
    const auto canonical = accentPresetFor(name).name;
    if (canonical == m_accentName) {
        return;
    }
    m_accentName = canonical;
    write(QLatin1String(accentKey), m_accentName);
    emit accentChanged();
}

QColor Preferences::accent() const
{
    return accentPresetFor(m_accentName).accent;
}

QColor Preferences::accentStrong() const
{
    return accentPresetFor(m_accentName).strong;
}

QColor Preferences::accentSoft() const
{
    return accentPresetFor(m_accentName).soft;
}

QColor Preferences::accentBorder() const
{
    return accentPresetFor(m_accentName).border;
}

QVariantList Preferences::accentPresets() const
{
    return accentPaletteForQml();
}

QString Preferences::extraChromiumFlags() const
{
    return m_extraChromiumFlags;
}

void Preferences::setExtraChromiumFlags(const QString& flags)
{
    const auto normalized = flags.trimmed();
    if (normalized == m_extraChromiumFlags) {
        return;
    }
    const bool wasRequired = restartRequired();
    m_extraChromiumFlags = normalized;
    write(QLatin1String(extraChromiumFlagsKey), m_extraChromiumFlags);
    emit extraChromiumFlagsChanged();
    if (restartRequired() != wasRequired) {
        emit restartRequiredChanged();
    }
}

bool Preferences::restartRequired() const
{
    return m_extraChromiumFlags != m_appliedChromiumFlags;
}

QString Preferences::effectiveChromiumFlags() const
{
    // Read live rather than cached: main.cpp merges the stored flags into the
    // environment before WebEngine starts, so this is what Chromium was given.
    return QString::fromLocal8Bit(qgetenv("QTWEBENGINE_CHROMIUM_FLAGS"));
}

QString Preferences::highDpiPolicy() const
{
    return m_highDpiPolicy;
}

QString Preferences::chromiumVersion() const
{
    return m_chromiumVersion;
}

QString Preferences::qtVersion() const
{
    return QString::fromLatin1(qVersion());
}

QString Preferences::appVersion() const
{
    return QCoreApplication::applicationVersion();
}

QString Preferences::dataRootPath() const
{
    return DeviceStorage::persistentRoot();
}

QString Preferences::cacheRootPath() const
{
    return DeviceStorage::cacheRoot();
}

void Preferences::setRuntimeFacts(const QString& highDpiPolicy, const QString& chromiumVersion)
{
    if (highDpiPolicy == m_highDpiPolicy && chromiumVersion == m_chromiumVersion) {
        return;
    }
    m_highDpiPolicy = highDpiPolicy;
    m_chromiumVersion = chromiumVersion;
    emit runtimeFactsChanged();
}

void Preferences::openDataFolder()
{
    const auto root = DeviceStorage::persistentRoot();
    if (!root.isEmpty()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(root));
    }
}

void Preferences::relaunch()
{
    // Chromium reads its command line once, so a stored flag change can only
    // take effect in a new process. The current process quits through the
    // normal teardown path, which releases every device browser surface.
    if (QProcess::startDetached(QCoreApplication::applicationFilePath(), {})) {
        QCoreApplication::quit();
    }
}

void Preferences::resetToDefaults()
{
    if (!m_settings) {
        return;
    }
    m_settings->resetPreferences();
    reloadFromStorage();
    // QML binds to individual properties and cannot observe a group reset, so
    // every preference is announced whether or not its value moved.
    emit newDeviceNameChanged();
    emit newDeviceUrlChanged();
    emit newDeviceProfileChanged();
    emit allowUpscaleChanged();
    emit showDevToolsOnOpenChanged();
    emit openInStandaloneChanged();
    emit showMetricsChanged();
    emit accentChanged();
    emit extraChromiumFlagsChanged();
    emit restartRequiredChanged();
}

void Preferences::reloadFromStorage()
{
    if (m_settings) {
        m_newDeviceName = normalizedOr(m_settings->preference(QLatin1String(newDeviceNameKey)).toString(),
                                       defaultNewDeviceName);
        m_newDeviceUrl = normalizedOr(m_settings->preference(QLatin1String(newDeviceUrlKey)).toString(),
                                      defaultNewDeviceUrl);
        m_newDeviceProfile = normalizedOr(m_settings->preference(QLatin1String(newDeviceProfileKey)).toString(),
                                          defaultNewDeviceProfile);
        m_allowUpscale = m_settings->preference(QLatin1String(allowUpscaleKey), false).toBool();
        m_showDevToolsOnOpen = m_settings->preference(QLatin1String(showDevToolsKey), false).toBool();
        m_openInStandalone = m_settings->preference(QLatin1String(openInStandaloneKey), false).toBool();
        m_showMetrics = m_settings->preference(QLatin1String(showMetricsKey), true).toBool();
        m_accentName = accentPresetFor(m_settings->preference(QLatin1String(accentKey)).toString()).name;
        m_extraChromiumFlags = m_settings->preference(QLatin1String(extraChromiumFlagsKey)).toString().trimmed();
    } else {
        m_newDeviceName = defaultNewDeviceName;
        m_newDeviceUrl = defaultNewDeviceUrl;
        m_newDeviceProfile = defaultNewDeviceProfile;
        m_allowUpscale = false;
        m_showDevToolsOnOpen = false;
        m_openInStandalone = false;
        m_showMetrics = true;
        m_accentName = accentPalette().constFirst().name;
        m_extraChromiumFlags.clear();
    }
}

void Preferences::write(const QString& key, const QVariant& value)
{
    if (m_settings) {
        m_settings->setPreference(key, value);
    }
}

QString storedExtraChromiumFlags()
{
    // A temporary reader instead of the Settings instance: this runs before
    // WebEngine starts, which is earlier than Application (and therefore
    // Preferences) is constructed.
    QSettings settings;
    return settings.value(Settings::preferenceSettingsKey(QLatin1String(extraChromiumFlagsKey)))
        .toString()
        .trimmed();
}

QString highDpiRoundingPolicyName()
{
    switch (QGuiApplication::highDpiScaleFactorRoundingPolicy()) {
    case Qt::HighDpiScaleFactorRoundingPolicy::Round:
        return QStringLiteral("Round");
    case Qt::HighDpiScaleFactorRoundingPolicy::Ceil:
        return QStringLiteral("Ceil");
    case Qt::HighDpiScaleFactorRoundingPolicy::Floor:
        return QStringLiteral("Floor");
    case Qt::HighDpiScaleFactorRoundingPolicy::RoundPreferFloor:
        return QStringLiteral("RoundPreferFloor");
    case Qt::HighDpiScaleFactorRoundingPolicy::PassThrough:
        return QStringLiteral("PassThrough");
    }
    return QStringLiteral("Unset");
}

} // namespace Hesh
