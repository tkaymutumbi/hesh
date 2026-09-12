#include "Device.hpp"

#include <QTimer>

#include <utility>

#include "app/AccentPalette.hpp"

namespace Hesh {

Device::Device(QString id,
               QString name,
               DeviceType type,
               DeviceProfile profile,
               QObject* parent)
    : QObject(parent)
    , m_id(std::move(id))
    , m_name(std::move(name))
    , m_type(type)
    , m_profile(std::move(profile))
{
}

Device::~Device() = default;

QString Device::id() const
{
    return m_id;
}

QString Device::name() const
{
    return m_name;
}

void Device::setName(const QString& name)
{
    const auto normalized = name.trimmed();
    if (normalized.isEmpty() || normalized == m_name) {
        return;
    }
    m_name = normalized;
    emit nameChanged();
    emit dataChanged();
}

DeviceType Device::deviceType() const
{
    return m_type;
}

QString Device::typeName() const
{
    return deviceTypeToString(m_type);
}

QString Device::typeLabel() const
{
    return m_type == DeviceType::Android ? QStringLiteral("ANDROID") : QStringLiteral("WEB");
}

Device::Status Device::status() const
{
    return m_status;
}

QString Device::statusName() const
{
    switch (m_status) {
    case Status::Stopped:
        return QStringLiteral("Stopped");
    case Status::Starting:
        return QStringLiteral("Starting");
    case Status::Running:
        return QStringLiteral("Running");
    case Status::Paused:
        return QStringLiteral("Paused");
    case Status::Error:
        return QStringLiteral("Error");
    }
    return QStringLiteral("Stopped");
}

void Device::setStatus(Status status)
{
    if (status == m_status) {
        return;
    }
    m_status = status;
    emit statusChanged();
    emit dataChanged();
}

const DeviceProfile& Device::profile() const
{
    return m_profile;
}

QString Device::profileName() const
{
    return m_profile.name;
}

int Device::viewportWidth() const
{
    return m_profile.width;
}

int Device::viewportHeight() const
{
    return m_profile.height;
}

double Device::devicePixelRatio() const
{
    return m_profile.devicePixelRatio;
}

QString Device::userAgent() const
{
    return m_profile.userAgent;
}

void Device::setProfile(const DeviceProfile& profile)
{
    if (m_profile.name == profile.name
        && m_profile.width == profile.width
        && m_profile.height == profile.height
        && qFuzzyCompare(m_profile.devicePixelRatio, profile.devicePixelRatio)
        && m_profile.userAgent == profile.userAgent) {
        return;
    }
    m_profile = profile;
    emit profileChanged();
    emit dataChanged();
}

void Device::start()
{
    setStatus(Status::Running);
}

void Device::stop()
{
    setStatus(Status::Stopped);
}

QString Device::accentName() const
{
    return m_accentName;
}

void Device::setAccentName(const QString& name)
{
    // A name outside the catalog is not a colour this build can draw, so it
    // falls back to following the application accent instead of being stored.
    const auto normalized = isKnownAccent(name) ? accentPresetFor(name).name : QString {};
    if (normalized == m_accentName) {
        return;
    }
    m_accentName = normalized;
    emit accentChanged();
    emit dataChanged();
}

bool Device::hasAccent() const
{
    return !m_accentName.isEmpty();
}

QColor Device::accent() const
{
    return accentPresetFor(m_accentName).accent;
}

QColor Device::accentStrong() const
{
    return accentPresetFor(m_accentName).strong;
}

QColor Device::accentSoft() const
{
    return accentPresetFor(m_accentName).soft;
}

QColor Device::accentBorder() const
{
    return accentPresetFor(m_accentName).border;
}

void Device::clearData()
{
    emit dataClearing();
    // Hosts release their WebEngine surface from dataClearing(); Chromium keeps
    // the storage directory busy until its profile is destroyed. Defer the
    // removal so the queued profile destruction is serviced first, then let
    // hosts restore a fresh surface.
    QTimer::singleShot(0, this, [this] {
        clearPersistentData();
        emit dataCleared();
    });
}

void Device::clearPersistentData()
{
}

} // namespace Hesh
