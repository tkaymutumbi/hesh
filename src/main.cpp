#include <QGuiApplication>
#include <QDebug>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QUrl>

#include <cstdio>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QLocalServer>
#include <QLocalSocket>
#include <QLockFile>
#include <QStandardPaths>
#include <QTimer>
#include <QUuid>
#include "automation/Automation.hpp"
#include "android/AndroidDevice.hpp"

static QString controlSocketPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
        + QStringLiteral("/hesh-control");
}

static int sendControl(const QJsonObject& request)
{
    QLocalSocket socket;
    socket.connectToServer(controlSocketPath());
    if (!socket.waitForConnected(1500)) {
        std::puts("{\"ok\":false,\"error\":\"Hesh backend is not running\"}");
        return 1;
    }
    socket.write(QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n');
    socket.waitForBytesWritten(1500);
    QByteArray reply;
    while (!reply.contains('\n') && socket.waitForReadyRead(15000)) reply += socket.readAll();
    if (reply.isEmpty()) {
        std::puts("{\"ok\":false,\"error\":\"Hesh backend did not respond\"}");
        return 1;
    }
    std::fwrite(reply.constData(), 1, reply.size(), stdout);
    return QJsonDocument::fromJson(reply).object().value("ok").toBool() ? 0 : 1;
}


#include <QtWebEngineCore/qtwebenginecoreglobal.h>
#include <QtWebEngineQuick/QtWebEngineQuick>

#include "app/Application.hpp"
#include "app/Preferences.hpp"
#include "devices/Device.hpp"
#include "web/BrowserProfiles.hpp"
#include "web/WebDevice.hpp"

int main(int argc, char* argv[])
{
    // Control clients never initialize Chromium or create a window.
    if (argc >= 3 && QString::fromLocal8Bit(argv[1]) == QStringLiteral("--control")) {
        QCoreApplication client(argc, argv);
        QJsonParseError error;
        const auto doc = QJsonDocument::fromJson(QByteArray(argv[2]), &error);
        if (error.error != QJsonParseError::NoError || !doc.isObject()) {
            std::puts("{\"ok\":false,\"error\":\"Expected a JSON command object\"}");
            return 2;
        }
        return sendControl(doc.object());
    }
    // Set the identity first: QSettings resolves the preference file from these
    // names, and the stored Chromium flags have to be read before WebEngine
    // starts.
    QCoreApplication::setApplicationName(QStringLiteral("Hesh"));
    QCoreApplication::setOrganizationName(QStringLiteral("Hesh"));
    QCoreApplication::setApplicationVersion(QStringLiteral(HESH_VERSION));

    // Do NOT force dark mode on web content.  `--force-dark-mode` makes
    // Chromium recolor light pages and also desaturates already-dark pages
    // (e.g. lime #A3FF12 → muted olive) which breaks color fidelity per
    // profile. DevTools dark appearance is handled via JS in
    // DeviceFrame.qml:applyDevToolsDarkTheme(), and WebUI dark is opt-in
    // via WebEngineView background. Preserve user-supplied flags and add only
    // the background-rendering guards required by persistent device surfaces.
    // Chromium can otherwise treat a covered Wayland window like a background
    // tab and stop producing frames after a workspace switch.
    //
    // Order matters: stored flags first, then the environment, then the guards.
    // Chromium keeps the last value for a repeated switch, so an env var set for
    // one launch outranks the stored preference, and the guards always apply.
    QStringList chromiumFlags;
    const auto appendFlags = [&chromiumFlags](const QString& flags) {
        for (const auto& flag : flags.split(QLatin1Char(' '), Qt::SkipEmptyParts)) {
            if (!chromiumFlags.contains(flag)) {
                chromiumFlags.append(flag);
            }
        }
    };
    appendFlags(Hesh::storedExtraChromiumFlags());
    appendFlags(QString::fromLocal8Bit(qgetenv("QTWEBENGINE_CHROMIUM_FLAGS")));
    for (const auto* flag : {"--disable-background-timer-throttling",
                             "--disable-backgrounding-occluded-windows",
                             "--disable-renderer-backgrounding"}) {
        appendFlags(QLatin1String(flag));
    }
    qputenv("QTWEBENGINE_CHROMIUM_FLAGS", chromiumFlags.join(QLatin1Char(' ')).toLocal8Bit());
    // HiDPI: use PassThrough for fractional scales (e.g. 1.25/1.5 on Hyprland)
    // so WebEngine renders at native physical resolution instead of rounded.
    QGuiApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);
    QtWebEngineQuick::initialize();

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationDisplayName(QStringLiteral("Hesh"));
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/qt/qml/Hesh/assets/icons/hesh.png")));

    QLockFile instanceLock(controlSocketPath() + QStringLiteral(".lock"));
    instanceLock.setStaleLockTime(0);
    const bool background = app.arguments().contains(QStringLiteral("--background"));
    if (!instanceLock.tryLock(0)) {
        return sendControl({{"action", background ? "background" : "show"}});
    }
    // Only the lock owner can clean up a socket left by a previous crash.
    QLocalServer::removeServer(controlSocketPath());
    app.setQuitOnLastWindowClosed(false);

    qmlRegisterUncreatableType<Hesh::Device>("Hesh", 1, 0, "Device",
                                              QStringLiteral("Devices are created by DeviceManager"));
    qmlRegisterUncreatableType<Hesh::WebDevice>("Hesh", 1, 0, "WebDevice",
                                                 QStringLiteral("Web devices are created by DeviceManager"));

    Hesh::Application hesh;
    // Process-level facts for the diagnostics rows: main.cpp owns both.
    hesh.preferences()->setRuntimeFacts(
        Hesh::highDpiRoundingPolicyName(), QString::fromLatin1(qWebEngineChromiumVersion()));
    // Preferences are read from unrelated corners of the tree, so they are a
    // singleton rather than another context property.
    qmlRegisterSingletonInstance("Hesh", 1, 0, "Preferences", hesh.preferences());

    Hesh::BrowserProfiles browserProfiles;
    qmlRegisterSingletonInstance("Hesh", 1, 0, "BrowserProfiles", &browserProfiles);

    Hesh::Automation automation;
    qmlRegisterSingletonInstance("Hesh", 1, 0, "Automation", &automation);
    automation.setNameResolver([&hesh](const QString& id) {
        auto* model = static_cast<Hesh::DeviceListModel*>(hesh.deviceManager()->devices());
        for (int row = 0; row < model->rowCount(); ++row)
            if (model->at(row)->id() == id) return model->at(row)->name();
        return QString();
    });

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("deviceManager"), hesh.deviceManager());
    engine.rootContext()->setContextProperty(QStringLiteral("backgroundLaunch"), background);

    QObject::connect(&engine,
                     &QQmlApplicationEngine::warnings,
                     &app,
                     [](const QList<QQmlError>& errors) {
                         for (const auto& error : errors) {
                             qWarning() << error;
                         }
                     });

    QObject::connect(&engine,
                     &QQmlApplicationEngine::objectCreationFailed,
                     &app,
                     [&engine] {
                         std::fprintf(stderr, "Hesh QML object creation failed.\n");
                         std::fflush(stderr);
                         qWarning() << "Hesh QML object creation failed.";
                         QCoreApplication::exit(EXIT_FAILURE);
                     },
                     Qt::QueuedConnection);
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/Hesh/qml/Main.qml")));

    if (engine.rootObjects().isEmpty()) {
        std::fprintf(stderr, "Hesh could not load its QML module.\n");
        std::fflush(stderr);
        QQmlComponent diagnostic(&engine,
                                 QUrl(QStringLiteral("qrc:/qt/qml/Hesh/qml/Main.qml")),
                                 &app);
        for (const auto& error : diagnostic.errors()) {
            qWarning() << error;
            std::fprintf(stderr, "%s\n", qPrintable(error.toString()));
        }
        qWarning() << "Hesh could not load its QML module.";
        return EXIT_FAILURE;
    }

    QLocalServer controlServer;
    controlServer.setSocketOptions(QLocalServer::UserAccessOption);
    QObject::connect(&controlServer, &QLocalServer::newConnection, &app, [&] {
        while (auto* socket = controlServer.nextPendingConnection()) {
            socket->setParent(&controlServer);
            socket->setReadBufferSize(1024 * 1024 + 1);
            QObject::connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
            auto process = [&, socket] {
                if (!socket->canReadLine()) return;
                if (socket->property("processed").toBool()) return;
                socket->setProperty("processed", true);
                if (socket->bytesAvailable() > 1024 * 1024) {
                    socket->write("{\"ok\":false,\"error\":\"Command exceeds 1 MiB\"}\n");
                    socket->disconnectFromServer();
                    return;
                }
                QJsonParseError parseError;
                const auto doc = QJsonDocument::fromJson(socket->readLine(), &parseError);
                if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
                    socket->write("{\"ok\":false,\"error\":\"Expected a JSON command object\"}\n");
                    socket->disconnectFromServer();
                    return;
                }
                const auto request = doc.object();
                const auto action = request.value("action").toString();
                const auto id = request.value("id").toString();
                QJsonObject reply{{"ok", true}};
                auto* manager = hesh.deviceManager();
                auto* model = static_cast<Hesh::DeviceListModel*>(manager->devices());
                Hesh::Device* device = nullptr;
                for (int row = 0; row < model->rowCount(); ++row)
                    if (model->at(row)->id() == id) device = model->at(row);
                auto* root = engine.rootObjects().constFirst();
                const bool agent = request.value("agent").toBool();
                const bool automationAction = action == "inspect" || action == "interact"
                    || action.startsWith("memory_") || action.startsWith("credential_");
                if (action.startsWith("agent_")) {
                    reply = automation.session(action.mid(6), request, agent);
                    socket->write(QJsonDocument(reply).toJson(QJsonDocument::Compact) + '\n');
                    socket->disconnectFromServer();
                    return;
                }
                if (agent && automation.paused()) {
                    socket->write("{\"ok\":false,\"error\":\"AI control is paused in Hesh\"}\n");
                    socket->disconnectFromServer();
                    return;
                }
                if (automationAction) {
                    const auto token = QUuid::createUuid().toString(QUuid::WithoutBraces);
                    QObject::connect(&automation, &Hesh::Automation::finished, socket,
                        [socket, token](const QString& completed, const QJsonObject& response) {
                        if (completed != token || socket->state() != QLocalSocket::ConnectedState) return;
                        socket->write(QJsonDocument(response).toJson(QJsonDocument::Compact) + '\n');
                        socket->disconnectFromServer();
                    });
                    automation.execute(token, request);
                    return;
                }
                if (agent) automation.noteActivity(id, request.value("client").toString("AI"), action);
                if (action == "list") {
                    QJsonArray devices;
                    for (int row = 0; row < model->rowCount(); ++row) {
                        auto* d = model->at(row);
                        auto* web = qobject_cast<Hesh::WebDevice*>(d);
                        devices.append(QJsonObject{{"id", d->id()}, {"name", d->name()}, {"type", d->typeName()},
                            {"profile", d->profileName()}, {"status", d->statusName()},
                            {"url", web ? web->url() : QString()}, {"presentation", automation.presentation(d->id())}});
                    }
                    reply.insert("devices", devices);
                    reply.insert("profiles", QJsonArray::fromVariantList(manager->availableProfiles()));
                } else if (action == "show" || action == "background" || action == "logins") {
                    QMetaObject::invokeMethod(root, action == "show" ? "showMainWindow" : action == "logins" ? "showLogins" : "enableBackground");
                } else if (action == "create" && request.value("type").toString() == "android") {
                    const auto name = request.value("name").toString().trimmed();
                    if (name.isEmpty()) reply = {{"ok", false}, {"error", "Enter a name"}};
                    else {
                        const auto flavor = request.value("flavor").toString("google");
                        const auto serial = request.value("serial").toString();
                        if (flavor == "phone" && serial.isEmpty()) reply = {{"ok", false}, {"error", "Choose a connected phone serial"}};
                        else reply.insert("id", manager->createAndroidDevice(name, request.value("profile").toString("Pixel 7"), flavor, serial)->id());
                    }
                } else if (action == "create") {
                    const auto name = request.value("name").toString().trimmed();
                    const auto url = request.value("url").toString().trimmed();
                    const auto profile = request.value("profile").toString("Pixel 7");
                    bool validProfile = false;
                    for (const auto& p : Hesh::DeviceProfile::catalog())
                        if (p.name == profile) validProfile = true;
                    const QUrl address(url);
                    if (name.isEmpty() || !validProfile || !address.isValid()
                        || (address.scheme() != "http" && address.scheme() != "https")) {
                        reply = {{"ok", false}, {"error", "Enter a name, valid profile and http(s) URL"}};
                    } else {
                        auto* created = manager->createWebDevice(name, profile, url);
                        reply.insert("id", created->id());
                    }
                } else if (!device) {
                    reply = {{"ok", false}, {"error", "Device not found"}};
                } else if (action == "android_info") {
                    auto* android = qobject_cast<Hesh::AndroidDevice*>(device);
                    if (!android) reply = {{"ok", false}, {"error", "Not an Android device"}};
                    else reply.insert("serial", android->serial()), reply.insert("status", android->statusName());
                } else if (action == "context") {
                    reply.insert("context", automation.deviceContext(device, automation.presentation(id)));
                    reply.insert("prompt", automation.agentPrompt(device, automation.presentation(id)));
                } else if (action == "start") {
                    manager->startDevice(id);
                } else if (action == "stop") {
                    manager->stopDevice(id);
                } else if (action == "preview") {
                    manager->startDevice(id);
                    QMetaObject::invokeMethod(root, "previewDevice", Q_ARG(QVariant, id));
                } else if (action == "reload") {
                    QMetaObject::invokeMethod(root, "reloadDevice", Q_ARG(QVariant, id));
                } else if (action == "rename") {
                    const auto name = request.value("name").toString().trimmed();
                    if (name.isEmpty()) reply = {{"ok", false}, {"error", "Enter a device name"}};
                    else device->setName(name);
                } else if (action == "clear") {
                    manager->clearDeviceData(id);
                } else if (action == "delete") {
                    QMetaObject::invokeMethod(root, "removeDeviceById", Q_ARG(QVariant, id));
                } else if (action == "url") {
                    auto* web = qobject_cast<Hesh::WebDevice*>(device);
                    const QUrl url(request.value("url").toString());
                    if (!web || !url.isValid() || (url.scheme() != "http" && url.scheme() != "https"))
                        reply = {{"ok", false}, {"error", "Enter an http(s) URL"}};
                    else web->setUrl(url.toString());
                } else {
                    reply = {{"ok", false}, {"error", "Unknown action"}};
                }
                socket->write(QJsonDocument(reply).toJson(QJsonDocument::Compact) + '\n');
                socket->disconnectFromServer();
            };
            QObject::connect(socket, &QLocalSocket::readyRead, &app, process);
            QTimer::singleShot(15000, socket, [socket] { socket->disconnectFromServer(); });
            process();
        }
    });
    if (!controlServer.listen(controlSocketPath())) {
        qWarning() << "Hesh control socket:" << controlServer.errorString();
        return EXIT_FAILURE;
    }
    return app.exec();
}
