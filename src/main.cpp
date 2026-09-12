#include <QGuiApplication>
#include <QDebug>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QUrl>

#include <cstdio>

#include <QtWebEngineCore/qtwebenginecoreglobal.h>
#include <QtWebEngineQuick/QtWebEngineQuick>

#include "app/Application.hpp"
#include "app/Preferences.hpp"
#include "devices/Device.hpp"
#include "web/WebDevice.hpp"

int main(int argc, char* argv[])
{
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

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("deviceManager"), hesh.deviceManager());

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

    return app.exec();
}
