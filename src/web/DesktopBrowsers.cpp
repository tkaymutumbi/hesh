#include "DesktopBrowsers.hpp"
#include "web/WebDevice.hpp"
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QProcess>
#include <QScreen>
#include <QStandardPaths>
#include <QUuid>

namespace Hesh {
DesktopBrowsers::DesktopBrowsers(QObject* parent) : QObject(parent) {
    for (const auto& name : {"chromium", "chromium-browser", "google-chrome", "google-chrome-stable"}) {
        m_binary = QStandardPaths::findExecutable(name);
        if (!m_binary.isEmpty()) break;
    }
    m_poll.setInterval(1000);
    connect(&m_poll, &QTimer::timeout, this, [this] {
        for (auto it = m_browsers.begin(); it != m_browsers.end(); ++it)
            if (it->pending.isEmpty()) send(it.key(), {}, {{"action", "state"}});
    });
    m_poll.start();
}
DesktopBrowsers::~DesktopBrowsers() {
    const auto ids = m_browsers.keys();
    for (const auto& id : ids) close(id);
}
bool DesktopBrowsers::usesNative(QObject* object) const {
    const auto* device = qobject_cast<WebDevice*>(object);
    const auto mode = qEnvironmentVariable("HESH_DESKTOP_BROWSER");
    return device && device->profileName() == "Desktop" && !m_binary.isEmpty()
        && mode == "chromium";
}
bool DesktopBrowsers::running(const QString& id) const {
    const auto process = m_browsers.value(id).process;
    return process && process->state() != QProcess::NotRunning;
}
QJsonObject DesktopBrowsers::context(const QString& id) const { return m_browsers.value(id).state; }
void DesktopBrowsers::send(const QString& id, const QString& token, const QJsonObject& command) {
    auto it = m_browsers.find(id);
    if (it == m_browsers.end() || !running(id)) {
        if (!token.isEmpty()) emit finished(token, {{"ok", false}, {"error", "Page is not ready; open the desktop device preview"}});
        return;
    }
    auto request = command;
    request.insert("token", token);
    if (!token.isEmpty()) it->pending.append(token);
    it->process->write(QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n');
}
void DesktopBrowsers::execute(const QString& id, const QString& token, const QJsonObject& command) { send(id, token, command); }
void DesktopBrowsers::open(QObject* object, bool focus) {
    auto* device = qobject_cast<WebDevice*>(object);
    if (!usesNative(device)) return;
    const auto id = device->id();
    if (running(id)) { if (focus) send(id, {}, {{"action", "focus"}}); return; }
    const auto python = QStandardPaths::findExecutable("python3");
    QFile bridge(":/automation/desktop_browser.py"), script(":/automation/page.js");
    if (python.isEmpty() || !bridge.open(QIODevice::ReadOnly) || !script.open(QIODevice::ReadOnly)) {
        emit console(id, 2, "Python 3 and the desktop browser bridge are required", 0, {});
        return;
    }
    auto* process = new QProcess(this);
    Browser browser;
    browser.process = process;
    browser.device = device;
    m_browsers.insert(id, browser);
    process->setProcessChannelMode(QProcess::SeparateChannels);
    connect(process, &QProcess::readyReadStandardOutput, this, [this, id] { read(id); });
    // Chromium's stderr can contain private URLs. Drain it without publishing it.
    connect(process, &QProcess::readyReadStandardError, process, [process] { process->readAllStandardError(); });
    connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this, [this, id, process] {
        auto it = m_browsers.find(id);
        if (it != m_browsers.end() && it->process == process) {
            const auto pending = it->pending;
            m_browsers.erase(it);
            for (const auto& token : pending) emit finished(token, {{"ok", false}, {"error", "Desktop browser closed"}});
            emit closed(id);
        }
        process->deleteLater();
    });
    connect(process, &QProcess::errorOccurred, this, [this, id, process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart && m_browsers.value(id).process == process) {
            m_browsers.remove(id);
            emit console(id, 2, "Could not start the desktop browser", 0, {});
            emit closed(id);
            process->deleteLater();
        }
    });
    // Device lifetime connections are installed once, even across browser restarts.
    const auto wiredKey = "desktopBrowserWired";
    if (!device->property(wiredKey).toBool()) {
        device->setProperty(wiredKey, true);
        connect(device, &WebDevice::urlChanged, this, [this, device, id] {
            if (running(id)) send(id, {}, {{"action", "navigate"}, {"url", device->url()}});
        });
        connect(device, &Device::statusChanged, this, [this, device, id] { if (!device->isRunning()) close(id); });
        connect(device, &Device::dataClearing, this, [this, device, id] {
            device->setProperty("reopenDesktopAfterClear", running(id));
            close(id);
        });
        connect(device, &Device::dataCleared, this, [this, device] {
            if (device->property("reopenDesktopAfterClear").toBool()) {
                device->setProperty("reopenDesktopAfterClear", false);
                open(device, false);
            }
        });
        connect(device, &QObject::destroyed, this, [this, id] { close(id); });
    }
    const QRect area = QGuiApplication::primaryScreen() ? QGuiApplication::primaryScreen()->availableGeometry() : QRect(0, 0, 1200, 800);
    const int width = qMax(320, qMin(1440, area.width() - 32));
    const int height = qMax(240, qMin(986, area.height() - 64));
    const QJsonObject config{{"binary", m_binary}, {"storage", device->persistentStoragePath() + "/chromium"},
        {"id", id}, {"url", device->url()}, {"width", width}, {"height", height},
        {"x", area.x() + (area.width() - width) / 2}, {"y", area.y() + (area.height() - height) / 2},
        {"headless", QGuiApplication::platformName() == "offscreen"}, {"script", QString::fromUtf8(script.readAll())}};
    process->start(python, {"-u", "-c", QString::fromUtf8(bridge.readAll())});
    process->write(QJsonDocument(config).toJson(QJsonDocument::Compact) + '\n');
    emit opened(id);
}
void DesktopBrowsers::close(const QString& id) {
    const auto process = m_browsers.value(id).process;
    if (!process) return;
    send(id, {}, {{"action", "close"}});
    process->closeWriteChannel();
    if (!process->waitForFinished(3000)) { process->terminate(); if (!process->waitForFinished(1000)) process->kill(); }
}
void DesktopBrowsers::focusForLogin(const QString& id) { send(id, "__login_focus__" + id, {{"action", "focus"}}); }
void DesktopBrowsers::reload(const QString& id) { send(id, {}, {{"action", "reload"}}); }
void DesktopBrowsers::read(const QString& id) {
    auto it = m_browsers.find(id);
    if (it == m_browsers.end() || !it->process) return;
    it->buffer += it->process->readAllStandardOutput();
    while (it != m_browsers.end() && it->buffer.contains('\n')) {
        const int end = it->buffer.indexOf('\n');
        const auto message = QJsonDocument::fromJson(it->buffer.left(end)).object();
        it->buffer.remove(0, end + 1);
        const auto event = message.value("event").toString();
        if (event == "state") {
            it->state = message;
            if (it->device) it->device->rememberUrl(message.value("mainUrl").toString());
        } else if (event == "console") {
            emit console(id, message.value("level").toInt(), message.value("message").toString(),
                         message.value("line").toInt(), message.value("source").toString());
        } else if (event == "failed") {
            emit console(id, 2, message.value("error").toString(), 0, {});
        } else if (message.contains("token")) {
            const auto token = message.value("token").toString();
            it->pending.removeAll(token);
            if (token.startsWith("__login_focus__")) emit loginFocused(id);
            else if (!token.isEmpty()) emit finished(token, message.value("reply").toObject());
        }
        it = m_browsers.find(id);
    }
}
}
