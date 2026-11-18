#include "WebDevice.hpp"

#include <utility>
#include <QUrl>

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
    QUrl requested(normalized), current(m_url);
    if (requested.path().isEmpty()) requested.setPath("/");
    if (current.path().isEmpty()) current.setPath("/");
    if (normalized == m_url || requested == current) {
        return;
    }
    m_url = normalized;
    emit urlChanged();
    emit dataChanged();
}

// Persist navigation without feeding it back into the view's URL binding.
void WebDevice::rememberUrl(const QString& url)
{
    const QUrl address(url);
    if (!address.isValid() || address.host().isEmpty()
        || (address.scheme() != "http" && address.scheme() != "https") || !address.userInfo().isEmpty()) return;
    if (m_url == address.toString()) return;
    m_url = address.toString();
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
