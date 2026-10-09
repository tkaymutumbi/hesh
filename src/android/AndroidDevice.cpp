#include "AndroidDevice.hpp"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QHash>
#include <QRegularExpression>
#include <QStandardPaths>

#include <functional>

#include <signal.h>
#include <sys/prctl.h>

namespace Hesh {

QString AndroidDevice::adbPath()
{
    const auto root = qEnvironmentVariable("ANDROID_HOME", QDir::homePath() + QStringLiteral("/.local/android-sdk"));
    const auto bundled = root + QStringLiteral("/platform-tools/adb");
    return QFile::exists(bundled) ? bundled : QStandardPaths::findExecutable(QStringLiteral("adb"));
}

QStringList AndroidDevice::connectedPhones()
{
    QProcess adb;
    adb.start(adbPath(), {QStringLiteral("devices"), QStringLiteral("-l")});
    adb.waitForFinished(5000);
    QStringList phones;
    for (const auto& line : QString::fromUtf8(adb.readAllStandardOutput()).split(QLatin1Char('\n'))) {
        const auto parts = line.simplified().split(QLatin1Char(' '));
        if (parts.size() < 2 || parts.at(1) != QLatin1String("device")
            || parts.at(0).startsWith(QLatin1String("emulator-")))
            continue;
        QString model = parts.at(0);
        for (const auto& part : parts)
            if (part.startsWith(QLatin1String("model:"))) model = QString(part.mid(6)).replace(QLatin1Char('_'), QLatin1Char(' '));
        phones << parts.at(0) + QLatin1Char('|') + model;
    }
    return phones;
}

QStringList AndroidDevice::pairingCandidates()
{
    QProcess adb;
    adb.start(adbPath(), {QStringLiteral("mdns"), QStringLiteral("services")});
    adb.waitForFinished(6000);
    QStringList found;
    for (const auto& line : QString::fromUtf8(adb.readAllStandardOutput()).split(QLatin1Char('\n'))) {
        if (!line.contains(QLatin1String("_adb-tls-pairing"))) continue;
        const auto parts = line.simplified().split(QLatin1Char(' '));
        if (parts.size() >= 3) found << parts.last() + QLatin1Char('|') + parts.first();
    }
    return found;
}

AndroidDevice::AndroidDevice(QString id, QString name, DeviceProfile profile, QString serial,
                             QString mode, QObject* parent)
    : Device(std::move(id), std::move(name), DeviceType::Android, std::move(profile), parent)
    , m_serial(std::move(serial))
    , m_mode(mode == QLatin1String("dark") ? std::move(mode) : QStringLiteral("mirror"))
{
    // The mirror must never outlive Hesh, even when Hesh is killed.
    m_screen.setChildProcessModifier([] { prctl(PR_SET_PDEATHSIG, SIGTERM); });
    connect(&m_screen, &QProcess::finished, this, [this] {
        // Closing the mirror window leaves the phone untouched; the panel can reopen it.
        if (status() == Status::Running) setDetail(QStringLiteral("Screen window closed"));
    });
}

AndroidDevice::~AndroidDevice()
{
    m_screen.kill();
}

void AndroidDevice::setDetail(const QString& detail)
{
    if (detail == m_detail) return;
    m_detail = detail;
    emit statusDetailChanged();
}

QProcess* AndroidDevice::tool(const QStringList& arguments)
{
    auto* p = new QProcess(this);
    connect(p, &QProcess::finished, p, &QObject::deleteLater);
    p->start(adbPath(), QStringList{QStringLiteral("-s"), m_serial} + arguments);
    return p;
}

void AndroidDevice::start()
{
    if (status() == Status::Starting || status() == Status::Running) return;
    if (QStandardPaths::findExecutable(QStringLiteral("scrcpy")).isEmpty() || adbPath().isEmpty()) {
        setDetail(QStringLiteral("adb and scrcpy are required"));
        setStatus(Status::Error);
        return;
    }
    setStatus(Status::Starting);
    setDetail(QStringLiteral("Connecting to the phone"));
    auto* check = tool({QStringLiteral("get-state")});
    connect(check, &QProcess::finished, this, [this, check] {
        if (QString::fromUtf8(check->readAllStandardOutput()).trimmed() != QLatin1String("device")) {
            setDetail(QStringLiteral("Phone not reachable. Unlock it and check USB or wireless debugging."));
            setStatus(Status::Error);
            return;
        }
        setDetail(QString());
        setStatus(Status::Running);
        openScreen();
    });
}

void AndroidDevice::openScreen()
{
    if (m_screen.state() != QProcess::NotRunning) return;
    // The title follows the web devices' "<name> — Hesh" so the window floats
    // and the shell overlay can find and frame it.
    QStringList arguments{QStringLiteral("-s"), m_serial, QStringLiteral("--window-title"),
                          name() + QStringLiteral(" \u2014 Hesh"), QStringLiteral("--no-audio"),
                          // Right-click opens the Hesh menu (see PhoneMenu), middle-click is Home.
                          QStringLiteral("--mouse-bind=-h--:++++"),
                          QStringLiteral("--max-fps"), QStringLiteral("60"),
                          QStringLiteral("--window-width"), QStringLiteral("300"), QStringLiteral("--window-height"), QStringLiteral("600")};
    if (m_mode == QLatin1String("dark")) arguments << QStringLiteral("--turn-screen-off");
    m_screen.start(QStringLiteral("scrcpy"), arguments);
}

void AndroidDevice::setMode(const QString& mode)
{
    const auto next = mode == QLatin1String("dark") ? mode : QStringLiteral("mirror");
    if (next == m_mode) return;
    m_mode = next;
    emit modeChanged();
    emit dataChanged();
    if (status() == Status::Running) {
        if (m_screen.state() != QProcess::NotRunning) { m_screen.terminate(); m_screen.waitForFinished(2000); }
        openScreen();
    }
}

void AndroidDevice::showScreen()
{
    if (status() == Status::Running) { setDetail(QString()); openScreen(); }
}

void AndroidDevice::stop()
{
    if (m_screen.state() != QProcess::NotRunning) m_screen.terminate();
    setDetail(QString());
    setStatus(Status::Stopped);
}

void AndroidDevice::press(const QString& control)
{
    if (status() != Status::Running) return;
    static const QHash<QString, QString> keys {
        {QStringLiteral("back"), QStringLiteral("4")}, {QStringLiteral("home"), QStringLiteral("3")},
        {QStringLiteral("recents"), QStringLiteral("187")}, {QStringLiteral("power"), QStringLiteral("26")},
        {QStringLiteral("volume_up"), QStringLiteral("24")}, {QStringLiteral("volume_down"), QStringLiteral("25")}};
    if (keys.contains(control))
        tool({QStringLiteral("shell"), QStringLiteral("input"), QStringLiteral("keyevent"), keys.value(control)});
    else if (control == QLatin1String("notifications"))
        tool({QStringLiteral("shell"), QStringLiteral("cmd"), QStringLiteral("statusbar"), QStringLiteral("expand-notifications")});
}

void AndroidDevice::screenshot()
{
    if (status() != Status::Running) return;
    const auto path = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + QStringLiteral("/hesh-")
        + QString(name()).replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9_-]+")), QStringLiteral("-"))
        + QLatin1Char('-') + QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss")) + QStringLiteral(".png");
    auto* p = tool({QStringLiteral("exec-out"), QStringLiteral("screencap"), QStringLiteral("-p")});
    connect(p, &QProcess::finished, this, [this, p, path] {
        QFile file(path);
        if (file.open(QIODevice::WriteOnly)) { file.write(p->readAllStandardOutput()); emit screenshotSaved(path); }
    });
}

namespace AdbPairing {

void run(const QStringList& arguments, QObject* context, std::function<void(bool, QString)> done,
                const QString& okMarker)
{
    auto* p = new QProcess(context);
    QObject::connect(p, &QProcess::finished, context, [p, done = std::move(done), okMarker] {
        const auto text = QString::fromUtf8(p->readAllStandardOutput() + p->readAllStandardError()).trimmed();
        done(text.contains(okMarker, Qt::CaseInsensitive), text.left(160));
        p->deleteLater();
    });
    p->start(AndroidDevice::adbPath(), arguments);
}

void pair(const QString& address, const QString& code, QObject* context, std::function<void(bool, QString)> done)
{
    static const QRegularExpression addressPattern(QStringLiteral("^[A-Za-z0-9.\\-]+:\\d{2,5}$"));
    static const QRegularExpression codePattern(QStringLiteral("^\\d{6}$"));
    if (!addressPattern.match(address.trimmed()).hasMatch()) { done(false, QStringLiteral("Enter the pairing address as host:port")); return; }
    if (!codePattern.match(code.trimmed()).hasMatch()) { done(false, QStringLiteral("The pairing code is six digits")); return; }
    run({QStringLiteral("pair"), address.trimmed(), code.trimmed()}, context, std::move(done), QStringLiteral("Successfully paired"));
}

void connectTo(const QString& address, QObject* context, std::function<void(bool, QString)> done)
{
    static const QRegularExpression addressPattern(QStringLiteral("^[A-Za-z0-9.\\-]+:\\d{2,5}$"));
    if (!addressPattern.match(address.trimmed()).hasMatch()) { done(false, QStringLiteral("Enter the address as host:port")); return; }
    run({QStringLiteral("connect"), address.trimmed()}, context, std::move(done), QStringLiteral("connected"));
}

} // namespace AdbPairing

} // namespace Hesh
