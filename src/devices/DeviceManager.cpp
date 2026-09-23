#include "DeviceManager.hpp"

#include <QDebug>
#include <QUuid>

#include <algorithm>

#include "app/Settings.hpp"
#include "web/WebDevice.hpp"

namespace Hesh {

DeviceListModel::DeviceListModel(QObject* parent)
    : QAbstractListModel(parent)
{
}

int DeviceListModel::rowCount(const QModelIndex& parent) const
{
    return parent.isValid() ? 0 : m_devices.size();
}

QVariant DeviceListModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_devices.size()) {
        return {};
    }

    const auto* device = m_devices.at(index.row());
    switch (role) {
    case DeviceObjectRole:
        return QVariant::fromValue(device);
    case DeviceIdRole:
        return device->id();
    case DeviceNameRole:
        return device->name();
    case DeviceTypeRole:
        return device->typeName();
    case DeviceTypeLabelRole:
        return device->typeLabel();
    case DeviceStatusRole:
        return device->statusName();
    case DeviceProfileRole:
        return device->profileName();
    case DeviceUrlRole: {
        const auto* webDevice = qobject_cast<const WebDevice*>(device);
        return webDevice ? webDevice->url() : QString {};
    }
    case Qt::DisplayRole:
        return device->name();
    default:
        return {};
    }
}

QHash<int, QByteArray> DeviceListModel::roleNames() const
{
    return {
        {DeviceObjectRole, "deviceObject"},
        {DeviceIdRole, "deviceId"},
        {DeviceNameRole, "deviceName"},
        {DeviceTypeRole, "deviceType"},
        {DeviceTypeLabelRole, "deviceTypeLabel"},
        {DeviceStatusRole, "deviceStatus"},
        {DeviceProfileRole, "deviceProfile"},
        {DeviceUrlRole, "deviceUrl"},
    };
}

void DeviceListModel::insertDevice(int row, Device* device)
{
    beginInsertRows({}, row, row);
    m_devices.insert(row, device);
    endInsertRows();
}

void DeviceListModel::removeDevice(int row)
{
    if (row < 0 || row >= m_devices.size()) {
        return;
    }
    beginRemoveRows({}, row, row);
    m_devices.removeAt(row);
    endRemoveRows();
}

Device* DeviceListModel::at(int row) const
{
    return row >= 0 && row < m_devices.size() ? m_devices.at(row) : nullptr;
}

void DeviceListModel::moveDevice(int from, int to)
{
    if (from == to || from < 0 || from >= m_devices.size() || to < 0 || to >= m_devices.size()) {
        return;
    }
    // beginMoveRows takes the row the moved rows are inserted before, in
    // pre-move coordinates: moving down has to point one past the target.
    const int destination = to > from ? to + 1 : to;
    if (!beginMoveRows({}, from, from, {}, destination)) {
        return;
    }
    m_devices.move(from, to);
    endMoveRows();
}

int DeviceListModel::indexOf(const Device* device) const
{
    return m_devices.indexOf(const_cast<Device*>(device));
}

DeviceManager::DeviceManager(Settings* settings, QObject* parent)
    : QObject(parent)
    , m_model(this)
    , m_settings(settings)
{
    load();
}

QAbstractListModel* DeviceManager::devices()
{
    return &m_model;
}

Device* DeviceManager::selectedDevice() const
{
    return m_selectedDevice;
}

int DeviceManager::deviceCount() const
{
    return m_model.rowCount();
}

QVariantList DeviceManager::availableProfiles() const
{
    return deviceProfileCatalogForQml();
}

WebDevice* DeviceManager::createWebDevice(const QString& requestedName,
                                          const QString& profileName,
                                          const QString& requestedUrl)
{
    const auto name = requestedName.trimmed().isEmpty()
        ? QStringLiteral("Web Device")
        : requestedName.trimmed();
    const auto url = requestedUrl.trimmed().isEmpty()
        ? QStringLiteral("http://localhost:3000")
        : requestedUrl.trimmed();
    const auto profile = DeviceProfile::fromName(profileName);
    auto* device = new WebDevice(
        QUuid::createUuid().toString(QUuid::WithoutBraces), name, profile, url, this);
    addDevice(device, true);
    device->start();
    persist();
    return device;
}

void DeviceManager::removeDevice(const QString& id)
{
    auto* device = findById(id);
    if (!device) {
        return;
    }

    const auto row = m_model.indexOf(device);
    const bool wasSelected = device == m_selectedDevice;
    if (wasSelected) {
        Device* replacement = nullptr;
        if (row + 1 < m_model.rowCount()) {
            replacement = m_model.at(row + 1);
        } else if (row > 0) {
            replacement = m_model.at(row - 1);
        }
        setSelectedDevice(replacement);
    }

    m_model.removeDevice(row);
    device->deleteLater();
    emit deviceCountChanged();
    persist();
}

void DeviceManager::clearDeviceData(const QString& id)
{
    if (auto* device = findById(id)) {
        device->clearData();
    }
}

void DeviceManager::clearAllDeviceData()
{
    // Each device schedules its own wipe on the next event-loop turn, so the
    // whole model can be asked at once: one device's pending wipe never blocks
    // the next one's profile release.
    for (int row = 0; row < m_model.rowCount(); ++row) {
        if (auto* device = m_model.at(row)) {
            device->clearData();
        }
    }
}

void DeviceManager::setDeviceAccent(const QString& id, const QString& accentName)
{
    // An empty name clears the override and returns the device to the
    // application accent; Device::setAccentName() rejects unknown names and
    // emits dataChanged, which persists the device list.
    if (auto* device = findById(id)) {
        device->setAccentName(accentName);
    }
}

void DeviceManager::moveDevice(const QString& id, int targetIndex)
{
    auto* device = findById(id);
    if (!device) {
        return;
    }
    const int from = m_model.indexOf(device);
    if (from < 0) {
        return;
    }
    // The boundary counts rows in the list as it looks now, including the row
    // being dragged, so dropping in place or just after itself changes nothing.
    const int boundary = std::clamp(targetIndex, 0, m_model.rowCount());
    if (boundary == from || boundary == from + 1) {
        return;
    }
    m_model.moveDevice(from, boundary > from ? boundary - 1 : boundary);
    persist();
}

void DeviceManager::setDeviceContentTheme(const QString& id, const QString& theme)
{
    // Only "dark" and "system" survive normalization; the device emits
    // dataChanged, which persists the device list.
    if (auto* device = findById(id)) {
        device->setContentTheme(theme);
    }
}

void DeviceManager::selectDevice(const QString& id)
{
    setSelectedDevice(findById(id));
}

void DeviceManager::startDevice(const QString& id)
{
    if (auto* device = findById(id)) {
        device->start();
        persist();
    }
}

void DeviceManager::stopDevice(const QString& id)
{
    if (auto* device = findById(id)) {
        device->stop();
        persist();
    }
}

void DeviceManager::load()
{
    if (!m_settings) {
        return;
    }

    for (const auto& record : m_settings->loadDevices()) {
        if (deviceTypeFromString(record.type) != DeviceType::Web) {
            qWarning() << "Skipping unsupported persisted device type:" << record.type;
            continue;
        }

        auto* device = new WebDevice(record.id,
                                     record.name,
                                     DeviceProfile::fromName(record.profileName),
                                     record.url,
                                     this);
        // Set before the device joins the model so restoring a stored accent is
        // not mistaken for an edit worth persisting.
        device->setAccentName(record.accent);
        device->setContentTheme(record.contentTheme);
        // Restore run state before connecting Device::dataChanged. Starting a
        // saved device emits dataChanged; persisting that during load would
        // overwrite selectedDeviceId with an empty value before the saved
        // selection below has been restored.
        if (record.running) {
            device->start();
        }
        addDevice(device, false);
        // Devices keep the run state they were left in: a stopped device stays
        // stopped and shows its stopped preview, and Hesh never starts the whole
        // collection just because it launched.
    }

    if (auto* saved = findById(m_settings->selectedDeviceId())) {
        setSelectedDevice(saved);
    } else if (m_model.rowCount() > 0) {
        setSelectedDevice(m_model.at(0));
    }
}

void DeviceManager::addDevice(Device* device, bool select)
{
    if (!device) {
        return;
    }

    const auto row = m_model.rowCount();
    m_model.insertDevice(row, device);
    connect(device, &Device::dataChanged, this, [this, device] {
        const auto row = m_model.indexOf(device);
        if (row >= 0) {
            const auto modelIndex = m_model.index(row);
            emit m_model.dataChanged(modelIndex, modelIndex, {});
        }
        persist();
    });
    if (select) {
        setSelectedDevice(device);
    }
    emit deviceCountChanged();
}

void DeviceManager::persist() const
{
    if (!m_settings) {
        return;
    }

    QList<DeviceRecord> records;
    for (int row = 0; row < m_model.rowCount(); ++row) {
        const auto* device = m_model.at(row);
        DeviceRecord record;
        record.id = device->id();
        record.name = device->name();
        record.type = device->typeName();
        record.profileName = device->profileName();
        record.accent = device->accentName();
        record.running = device->isRunning();
        record.contentTheme = device->contentTheme();
        if (const auto* webDevice = qobject_cast<const WebDevice*>(device)) {
            record.url = webDevice->url();
        }
        records.append(record);
    }

    m_settings->saveDevices(records);
    m_settings->setSelectedDeviceId(m_selectedDevice ? m_selectedDevice->id() : QString {});
}

Device* DeviceManager::findById(const QString& id) const
{
    if (id.isEmpty()) {
        return nullptr;
    }
    for (int row = 0; row < m_model.rowCount(); ++row) {
        if (m_model.at(row)->id() == id) {
            return m_model.at(row);
        }
    }
    return nullptr;
}

void DeviceManager::setSelectedDevice(Device* device)
{
    if (device == m_selectedDevice) {
        return;
    }
    m_selectedDevice = device;
    emit selectedDeviceChanged();
    if (m_settings) {
        m_settings->setSelectedDeviceId(m_selectedDevice ? m_selectedDevice->id() : QString {});
    }
}

} // namespace Hesh
