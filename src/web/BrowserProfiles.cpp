#include "web/BrowserProfiles.hpp"

#include <QtWebEngineQuick/QQuickWebEngineProfile>

#include "web/WebDevice.hpp"

namespace Hesh {

BrowserProfiles::BrowserProfiles(QObject* parent)
    : QObject(parent)
{
}

QQuickWebEngineProfile* BrowserProfiles::profileFor(QObject* object)
{
    auto* device = qobject_cast<WebDevice*>(object);
    if (!device) {
        return nullptr;
    }
    const auto id = device->id();
    if (auto existing = m_profiles.value(id)) {
        return existing;
    }

    auto* profile = new QQuickWebEngineProfile(QStringLiteral("hesh-device-") + id, this);
    // The device owns the storage layout, so the profile and the clear-data
    // operation can never disagree about the directories.
    profile->setPersistentStoragePath(device->persistentStoragePath());
    profile->setCachePath(device->cachePath());
    profile->setHttpCacheType(QQuickWebEngineProfile::DiskHttpCache);
    profile->setPersistentCookiesPolicy(QQuickWebEngineProfile::ForcePersistentCookies);
    m_profiles.insert(id, profile);

    // Clearing data needs the profile gone before its directories are
    // removed; hosts drop their views on dataClearing, and the next frame
    // asks for a fresh profile after dataCleared. Removing the device drops
    // it for good. Queued so the views' own teardown runs first.
    connect(device, &Device::dataClearing, profile, [this, id] { release(id); }, Qt::QueuedConnection);
    connect(device, &QObject::destroyed, profile, [this, id] { release(id); }, Qt::QueuedConnection);
    return profile;
}

void BrowserProfiles::release(const QString& deviceId)
{
    if (auto profile = m_profiles.take(deviceId)) {
        profile->deleteLater();
    }
}

} // namespace Hesh
