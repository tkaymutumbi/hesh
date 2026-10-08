#include "AndroidDevice.hpp"

#include <QDir>
#include <QFile>
#include <QProcessEnvironment>
#include <QStandardPaths>

namespace Hesh {

QString AndroidDevice::sdkRoot()
{
    const auto env = qEnvironmentVariable("ANDROID_HOME", qEnvironmentVariable("ANDROID_SDK_ROOT"));
    return env.isEmpty() ? QDir::homePath() + QStringLiteral("/.local/android-sdk") : env;
}

QString AndroidDevice::avdHome()
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/android-avd");
}

QString AndroidDevice::systemImage() const
{
    return m_flavor == QLatin1String("light") ? QStringLiteral("system-images;android-35;default;x86_64")
                                              : QStringLiteral("system-images;android-35;google_apis;x86_64");
}

QStringList AndroidDevice::connectedPhones()
{
    QProcess adb;
    adb.start(sdkRoot() + QStringLiteral("/platform-tools/adb"), {QStringLiteral("devices"), QStringLiteral("-l")});
    adb.waitForFinished(5000);
    QStringList phones;
    for (const auto& line : QString::fromUtf8(adb.readAllStandardOutput()).split(QLatin1Char('\n'))) {
        const auto parts = line.simplified().split(QLatin1Char(' '));
        if (parts.size() < 2 || parts.at(1) != QLatin1String("device") || parts.at(0).startsWith(QLatin1String("emulator-")))
            continue;
        QString model = parts.at(0);
        for (const auto& part : parts)
            if (part.startsWith(QLatin1String("model:"))) model = part.mid(6);
        phones << parts.at(0) + QLatin1Char('|') + model;
    }
    return phones;
}

QString AndroidDevice::missingRequirement() const
{
    const auto sdk = sdkRoot();
    if (QStandardPaths::findExecutable(QStringLiteral("scrcpy")).isEmpty())
        return QStringLiteral("scrcpy is not installed");
    if (isPhone()) return {};
    if (!QFile::exists(sdk + QStringLiteral("/emulator/emulator")))
        return QStringLiteral("Android Emulator is not installed (sdkmanager \"emulator\")");
    if (!QFile::exists(sdk + QLatin1Char('/') + systemImage().replace(QLatin1Char(';'), QLatin1Char('/')) + QStringLiteral("/system.img")))
        return QStringLiteral("System image missing (sdkmanager \"%1\")").arg(systemImage());
    if (!QFile::exists(QStringLiteral("/dev/kvm")))
        return QStringLiteral("KVM is not available");
    return {};
}

AndroidDevice::AndroidDevice(QString id, QString name, DeviceProfile profile, QString flavor,
                             QString phoneSerial, QObject* parent)
    : Device(std::move(id), std::move(name), DeviceType::Android, std::move(profile), parent)
    , m_flavor(flavor == QLatin1String("light") || flavor == QLatin1String("phone") ? std::move(flavor) : QStringLiteral("google"))
    , m_phoneSerial(std::move(phoneSerial))
{
    // Even ports 5556..5584, stable per device id so adb serials survive restarts.
    m_port = 5556 + 2 * int(qHash(this->id()) % 15);
    m_bootTimer.setInterval(1500);
    connect(&m_bootTimer, &QTimer::timeout, this, &AndroidDevice::pollBoot);
    connect(&m_emulator, &QProcess::finished, this, [this] {
        m_bootTimer.stop();
        if (m_screen.state() != QProcess::NotRunning) m_screen.terminate();
        if (status() != Status::Error) setDetail(m_stopping ? QString() : QStringLiteral("Emulator exited"));
        if (status() != Status::Error) setStatus(Status::Stopped);
        m_stopping = false;
    });
    connect(&m_screen, &QProcess::finished, this, [this] {
        // Closing the screen window leaves the emulator running; the panel can reopen it.
        if (status() == Status::Running) setDetail(QStringLiteral("Screen window closed"));
    });
}

AndroidDevice::~AndroidDevice()
{
    m_bootTimer.stop();
    m_screen.kill();
    if (m_emulator.state() != QProcess::NotRunning) {
        m_emulator.kill();
        m_emulator.waitForFinished(2000);
    }
}

QString AndroidDevice::serial() const { return isPhone() ? m_phoneSerial : QStringLiteral("emulator-%1").arg(m_port); }
QString AndroidDevice::avdName() const { return QStringLiteral("hesh_") + id().left(8); }
QString AndroidDevice::statusDetail() const { return m_detail; }

void AndroidDevice::setDetail(const QString& detail)
{
    if (detail == m_detail) return;
    m_detail = detail;
    emit statusDetailChanged();
}

void AndroidDevice::fail(const QString& message)
{
    setDetail(message);
    setStatus(Status::Error);
}

QProcess* AndroidDevice::tool(const QString& program, const QStringList& arguments)
{
    auto* p = new QProcess(this);
    auto env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("ANDROID_HOME"), sdkRoot());
    env.insert(QStringLiteral("ANDROID_AVD_HOME"), avdHome());
    env.insert(QStringLiteral("ANDROID_SDK_ROOT"), sdkRoot());
    p->setProcessEnvironment(env);
    connect(p, &QProcess::finished, p, &QObject::deleteLater);
    p->start(program, arguments);
    return p;
}

void AndroidDevice::start()
{
    if (status() == Status::Starting || status() == Status::Running) return;
    if (const auto missing = missingRequirement(); !missing.isEmpty()) {
        fail(missing);
        return;
    }
    m_stopping = false;
    setStatus(Status::Starting);
    setDetail(QStringLiteral("Preparing device"));

    if (isPhone()) {
        // A real handset needs no boot: confirm adb can reach it, then show it.
        auto* check = tool(sdkRoot() + QStringLiteral("/platform-tools/adb"),
                           {QStringLiteral("-s"), serial(), QStringLiteral("get-state")});
        connect(check, &QProcess::finished, this, [this, check] {
            if (QString::fromUtf8(check->readAllStandardOutput()).trimmed() != QLatin1String("device")) {
                fail(QStringLiteral("Phone not reachable. Unlock it and check USB or wireless debugging."));
                return;
            }
            setDetail(QString());
            setStatus(Status::Running);
            openScreen();
        });
        return;
    }

    const auto avdDir = avdHome() + QLatin1Char('/') + avdName() + QStringLiteral(".avd");
    if (QDir(avdDir).exists()) {
        launchEmulator();
        return;
    }
    // First start creates the virtual device from the system image.
    QDir().mkpath(avdHome());
    auto* create = new QProcess(this);
    auto env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("ANDROID_HOME"), sdkRoot());
    env.insert(QStringLiteral("ANDROID_AVD_HOME"), avdHome());
    create->setProcessEnvironment(env);
    connect(create, &QProcess::finished, this, [this, create](int code) {
        create->deleteLater();
        if (code != 0) { fail(QStringLiteral("Could not create the virtual device")); return; }
        // A roomy data partition and 2 GB of RAM suit this machine.
        const auto ini = avdHome() + QLatin1Char('/') + avdName() + QStringLiteral(".avd/config.ini");
        QFile f(ini);
        if (f.open(QIODevice::Append))
            f.write((m_flavor == QLatin1String("light") ? "hw.ramSize=1536\n" : "hw.ramSize=2048\n") + QByteArray("disk.dataPartition.size=8G\nhw.keyboard=yes\n"
                    // A compact 2:1 screen: smaller on the desktop and lighter to render.
                    "skin.name=720x1440\nskin.path=_no_skin\nhw.lcd.width=720\nhw.lcd.height=1440\nhw.lcd.density=280\n"));
        launchEmulator();
    });
    create->start(sdkRoot() + QStringLiteral("/cmdline-tools/latest/bin/avdmanager"),
                  {QStringLiteral("create"), QStringLiteral("avd"), QStringLiteral("-n"), avdName(),
                   QStringLiteral("-k"), systemImage(),
                   QStringLiteral("-d"), QStringLiteral("pixel_7"), QStringLiteral("--force")});
    create->write("no\n");
    create->closeWriteChannel();
}

void AndroidDevice::launchEmulator()
{
    setDetail(QStringLiteral("Starting Android"));
    auto env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("ANDROID_HOME"), sdkRoot());
    env.insert(QStringLiteral("ANDROID_AVD_HOME"), avdHome());
    m_emulator.setProcessEnvironment(env);
    m_emulator.setProcessChannelMode(QProcess::MergedChannels);
    m_emulator.start(sdkRoot() + QStringLiteral("/emulator/emulator"),
                     {QStringLiteral("-avd"), avdName(), QStringLiteral("-port"), QString::number(m_port),
                      QStringLiteral("-no-window"), QStringLiteral("-no-audio"), QStringLiteral("-no-boot-anim"),
                      QStringLiteral("-gpu"), QStringLiteral("swiftshader_indirect"),
                      QStringLiteral("-cores"), m_flavor == QLatin1String("light") ? QStringLiteral("3") : QStringLiteral("4"),
                      QStringLiteral("-memory"), m_flavor == QLatin1String("light") ? QStringLiteral("1536") : QStringLiteral("2048"),
                      QStringLiteral("-feature"), QStringLiteral("-Vulkan"), QStringLiteral("-netdelay"), QStringLiteral("none"),
                      QStringLiteral("-netspeed"), QStringLiteral("full")});
    m_bootChecks = 0;
    m_bootTimer.start();
}

void AndroidDevice::pollBoot()
{
    if (m_emulator.state() == QProcess::NotRunning) { m_bootTimer.stop(); return; }
    if (++m_bootChecks > 160) { m_bootTimer.stop(); m_emulator.kill(); fail(QStringLiteral("Android did not finish booting")); return; }
    auto* p = tool(sdkRoot() + QStringLiteral("/platform-tools/adb"),
                   {QStringLiteral("-s"), serial(), QStringLiteral("shell"), QStringLiteral("getprop"), QStringLiteral("sys.boot_completed")});
    connect(p, &QProcess::finished, this, [this, p] {
        if (status() != Status::Starting) return;
        if (QString::fromUtf8(p->readAllStandardOutput()).trimmed() == QLatin1String("1")) {
            m_bootTimer.stop();
            // Without a GPU, Android renders in software, and the Google apps that
            // ship in the image (Messages, Search, Photos, on-device AI...) keep
            // several cores at full load even when idle. Disable them once the
            // device is up, hide error boxes and shorten animations.
            tool(sdkRoot() + QStringLiteral("/platform-tools/adb"),
                 {QStringLiteral("-s"), serial(), QStringLiteral("shell"),
                  QStringLiteral("settings put global hide_error_dialogs 1; settings put global window_animation_scale 0.5; "
                                 "settings put global transition_animation_scale 0.5; settings put global animator_duration_scale 0.5; "
                                 "for p in com.google.android.apps.messaging com.google.android.as com.google.android.as.oss "
                                 "com.google.android.apps.maps com.google.android.youtube com.google.android.apps.photos "
                                 "com.google.android.apps.youtube.music com.google.android.apps.wellbeing com.google.android.apps.nbu.files "
                                 "com.google.android.googlequicksearchbox com.google.android.apps.docs com.google.android.apps.turbo "
                                 "com.google.android.apps.restore com.google.android.apps.tachyon com.google.android.videos "
                                 "com.google.android.music; do pm disable-user --user 0 $p; done")});
            setDetail(QString());
            setStatus(Status::Running);
            openScreen();
        } else {
            setDetail(QStringLiteral("Booting Android (%1s)").arg(int(m_bootChecks * 1.5)));
        }
    });
}

void AndroidDevice::openScreen()
{
    if (m_screen.state() != QProcess::NotRunning) return;
    // The window title follows the web devices' "<name> — Hesh" so the shell
    // overlay can find and frame it.
    QStringList extra;
    // Keeping a real phone awake would change its settings; only emulators get it.
    if (!isPhone()) extra << QStringLiteral("--stay-awake");
    m_screen.start(QStringLiteral("scrcpy"),
                   extra + QStringList{QStringLiteral("-s"), serial(), QStringLiteral("--window-title"),
                    name() + QStringLiteral(" — Hesh"), QStringLiteral("--no-audio"),
                    QStringLiteral("--max-fps"), QStringLiteral("60"),
                    QStringLiteral("--window-width"), QStringLiteral("300"), QStringLiteral("--window-height"), QStringLiteral("600")});
}

void AndroidDevice::showScreen()
{
    if (status() == Status::Running) { setDetail(QString()); openScreen(); }
}

void AndroidDevice::stop()
{
    m_bootTimer.stop();
    m_stopping = true;
    if (m_screen.state() != QProcess::NotRunning) m_screen.terminate();
    if (isPhone() || m_emulator.state() == QProcess::NotRunning) {
        setDetail(QString());
        setStatus(Status::Stopped);
        return;
    }
    setDetail(QStringLiteral("Shutting down"));
    tool(sdkRoot() + QStringLiteral("/platform-tools/adb"), {QStringLiteral("-s"), serial(), QStringLiteral("emu"), QStringLiteral("kill")});
    QTimer::singleShot(8000, this, [this] { if (m_emulator.state() != QProcess::NotRunning) m_emulator.kill(); });
}

void AndroidDevice::clearPersistentData()
{
    if (isPhone()) return;
    if (m_emulator.state() != QProcess::NotRunning) { m_emulator.kill(); m_emulator.waitForFinished(3000); }
    QDir(avdHome() + QLatin1Char('/') + avdName() + QStringLiteral(".avd")).removeRecursively();
    QFile::remove(avdHome() + QLatin1Char('/') + avdName() + QStringLiteral(".ini"));
}

} // namespace Hesh
