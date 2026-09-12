#pragma once

#include <QList>
#include <QString>
#include <QVariant>

#include <memory>

#include "devices/DeviceProfile.hpp"

class QSettings;

namespace Hesh {

class Settings final
{
public:
    Settings(QString organization = QStringLiteral("Hesh"),
             QString application = QStringLiteral("Hesh"),
             QString filePath = {});
    ~Settings();

    Settings(const Settings&) = delete;
    Settings& operator=(const Settings&) = delete;

    QList<DeviceRecord> loadDevices() const;
    void saveDevices(const QList<DeviceRecord>& devices);

    QString selectedDeviceId() const;
    void setSelectedDeviceId(const QString& id);

    // Preferences are raw key/value reads; Preferences owns the keys, their
    // defaults, and their validation. Device records stay under their own
    // top-level keys and are never touched by resetPreferences().
    QVariant preference(const QString& key, const QVariant& fallback = {}) const;
    void setPreference(const QString& key, const QVariant& value);
    void resetPreferences();

    // Full QSettings key for a preference. Out-of-band readers (the Chromium
    // flags read in main.cpp, before the Preferences object exists) go through
    // this so they cannot drift from the reader that owns the defaults.
    static QString preferenceSettingsKey(const QString& key);

private:
    std::unique_ptr<QSettings> m_settings;
};

} // namespace Hesh
