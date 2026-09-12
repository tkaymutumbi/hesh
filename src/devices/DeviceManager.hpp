#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QObject>
#include <QVariantList>

#include "Device.hpp"
#include "web/WebDevice.hpp"

namespace Hesh {

class Settings;

class DeviceListModel final : public QAbstractListModel
{
    Q_OBJECT

public:
    enum Role {
        DeviceObjectRole = Qt::UserRole + 1,
        DeviceIdRole,
        DeviceNameRole,
        DeviceTypeRole,
        DeviceTypeLabelRole,
        DeviceStatusRole,
        DeviceProfileRole,
        DeviceUrlRole,
    };
    Q_ENUM(Role)

    explicit DeviceListModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = {}) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void insertDevice(int row, Device* device);
    void removeDevice(int row);
    Device* at(int row) const;
    int indexOf(const Device* device) const;

private:
    QList<Device*> m_devices;
};

class DeviceManager final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QAbstractListModel* devices READ devices CONSTANT)
    Q_PROPERTY(Device* selectedDevice READ selectedDevice NOTIFY selectedDeviceChanged)
    Q_PROPERTY(int deviceCount READ deviceCount NOTIFY deviceCountChanged)
    Q_PROPERTY(QVariantList availableProfiles READ availableProfiles CONSTANT)

public:
    explicit DeviceManager(Settings* settings, QObject* parent = nullptr);

    QAbstractListModel* devices();
    Device* selectedDevice() const;
    int deviceCount() const;
    QVariantList availableProfiles() const;

    Q_INVOKABLE WebDevice* createWebDevice(const QString& name,
                                           const QString& profileName,
                                           const QString& url);
    Q_INVOKABLE void removeDevice(const QString& id);
    Q_INVOKABLE void clearDeviceData(const QString& id);
    Q_INVOKABLE void clearAllDeviceData();
    Q_INVOKABLE void setDeviceAccent(const QString& id, const QString& accentName);
    Q_INVOKABLE void setDeviceContentTheme(const QString& id, const QString& theme);
    Q_INVOKABLE void selectDevice(const QString& id);
    Q_INVOKABLE void startDevice(const QString& id);
    Q_INVOKABLE void stopDevice(const QString& id);

signals:
    void selectedDeviceChanged();
    void deviceCountChanged();

private:
    void load();
    void addDevice(Device* device, bool select);
    void persist() const;
    Device* findById(const QString& id) const;
    void setSelectedDevice(Device* device);

    DeviceListModel m_model;
    Settings* m_settings = nullptr;
    Device* m_selectedDevice = nullptr;
};

} // namespace Hesh
