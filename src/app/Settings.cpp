#include "Settings.hpp"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>

namespace Hesh {

Settings::Settings(QString organization, QString application, QString filePath)
{
    if (filePath.isEmpty()) {
        m_settings = std::make_unique<QSettings>(std::move(organization), std::move(application));
    } else {
        m_settings = std::make_unique<QSettings>(std::move(filePath), QSettings::IniFormat);
    }
}

Settings::~Settings() = default;

QList<DeviceRecord> Settings::loadDevices() const
{
    const auto json = m_settings->value(QStringLiteral("devices")).toByteArray();
    if (json.isEmpty()) {
        return {};
    }

    const auto document = QJsonDocument::fromJson(json);
    if (!document.isArray()) {
        return {};
    }

    QList<DeviceRecord> records;
    for (const auto& value : document.array()) {
        if (!value.isObject()) {
            continue;
        }

        const auto record = deviceRecordFromJson(value.toObject());
        if (record.has_value()) {
            records.append(record.value());
        }
    }
    return records;
}

void Settings::saveDevices(const QList<DeviceRecord>& devices)
{
    QJsonArray array;
    for (const auto& device : devices) {
        array.append(deviceRecordToJson(device));
    }

    m_settings->setValue(QStringLiteral("devices"),
                         QJsonDocument(array).toJson(QJsonDocument::Compact));
    m_settings->sync();
}

QString Settings::selectedDeviceId() const
{
    return m_settings->value(QStringLiteral("selectedDeviceId")).toString();
}

void Settings::setSelectedDeviceId(const QString& id)
{
    m_settings->setValue(QStringLiteral("selectedDeviceId"), id);
    m_settings->sync();
}

namespace {
constexpr auto preferencesGroup = "preferences";
}

QString Settings::preferenceSettingsKey(const QString& key)
{
    if (key.isEmpty()) {
        return QLatin1String(preferencesGroup);
    }
    return QLatin1String(preferencesGroup) + QLatin1Char('/') + key;
}

QVariant Settings::preference(const QString& key, const QVariant& fallback) const
{
    return m_settings->value(preferenceSettingsKey(key), fallback);
}

void Settings::setPreference(const QString& key, const QVariant& value)
{
    m_settings->setValue(preferenceSettingsKey(key), value);
    m_settings->sync();
}

void Settings::resetPreferences()
{
    m_settings->remove(QLatin1String(preferencesGroup));
    m_settings->sync();
}

} // namespace Hesh
