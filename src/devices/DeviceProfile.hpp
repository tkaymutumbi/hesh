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
};

QJsonObject deviceRecordToJson(const DeviceRecord& record);
std::optional<DeviceRecord> deviceRecordFromJson(const QJsonObject& object);
QVariantList deviceProfileCatalogForQml();

} // namespace Hesh
