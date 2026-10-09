#pragma once

#include <QProcess>

#include <functional>

#include "devices/Device.hpp"

namespace Hesh {

// A real Android phone reached through adb (USB or wireless debugging). Hesh
// mirrors its screen with scrcpy, which also carries mouse and keyboard input.
// The phone itself is never rebooted, stopped or reconfigured: stopping the
// device only closes the mirror window.
class AndroidDevice final : public Device
{
    Q_OBJECT
    Q_PROPERTY(QString serial READ serial CONSTANT)
    Q_PROPERTY(QString mode READ mode NOTIFY modeChanged)
    Q_PROPERTY(QString statusDetail READ statusDetail NOTIFY statusDetailChanged)

public:
    AndroidDevice(QString id, QString name, DeviceProfile profile, QString serial,
                  QString mode = QString(), QObject* parent = nullptr);
    ~AndroidDevice() override;

    QString serial() const { return m_serial; }
    QString statusDetail() const { return m_detail; }
    QString mode() const { return m_mode; }
    // "mirror" shows the phone's screen; "dark" also turns its own screen off.
    Q_INVOKABLE void setMode(const QString& mode);
    static QString adbPath();

    // "serial|model" for every phone adb can reach right now.
    static QStringList connectedPhones();
    // "host:port|name" for phones that are showing a wireless-debugging pairing
    // code, found through mDNS.
    static QStringList pairingCandidates();

    void start() override;
    void stop() override;
    Q_INVOKABLE void showScreen();
    // Hardware-style controls: back, home, recents, power, volume_up,
    // volume_down, notifications. screenshot() saves a PNG to Pictures.
    Q_INVOKABLE void press(const QString& control);
    Q_INVOKABLE void screenshot();

signals:
    void modeChanged();
    void statusDetailChanged();
    void screenshotSaved(const QString& path);

private:
    void setDetail(const QString& detail);
    void openScreen();
    QProcess* tool(const QStringList& arguments);

    QString m_serial;
    QString m_mode;
    QString m_detail;
    QProcess m_screen;
};

// Wireless debugging helpers used by the app, the control socket and the plugin.
// Each runs adb and calls back with (ok, message).
namespace AdbPairing {
void run(const QStringList& arguments, QObject* context, std::function<void(bool, QString)> done,
         const QString& okMarker);
void pair(const QString& address, const QString& code, QObject* context,
          std::function<void(bool, QString)> done);
void connectTo(const QString& address, QObject* context, std::function<void(bool, QString)> done);
}

} // namespace Hesh
