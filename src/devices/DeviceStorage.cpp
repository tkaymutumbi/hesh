#include "DeviceStorage.hpp"

#include <QDebug>
#include <QDir>
#include <QStandardPaths>

namespace Hesh {

namespace {
constexpr auto webDeviceDirectory = "web-devices";
}

QString DeviceStorage::devicePath(const QString& location, const QString& deviceId)
{
    if (location.isEmpty() || deviceId.isEmpty()) {
        return {};
    }
    return QDir(location).filePath(QLatin1String(webDeviceDirectory) + QLatin1Char('/') + deviceId);
}

QString DeviceStorage::persistentRoot()
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

QString DeviceStorage::cacheRoot()
{
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
}

QString DeviceStorage::persistentStoragePath(const QString& deviceId)
{
    return devicePath(persistentRoot(), deviceId);
}

QString DeviceStorage::cachePath(const QString& deviceId)
{
    return devicePath(cacheRoot(), deviceId);
}

bool DeviceStorage::remove(const QString& deviceId)
{
    bool removed = false;
    for (const auto& path : {persistentStoragePath(deviceId), cachePath(deviceId)}) {
        if (path.isEmpty()) {
            continue;
        }
        QDir directory(path);
        if (!directory.exists()) {
            continue;
        }
        if (directory.removeRecursively()) {
            removed = true;
        } else {
            qWarning() << "Hesh could not remove device storage" << path;
        }
    }
    return removed;
}

} // namespace Hesh
