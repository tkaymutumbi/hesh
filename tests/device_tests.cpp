#include <QtTest>

#include <QDir>
#include <QFile>
#include <QSettings>
#include <QStandardPaths>
#include <QTemporaryDir>

#include "app/Preferences.hpp"
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
    void clearAllDeviceData();
    void selectDevice();
    void profileAssignment();
    void persistenceRoundTrip();
    void preferenceDefaults();
    void preferenceRoundTrip();
    void unknownAccentFallsBack();
    void deviceAccentColors();
    void deviceAccentRoundTrip();
    void deviceRunStatePersists();
    void legacyDeviceRecordsLoadStopped();
    void deviceContentThemePersists();
    void restartRequiredTracksEdits();
    void resetPreferencesKeepsDevices();
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

void DeviceTests::clearAllDeviceData()
{
    QStandardPaths::setTestModeEnabled(true);

    QTemporaryDir directory;
    QVERIFY(directory.isValid());

    Settings settings(QStringLiteral("HeshTests"), QStringLiteral("ClearAll"),
                      directory.filePath(QStringLiteral("settings.ini")));
    DeviceManager manager(&settings);
    auto* first = manager.createWebDevice(QStringLiteral("First"), QStringLiteral("Pixel 7"), {});
    auto* second = manager.createWebDevice(QStringLiteral("Second"), QStringLiteral("Pixel 8"), {});
    QVERIFY(first != nullptr);
    QVERIFY(second != nullptr);

    QStringList paths;
    for (auto* device : {first, second}) {
        const auto* webDevice = qobject_cast<const WebDevice*>(device);
        QVERIFY(webDevice != nullptr);
        for (const auto& path : {webDevice->persistentStoragePath(), webDevice->cachePath()}) {
            QDir storage(path);
            QVERIFY(storage.mkpath(QStringLiteral(".")));
            QFile file(storage.filePath(QStringLiteral("stored-data")));
            QVERIFY(file.open(QIODevice::WriteOnly));
            file.close();
            paths.append(path);
        }
    }

    manager.clearAllDeviceData();

    // Every device's storage goes, not just the selected one.
    for (const auto& path : paths) {
        QTRY_VERIFY_WITH_TIMEOUT(!QDir(path).exists(), 5000);
    }
    QCOMPARE(manager.deviceCount(), 2);
}

void DeviceTests::preferenceDefaults()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());

    Settings settings(QStringLiteral("HeshTests"), QStringLiteral("Defaults"),
                      directory.filePath(QStringLiteral("settings.ini")));
    Preferences preferences(&settings);

    QCOMPARE(preferences.newDeviceName(), QStringLiteral("Pixel 7 Development"));
    QCOMPARE(preferences.newDeviceUrl(), QStringLiteral("http://localhost:3000"));
    QCOMPARE(preferences.newDeviceProfile(), QStringLiteral("Pixel 7"));
    QCOMPARE(preferences.allowUpscale(), false);
    QCOMPARE(preferences.showDevToolsOnOpen(), false);
    QCOMPARE(preferences.openInStandalone(), false);
    QCOMPARE(preferences.showMetrics(), true);
    QCOMPARE(preferences.accentName(), QStringLiteral("Indigo"));
    QCOMPARE(preferences.accent(), QColor(QStringLiteral("#a4a7ff")));
    QCOMPARE(preferences.accentBorder(), QColor(QStringLiteral("#454a75")));
    QCOMPARE(preferences.accentPresets().size(), 6);
    QVERIFY(preferences.extraChromiumFlags().isEmpty());
    QCOMPARE(preferences.restartRequired(), false);

    // Empty input is not a value: it falls back instead of persisting blank
    // fields into the next Create Device dialog.
    preferences.setNewDeviceName(QStringLiteral("   "));
    preferences.setNewDeviceUrl(QString());
    QCOMPARE(preferences.newDeviceName(), QStringLiteral("Pixel 7 Development"));
    QCOMPARE(preferences.newDeviceUrl(), QStringLiteral("http://localhost:3000"));
}

void DeviceTests::preferenceRoundTrip()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto settingsPath = directory.filePath(QStringLiteral("settings.ini"));

    {
        Settings settings(QStringLiteral("HeshTests"), QStringLiteral("Preferences"), settingsPath);
        Preferences preferences(&settings);
        preferences.setNewDeviceName(QStringLiteral("Staging tablet"));
        preferences.setNewDeviceUrl(QStringLiteral("http://localhost:5173"));
        preferences.setNewDeviceProfile(QStringLiteral("Galaxy S24"));
        preferences.setAllowUpscale(true);
        preferences.setShowDevToolsOnOpen(true);
        preferences.setOpenInStandalone(true);
        preferences.setShowMetrics(false);
        preferences.setAccentName(QStringLiteral("Cyan"));
    }

    Settings reloadedSettings(QStringLiteral("HeshTests"), QStringLiteral("Preferences"), settingsPath);
    Preferences reloaded(&reloadedSettings);
    QCOMPARE(reloaded.newDeviceName(), QStringLiteral("Staging tablet"));
    QCOMPARE(reloaded.newDeviceUrl(), QStringLiteral("http://localhost:5173"));
    QCOMPARE(reloaded.newDeviceProfile(), QStringLiteral("Galaxy S24"));
    QCOMPARE(reloaded.allowUpscale(), true);
    QCOMPARE(reloaded.showDevToolsOnOpen(), true);
    QCOMPARE(reloaded.openInStandalone(), true);
    QCOMPARE(reloaded.showMetrics(), false);
    QCOMPARE(reloaded.accentName(), QStringLiteral("Cyan"));
    QCOMPARE(reloaded.accent(), QColor(QStringLiteral("#66d9e8")));
}

void DeviceTests::unknownAccentFallsBack()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());

    Settings settings(QStringLiteral("HeshTests"), QStringLiteral("Accent"),
                      directory.filePath(QStringLiteral("settings.ini")));
    // A hand-edited or stale name must not leave the palette without an accent.
    settings.setPreference(QStringLiteral("appearance/accent"), QStringLiteral("Chartreuse"));

    Preferences preferences(&settings);
    QCOMPARE(preferences.accentName(), QStringLiteral("Indigo"));
    QCOMPARE(preferences.accent(), QColor(QStringLiteral("#a4a7ff")));
}

void DeviceTests::deviceAccentColors()
{
    const auto profile = DeviceProfile::fromName(QStringLiteral("Pixel 7"));
    WebDevice device(QStringLiteral("accent-test"),
                     QStringLiteral("Accent test"),
                     profile,
                     QStringLiteral("http://localhost:3000"));

    // A device with no accent follows the application accent, which the
    // presentation layer resolves; the model only reports that there is none.
    QCOMPARE(device.accentName(), QString());
    QCOMPARE(device.hasAccent(), false);

    device.setAccentName(QStringLiteral("Cyan"));
    QCOMPARE(device.hasAccent(), true);
    QCOMPARE(device.accentName(), QStringLiteral("Cyan"));
    QCOMPARE(device.accent(), QColor(QStringLiteral("#66d9e8")));
    QCOMPARE(device.accentStrong(), QColor(QStringLiteral("#45bed0")));
    QCOMPARE(device.accentSoft(), QColor(QStringLiteral("#1f3a41")));
    QCOMPARE(device.accentBorder(), QColor(QStringLiteral("#33626c")));

    // Names this build cannot draw are not stored as accents.
    device.setAccentName(QStringLiteral("Chartreuse"));
    QCOMPARE(device.hasAccent(), false);
    QCOMPARE(device.accentName(), QString());

    device.setAccentName(QStringLiteral("Rose"));
    QCOMPARE(device.accentName(), QStringLiteral("Rose"));
    device.setAccentName(QString());
    QCOMPARE(device.hasAccent(), false);
}

void DeviceTests::deviceAccentRoundTrip()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto settingsPath = directory.filePath(QStringLiteral("settings.ini"));

    QString accentedId;
    QString inheritedId;
    {
        Settings settings(QStringLiteral("HeshTests"), QStringLiteral("DeviceAccent"), settingsPath);
        DeviceManager manager(&settings);
        auto* accented = manager.createWebDevice(QStringLiteral("Accented"),
                                                 QStringLiteral("Pixel 7"),
                                                 QStringLiteral("http://localhost:3000"));
        auto* inherited = manager.createWebDevice(QStringLiteral("Inherited"),
                                                  QStringLiteral("Pixel 8"),
                                                  QStringLiteral("http://localhost:3001"));
        QVERIFY(accented != nullptr);
        QVERIFY(inherited != nullptr);
        accentedId = accented->id();
        inheritedId = inherited->id();

        manager.setDeviceAccent(accentedId, QStringLiteral("Violet"));
        QCOMPARE(accented->accentName(), QStringLiteral("Violet"));
        // An unknown device id is ignored instead of touching anything.
        manager.setDeviceAccent(QStringLiteral("missing-device"), QStringLiteral("Rose"));
        QCOMPARE(inherited->hasAccent(), false);
    }

    Settings reloadedSettings(QStringLiteral("HeshTests"), QStringLiteral("DeviceAccent"), settingsPath);
    DeviceManager reloaded(&reloadedSettings);
    QCOMPARE(reloaded.deviceCount(), 2);

    reloaded.selectDevice(accentedId);
    QVERIFY(reloaded.selectedDevice() != nullptr);
    QCOMPARE(reloaded.selectedDevice()->accentName(), QStringLiteral("Violet"));

    reloaded.selectDevice(inheritedId);
    QVERIFY(reloaded.selectedDevice() != nullptr);
    QCOMPARE(reloaded.selectedDevice()->hasAccent(), false);
}

void DeviceTests::deviceRunStatePersists()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto settingsPath = directory.filePath(QStringLiteral("settings.ini"));

    QString runningId;
    QString stoppedId;
    {
        Settings settings(QStringLiteral("HeshTests"), QStringLiteral("RunState"), settingsPath);
        DeviceManager manager(&settings);
        auto* running = manager.createWebDevice(QStringLiteral("Running"), QStringLiteral("Pixel 7"), {});
        auto* stopped = manager.createWebDevice(QStringLiteral("Stopped"), QStringLiteral("Pixel 8"), {});
        QVERIFY(running != nullptr);
        QVERIFY(stopped != nullptr);
        runningId = running->id();
        stoppedId = stopped->id();

        // A created device is running until it is stopped.
        QCOMPARE(running->statusName(), QStringLiteral("Running"));
        manager.stopDevice(stoppedId);
        QCOMPARE(stopped->statusName(), QStringLiteral("Stopped"));
    }

    // The state is written when it changes rather than on exit, so a stopped
    // device is already stopped in storage.
    {
        Settings settings(QStringLiteral("HeshTests"), QStringLiteral("RunState"), settingsPath);
        DeviceManager manager(&settings);
        QCOMPARE(manager.deviceCount(), 2);

        manager.selectDevice(runningId);
        QCOMPARE(manager.selectedDevice()->statusName(), QStringLiteral("Running"));
        manager.selectDevice(stoppedId);
        QCOMPARE(manager.selectedDevice()->statusName(), QStringLiteral("Stopped"));

        // Opening Hesh starts only what was running; the rest stay stopped.
        manager.startDevice(stoppedId);
        manager.stopDevice(runningId);
    }

    Settings settings(QStringLiteral("HeshTests"), QStringLiteral("RunState"), settingsPath);
    DeviceManager manager(&settings);
    manager.selectDevice(runningId);
    QCOMPARE(manager.selectedDevice()->statusName(), QStringLiteral("Stopped"));
    manager.selectDevice(stoppedId);
    QCOMPARE(manager.selectedDevice()->statusName(), QStringLiteral("Running"));
}

void DeviceTests::legacyDeviceRecordsLoadStopped()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto settingsPath = directory.filePath(QStringLiteral("settings.ini"));

    // A record written before run state was persisted carries no "running" key.
    {
        QSettings raw(settingsPath, QSettings::IniFormat);
        raw.setValue(QStringLiteral("devices"),
                     QByteArray("[{\"id\":\"legacy-device\",\"name\":\"Legacy\",\"type\":\"web\","
                                "\"profile\":\"Pixel 7\",\"url\":\"http://localhost:3000\"}]"));
        raw.sync();
    }

    Settings settings(QStringLiteral("HeshTests"), QStringLiteral("Legacy"), settingsPath);
    DeviceManager manager(&settings);
    QCOMPARE(manager.deviceCount(), 1);
    QVERIFY(manager.selectedDevice() != nullptr);
    QCOMPARE(manager.selectedDevice()->name(), QStringLiteral("Legacy"));
    // Absent means not running: Hesh must not start devices it was never told
    // to start, and the preview shows its stopped state instead.
    QCOMPARE(manager.selectedDevice()->statusName(), QStringLiteral("Stopped"));
}

void DeviceTests::deviceContentThemePersists()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto settingsPath = directory.filePath(QStringLiteral("settings.ini"));

    QString darkId;
    QString systemId;
    {
        Settings settings(QStringLiteral("HeshTests"), QStringLiteral("Theme"), settingsPath);
        DeviceManager manager(&settings);
        auto* dark = manager.createWebDevice(QStringLiteral("Dark"), QStringLiteral("Pixel 7"), {});
        auto* system = manager.createWebDevice(QStringLiteral("System"), QStringLiteral("Pixel 8"), {});
        QVERIFY(dark != nullptr);
        QVERIFY(system != nullptr);
        darkId = dark->id();
        systemId = system->id();

        // A device follows the desktop scheme until it is told otherwise.
        QCOMPARE(dark->contentTheme(), QStringLiteral("system"));

        manager.setDeviceContentTheme(darkId, QStringLiteral("dark"));
        QCOMPARE(dark->contentTheme(), QStringLiteral("dark"));

        // Only force-dark exists; anything else is "system", including values a
        // hand-edited settings file might carry.
        manager.setDeviceContentTheme(systemId, QStringLiteral("light"));
        QCOMPARE(system->contentTheme(), QStringLiteral("system"));
        manager.setDeviceContentTheme(QStringLiteral("missing-device"), QStringLiteral("dark"));
    }

    Settings reloadedSettings(QStringLiteral("HeshTests"), QStringLiteral("Theme"), settingsPath);
    DeviceManager reloaded(&reloadedSettings);
    reloaded.selectDevice(darkId);
    QCOMPARE(reloaded.selectedDevice()->contentTheme(), QStringLiteral("dark"));
    reloaded.selectDevice(systemId);
    QCOMPARE(reloaded.selectedDevice()->contentTheme(), QStringLiteral("system"));

    // Switching back to the desktop scheme round-trips too.
    reloaded.setDeviceContentTheme(darkId, QStringLiteral("system"));
    Settings again(QStringLiteral("HeshTests"), QStringLiteral("Theme"), settingsPath);
    DeviceManager reloadedAgain(&again);
    reloadedAgain.selectDevice(darkId);
    QCOMPARE(reloadedAgain.selectedDevice()->contentTheme(), QStringLiteral("system"));
}

void DeviceTests::restartRequiredTracksEdits()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());
    const auto settingsPath = directory.filePath(QStringLiteral("settings.ini"));

    Settings settings(QStringLiteral("HeshTests"), QStringLiteral("Restart"), settingsPath);
    Preferences preferences(&settings);
    QCOMPARE(preferences.restartRequired(), false);

    // Chromium reads its command line once, so an edit that differs from what
    // this process started with has to ask for a relaunch.
    preferences.setExtraChromiumFlags(QStringLiteral("--enable-features=WebUIDarkMode"));
    QCOMPARE(preferences.restartRequired(), true);

    // A fresh process that started with the stored flags reports no restart.
    Settings reloadedSettings(QStringLiteral("HeshTests"), QStringLiteral("Restart"), settingsPath);
    Preferences reloaded(&reloadedSettings);
    QCOMPARE(reloaded.extraChromiumFlags(), QStringLiteral("--enable-features=WebUIDarkMode"));
    QCOMPARE(reloaded.restartRequired(), false);
}

void DeviceTests::resetPreferencesKeepsDevices()
{
    QTemporaryDir directory;
    QVERIFY(directory.isValid());

    Settings settings(QStringLiteral("HeshTests"), QStringLiteral("Reset"),
                      directory.filePath(QStringLiteral("settings.ini")));
    Preferences preferences(&settings);
    DeviceManager manager(&settings);
    auto* device = manager.createWebDevice(QStringLiteral("Persisted"),
                                           QStringLiteral("iPad"),
                                           QStringLiteral("http://localhost:8080"));
    QVERIFY(device != nullptr);

    preferences.setAccentName(QStringLiteral("Violet"));
    preferences.setAllowUpscale(true);
    preferences.setNewDeviceName(QStringLiteral("Renamed default"));

    preferences.resetToDefaults();

    QCOMPARE(preferences.accentName(), QStringLiteral("Indigo"));
    QCOMPARE(preferences.allowUpscale(), false);
    QCOMPARE(preferences.newDeviceName(), QStringLiteral("Pixel 7 Development"));

    // Restoring preferences must never touch the device collection.
    QCOMPARE(manager.deviceCount(), 1);
    QCOMPARE(manager.selectedDevice(), static_cast<Device*>(device));
    QCOMPARE(device->name(), QStringLiteral("Persisted"));
    QCOMPARE(device->profileName(), QStringLiteral("iPad"));
}

QTEST_MAIN(DeviceTests)

#include "device_tests.moc"
