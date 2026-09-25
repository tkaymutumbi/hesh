#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>

class QQuickWebEngineProfile;

namespace Hesh {

class WebDevice;

// Owns exactly one WebEngine profile per web device.
//
// Chromium refuses a second live profile on the same storage path, and it
// tears profiles down asynchronously. When every DeviceFrame built its own
// profile, moving a device between the workspace and a standalone window
// could leave the new frame locked out by the old one indefinitely. Frames
// now borrow the device's single long-lived profile instead.
class BrowserProfiles final : public QObject
{
    Q_OBJECT

public:
    explicit BrowserProfiles(QObject* parent = nullptr);

    // Returns the device's profile, creating it on first use. Null only when
    // Chromium refuses to create it.
    Q_INVOKABLE QQuickWebEngineProfile* profileFor(QObject* device);

private:
    void release(const QString& deviceId);

    QHash<QString, QPointer<QQuickWebEngineProfile>> m_profiles;
};

} // namespace Hesh
