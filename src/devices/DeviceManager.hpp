#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QObject>
#include <QTimer>
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
    // Moves a row to a new index in the resulting order. The view is notified
    // through beginMoveRows/endMoveRows so delegates move instead of rebuilding.
    void moveDevice(int from, int to);
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
    Q_INVOKABLE Device* createAndroidDevice(const QString& name, const QString& profileName,
                                            const QString& phoneSerial);
    // Phones adb can reach ("serial|model") and phones offering a wireless
    // pairing code ("host:port|name").
    Q_INVOKABLE QStringList connectedPhones() const;
    Q_INVOKABLE QStringList pairingCandidates() const;
    // Wireless debugging. The result arrives through phoneActionFinished.
    Q_INVOKABLE void pairPhone(const QString& address, const QString& code);
    Q_INVOKABLE void connectPhone(const QString& address);
    // Pair by QR code: shows a code the phone scans from Wireless debugging,
    // "Pair device with QR code". The phone then advertises a pairing service
    // under the code's name, which Hesh finds over mDNS and pairs with.
    // startQrPairing() returns the path of the code image (empty if it cannot
    // be made); qrPairingState() is "idle", "waiting", "paired", "failed" or
    // "expired".
    Q_INVOKABLE QString startQrPairing();
    Q_INVOKABLE void cancelQrPairing();
    Q_INVOKABLE QString qrPairingState() const { return m_qrState; }
    Q_INVOKABLE QString qrPairingMessage() const { return m_qrMessage; }
    Q_INVOKABLE QObject* deviceById(const QString& id) const { return findById(id); }
    Q_INVOKABLE void removeDevice(const QString& id);
    Q_INVOKABLE void clearDeviceData(const QString& id);
    Q_INVOKABLE void clearAllDeviceData();
    Q_INVOKABLE void setDeviceAccent(const QString& id, const QString& accentName);
    Q_INVOKABLE void setDeviceContentTheme(const QString& id, const QString& theme);
    // Moves a device to an insertion boundary in the list: targetIndex counts
    // the boundaries between rows, so a value equal to the row count moves the
    // device to the end. Dropping a device onto its own boundary is a no-op.
    Q_INVOKABLE void moveDevice(const QString& id, int targetIndex);
    Q_INVOKABLE void selectDevice(const QString& id);
    Q_INVOKABLE void startDevice(const QString& id);
    Q_INVOKABLE void stopDevice(const QString& id);

signals:
    void qrPairingChanged();
    void phoneActionFinished(bool ok, const QString& message);
    void selectedDeviceChanged();
    void deviceCountChanged();

private:
    void pollQrPairing();
    void setQrState(const QString& state, const QString& message);
    QTimer m_qrTimer;
    QString m_qrName, m_qrPassword, m_qrState = QStringLiteral("idle"), m_qrMessage;
    int m_qrChecks = 0;
    bool m_qrBusy = false;
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
