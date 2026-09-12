#pragma once

#include <QString>

namespace Hesh {

// Single source of truth for the on-disk browser storage of a web device.
//
// DeviceFrame binds its WebEngineProfile to these paths and Device::clearData()
// removes them, so the layout cannot drift between the profile that writes the
// data and the operation that wipes it.
class DeviceStorage final
{
public:
    DeviceStorage() = delete;

    static QString persistentStoragePath(const QString& deviceId);
    static QString cachePath(const QString& deviceId);

    // The directories every device lives under. Settings surfaces them so the
    // paths it shows and the paths the wipe uses come from one place.
    static QString persistentRoot();
    static QString cacheRoot();

    // Removes both directories. Returns true when at least one existed.
    static bool remove(const QString& deviceId);

private:
    static QString devicePath(const QString& location, const QString& deviceId);
};

} // namespace Hesh
