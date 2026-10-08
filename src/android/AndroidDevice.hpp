#pragma once

#include <QProcess>
#include <QTimer>

#include "devices/Device.hpp"

namespace Hesh {

// A real Android device: the official Android Emulator (x86_64, KVM) running
// headless, driven through adb. Hesh shows its screen with scrcpy, which also
// carries mouse and keyboard input. Each device owns one AVD named after its id.
class AndroidDevice final : public Device
{
    Q_OBJECT
    Q_PROPERTY(QString serial READ serial CONSTANT)
    Q_PROPERTY(QString statusDetail READ statusDetail NOTIFY statusDetailChanged)

public:
    AndroidDevice(QString id, QString name, DeviceProfile profile, QObject* parent = nullptr);
    ~AndroidDevice() override;

    QString serial() const;
    QString avdName() const;
    QString statusDetail() const;
    static QString sdkRoot();
    // Hesh keeps its virtual devices in its own data directory.
    static QString avdHome();
    // Why the Android runtime cannot be used on this machine, or empty.
    static QString missingRequirement();

    void start() override;
    void stop() override;
    Q_INVOKABLE void showScreen();

signals:
    void statusDetailChanged();

protected:
    void clearPersistentData() override;

private:
    void setDetail(const QString& detail);
    void launchEmulator();
    void pollBoot();
    void openScreen();
    void fail(const QString& message);
    QProcess* tool(const QString& program, const QStringList& arguments);

    int m_port = 5554;
    QString m_detail;
    QProcess m_emulator;
    QProcess m_screen;
    QTimer m_bootTimer;
    int m_bootChecks = 0;
    bool m_stopping = false;
};

} // namespace Hesh
