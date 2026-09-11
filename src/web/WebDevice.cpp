#include "WebDevice.hpp"

#include <utility>

#include "devices/DeviceStorage.hpp"

namespace Hesh {

WebDevice::WebDevice(QString id,
                     QString name,
                     DeviceProfile profile,
                     QString url,
                     QObject* parent)
    : Device(std::move(id), std::move(name), DeviceType::Web, std::move(profile), parent)
    , m_url(std::move(url))
{
}

QString WebDevice::url() const
{
    return m_url;
}

void WebDevice::setUrl(const QString& url)
{
    const auto normalized = url.trimmed();
    if (normalized == m_url) {
        return;
    }
    m_url = normalized;
    emit urlChanged();
    emit dataChanged();
}

void WebDevice::start()
{
    setStatus(Status::Starting);
    setStatus(Status::Running);
}

void WebDevice::stop()
{
    setStatus(Status::Stopped);
}

QString WebDevice::persistentStoragePath() const
{
    return DeviceStorage::persistentStoragePath(id());
}

QString WebDevice::cachePath() const
{
    return DeviceStorage::cachePath(id());
}

void WebDevice::clearPersistentData()
{
    DeviceStorage::remove(id());
}

} // namespace Hesh
