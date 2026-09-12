#pragma once

#include <QColor>
#include <QObject>
#include <QString>
#include <QVariantList>

namespace Hesh {

class Settings;

// QML-facing boundary over the preferences that are not device records.
// Settings stays the raw persistence boundary; this object owns the keys, their
// documented defaults, validation, and the change notifications QML binds to.
//
// The instance is registered in main.cpp as the `Preferences` QML singleton
// because a preference is read from unrelated corners of the tree (the palette,
// the preview frame, the toolbars). Device-scoped objects keep their existing
// explicit `manager` injection.
class Preferences final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString newDeviceName READ newDeviceName WRITE setNewDeviceName NOTIFY newDeviceNameChanged)
    Q_PROPERTY(QString newDeviceUrl READ newDeviceUrl WRITE setNewDeviceUrl NOTIFY newDeviceUrlChanged)
    Q_PROPERTY(QString newDeviceProfile READ newDeviceProfile WRITE setNewDeviceProfile NOTIFY newDeviceProfileChanged)
    Q_PROPERTY(bool allowUpscale READ allowUpscale WRITE setAllowUpscale NOTIFY allowUpscaleChanged)
    Q_PROPERTY(bool showDevToolsOnOpen READ showDevToolsOnOpen WRITE setShowDevToolsOnOpen NOTIFY showDevToolsOnOpenChanged)
    Q_PROPERTY(bool openInStandalone READ openInStandalone WRITE setOpenInStandalone NOTIFY openInStandaloneChanged)
    Q_PROPERTY(bool showMetrics READ showMetrics WRITE setShowMetrics NOTIFY showMetricsChanged)
    Q_PROPERTY(QString accentName READ accentName WRITE setAccentName NOTIFY accentChanged)
    Q_PROPERTY(QColor accent READ accent NOTIFY accentChanged)
    Q_PROPERTY(QColor accentStrong READ accentStrong NOTIFY accentChanged)
    Q_PROPERTY(QColor accentSoft READ accentSoft NOTIFY accentChanged)
    Q_PROPERTY(QColor accentBorder READ accentBorder NOTIFY accentChanged)
    Q_PROPERTY(QVariantList accentPresets READ accentPresets CONSTANT)
    Q_PROPERTY(QString extraChromiumFlags READ extraChromiumFlags WRITE setExtraChromiumFlags NOTIFY extraChromiumFlagsChanged)
    Q_PROPERTY(bool restartRequired READ restartRequired NOTIFY restartRequiredChanged)
    Q_PROPERTY(QString effectiveChromiumFlags READ effectiveChromiumFlags NOTIFY effectiveChromiumFlagsChanged)
    Q_PROPERTY(QString highDpiPolicy READ highDpiPolicy NOTIFY runtimeFactsChanged)
    Q_PROPERTY(QString chromiumVersion READ chromiumVersion NOTIFY runtimeFactsChanged)
    Q_PROPERTY(QString qtVersion READ qtVersion CONSTANT)
    Q_PROPERTY(QString appVersion READ appVersion CONSTANT)
    Q_PROPERTY(QString dataRootPath READ dataRootPath CONSTANT)
    Q_PROPERTY(QString cacheRootPath READ cacheRootPath CONSTANT)

public:
    explicit Preferences(Settings* settings, QObject* parent = nullptr);

    QString newDeviceName() const;
    void setNewDeviceName(const QString& name);

    QString newDeviceUrl() const;
    void setNewDeviceUrl(const QString& url);

    QString newDeviceProfile() const;
    void setNewDeviceProfile(const QString& profileName);

    bool allowUpscale() const;
    void setAllowUpscale(bool allow);

    bool showDevToolsOnOpen() const;
    void setShowDevToolsOnOpen(bool show);

    bool openInStandalone() const;
    void setOpenInStandalone(bool open);

    bool showMetrics() const;
    void setShowMetrics(bool show);

    QString accentName() const;
    void setAccentName(const QString& name);

    QColor accent() const;
    QColor accentStrong() const;
    QColor accentSoft() const;
    QColor accentBorder() const;
    QVariantList accentPresets() const;

    QString extraChromiumFlags() const;
    void setExtraChromiumFlags(const QString& flags);
    // True while the stored flags differ from the ones this process started
    // with: Chromium reads its command line once, so the change needs a
    // relaunch rather than a reload.
    bool restartRequired() const;

    QString effectiveChromiumFlags() const;

    QString highDpiPolicy() const;
    QString chromiumVersion() const;
    QString qtVersion() const;
    QString appVersion() const;

    QString dataRootPath() const;
    QString cacheRootPath() const;

    // Process-level facts main.cpp owns: the rounding policy it installed and
    // the Chromium build Qt linked. Not persisted.
    void setRuntimeFacts(const QString& highDpiPolicy, const QString& chromiumVersion);

    Q_INVOKABLE void openDataFolder();
    Q_INVOKABLE void relaunch();
    Q_INVOKABLE void resetToDefaults();

signals:
    void newDeviceNameChanged();
    void newDeviceUrlChanged();
    void newDeviceProfileChanged();
    void allowUpscaleChanged();
    void showDevToolsOnOpenChanged();
    void openInStandaloneChanged();
    void showMetricsChanged();
    void accentChanged();
    void extraChromiumFlagsChanged();
    void restartRequiredChanged();
    void effectiveChromiumFlagsChanged();
    void runtimeFactsChanged();

private:
    void reloadFromStorage();
    void write(const QString& key, const QVariant& value);

    Settings* m_settings = nullptr;
    QString m_newDeviceName;
    QString m_newDeviceUrl;
    QString m_newDeviceProfile;
    bool m_allowUpscale = false;
    bool m_showDevToolsOnOpen = false;
    bool m_openInStandalone = false;
    bool m_showMetrics = true;
    QString m_accentName;
    QString m_extraChromiumFlags;
    // Flags this process actually started Chromium with, captured before any
    // edit so restartRequired() compares against reality.
    QString m_appliedChromiumFlags;
    QString m_highDpiPolicy;
    QString m_chromiumVersion;
};

// The extra Chromium flags a user stored, read straight from the settings file.
// main.cpp merges them into QTWEBENGINE_CHROMIUM_FLAGS before
// QtWebEngineQuick::initialize(), which runs before the Preferences instance
// exists. The application organization and name must already be set so both
// readers resolve the same file.
QString storedExtraChromiumFlags();

// Human-readable name of the rounding policy main.cpp installs, for the
// read-only diagnostics row.
QString highDpiRoundingPolicyName();

} // namespace Hesh
