#pragma once

#include <QJsonObject>
#include <QList>
#include <QString>
#include <QVariantList>

#include <optional>

namespace Hesh {

enum class DeviceType {
    Web,
    Android,
};

QString deviceTypeToString(DeviceType type);
DeviceType deviceTypeFromString(const QString& value);

struct DeviceProfile
{
    QString name;
    int width = 412;
    int height = 915;
    double devicePixelRatio = 1.0;
    QString userAgent;

    static QList<DeviceProfile> catalog();
    static DeviceProfile fromName(const QString& name);
};

struct DeviceRecord
{
    QString id;
    QString name;
    QString type;
    QString profileName;
    QString url;
    // Empty means the device follows the application accent.
    QString accent;
    // Whether the device was running when this record was last written. A
    // record without the key predates persisted run state and loads stopped.
    bool running = false;
    // Web content theme: "dark" turns on Chromium's force-dark rendering for
    // this device; anything else means "system". A record without the key
    // predates the setting and loads as "system".
    QString contentTheme;
};

QJsonObject deviceRecordToJson(const DeviceRecord& record);
std::optional<DeviceRecord> deviceRecordFromJson(const QJsonObject& object);
QVariantList deviceProfileCatalogForQml();

} // namespace Hesh
