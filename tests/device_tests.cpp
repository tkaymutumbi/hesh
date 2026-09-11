#include <QtTest>

#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QTemporaryDir>

#include "app/Settings.hpp"
#include "devices/DeviceManager.hpp"
#include "devices/DeviceProfile.hpp"
#include "web/WebDevice.hpp"

using namespace Hesh;

class DeviceTests final : public QObject
{
    Q_OBJECT

private slots:
    void createWebDevice();
    void removeDevice();
    void clearDeviceData();
    void selectDevice();
    void profileAssignment();
    void persistenceRoundTrip();
};

void DeviceTests::createWebDevice()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());

    Settings settings(QStringLiteral("HeshTests"), QStringLiteral("Create"),
                      directory.filePath(QStringLiteral("settings.ini")));
    DeviceManager manager(&settings);
    auto* device = manager.createWebDevice(QStringLiteral("Preview"),
                                           QStringLiteral("Pixel 7"),
                                           QStringLiteral("http://localhost:3000"));

    QVERIFY(device != nullptr);
    QCOMPARE(manager.deviceCount(), 1);
    QCOMPARE(device->name(), QStringLiteral("Preview"));
    QCOMPARE(device->typeName(), QStringLiteral("web"));
    QCOMPARE(device->statusName(), QStringLiteral("Running"));
    QCOMPARE(manager.selectedDevice(), static_cast<Device*>(device));
}

void DeviceTests::removeDevice()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());

    Settings settings(QStringLiteral("HeshTests"), QStringLiteral("Remove"),
                      directory.filePath(QStringLiteral("settings.ini")));
    DeviceManager manager(&settings);
    auto* first = manager.createWebDevice(QStringLiteral("First"), QStringLiteral("Pixel 7"), {});
    auto* second = manager.createWebDevice(QStringLiteral("Second"), QStringLiteral("Pixel 8"), {});
    QVERIFY(first != nullptr);
    QVERIFY(second != nullptr);

    manager.removeDevice(second->id());
    QCOMPARE(manager.deviceCount(), 1);
    QCOMPARE(manager.selectedDevice(), static_cast<Device*>(first));
}

void DeviceTests::clearDeviceData()
{
    // Keep the device storage inside the Qt test directory instead of the real
    // application-data location.
    QStandardPaths::setTestModeEnabled(true);

    QTemporaryDir directory;
    QVERIFY(directory.isValid());

    Settings settings(QStringLiteral("HeshTests"), QStringLiteral("ClearData"),
                      directory.filePath(QStringLiteral("settings.ini")));
    DeviceManager manager(&settings);
    auto* device = manager.createWebDevice(QStringLiteral("Preview"),
                                           QStringLiteral("Pixel 7"),
                                           QStringLiteral("http://localhost:3000"));
    QVERIFY(device != nullptr);

    const auto* webDevice = qobject_cast<const WebDevice*>(device);
    QVERIFY(webDevice != nullptr);
    QVERIFY(!webDevice->persistentStoragePath().isEmpty());
    QVERIFY(!webDevice->cachePath().isEmpty());

    // Store data where Chromium would, so clearing has something to remove.
    for (const auto& path : {webDevice->persistentStoragePath(), webDevice->cachePath()}) {
        QDir storage(path);
        QVERIFY(storage.mkpath(QStringLiteral(".")));
        QFile file(storage.filePath(QStringLiteral("stored-data")));
        QVERIFY(file.open(QIODevice::WriteOnly));
        QCOMPARE(file.write("payload"), qint64(7));
        file.close();
    }

    QSignalSpy clearing(device, &Device::dataClearing);
    QSignalSpy cleared(device, &Device::dataCleared);

    // An unknown device is ignored instead of wiping anything.
    manager.clearDeviceData(QStringLiteral("missing-device"));
    QCOMPARE(clearing.count(), 0);

    manager.clearDeviceData(device->id());
    // Hosts release their browser surface while the wipe is pending, so the
    // directories must still be present when the first signal arrives.
    QCOMPARE(clearing.count(), 1);
    QVERIFY(QDir(webDevice->persistentStoragePath()).exists());

    QTRY_COMPARE(cleared.count(), 1);
    QVERIFY(!QDir(webDevice->persistentStoragePath()).exists());
    QVERIFY(!QDir(webDevice->cachePath()).exists());
}

void DeviceTests::selectDevice()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());

    Settings settings(QStringLiteral("HeshTests"), QStringLiteral("Select"),
                      directory.filePath(QStringLiteral("settings.ini")));
    DeviceManager manager(&settings);
    auto* first = manager.createWebDevice(QStringLiteral("First"), QStringLiteral("Pixel 7"), {});
    auto* second = manager.createWebDevice(QStringLiteral("Second"), QStringLiteral("iPhone 14"), {});

    manager.selectDevice(first->id());
    QCOMPARE(manager.selectedDevice(), static_cast<Device*>(first));
    manager.selectDevice(second->id());
    QCOMPARE(manager.selectedDevice(), static_cast<Device*>(second));
}

void DeviceTests::profileAssignment()
{
    const auto profile = DeviceProfile::fromName(QStringLiteral("Pixel 8"));
    QCOMPARE(profile.name, QStringLiteral("Pixel 8"));
    QCOMPARE(profile.width, 412);
    QCOMPARE(profile.height, 915);
    QCOMPARE(profile.devicePixelRatio, 2.75);

    WebDevice device(QStringLiteral("profile-test"),
                     QStringLiteral("Profile test"),
                     profile,
                     QStringLiteral("http://localhost:3000"));
    QCOMPARE(device.profileName(), QStringLiteral("Pixel 8"));
    QCOMPARE(device.viewportWidth(), 412);
    QCOMPARE(device.viewportHeight(), 915);
    QCOMPARE(device.devicePixelRatio(), 2.75);
}

void DeviceTests::persistenceRoundTrip()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto settingsPath = directory.filePath(QStringLiteral("settings.ini"));

    {
        Settings settings(QStringLiteral("HeshTests"), QStringLiteral("Persistence"), settingsPath);
        DeviceManager manager(&settings);
        manager.createWebDevice(QStringLiteral("Persisted"),
                                QStringLiteral("Galaxy S24"),
                                QStringLiteral("http://localhost:4173"));
    }

    Settings reloadedSettings(QStringLiteral("HeshTests"), QStringLiteral("Persistence"), settingsPath);
    DeviceManager reloaded(&reloadedSettings);
    QCOMPARE(reloaded.deviceCount(), 1);
    QVERIFY(reloaded.selectedDevice() != nullptr);
    QCOMPARE(reloaded.selectedDevice()->name(), QStringLiteral("Persisted"));
    QCOMPARE(reloaded.selectedDevice()->profileName(), QStringLiteral("Galaxy S24"));
    const auto* webDevice = qobject_cast<const WebDevice*>(reloaded.selectedDevice());
    QVERIFY(webDevice != nullptr);
    QCOMPARE(webDevice->url(), QStringLiteral("http://localhost:4173"));
}

QTEST_MAIN(DeviceTests)

#include "device_tests.moc"
