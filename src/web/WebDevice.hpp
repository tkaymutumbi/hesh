#pragma once

#include "devices/Device.hpp"

namespace Hesh {

class WebDevice final : public Device
{
    Q_OBJECT
    Q_PROPERTY(QString url READ url WRITE setUrl NOTIFY urlChanged)
    Q_PROPERTY(QString persistentStoragePath READ persistentStoragePath CONSTANT)
    Q_PROPERTY(QString cachePath READ cachePath CONSTANT)

public:
    WebDevice(QString id,
              QString name,
              DeviceProfile profile,
              QString url,
              QObject* parent = nullptr);

    QString url() const;
    void setUrl(const QString& url);

    // Browser storage directories that belong to this device, derived from the
    // device id. Presentation hosts bind their WebEngineProfile to them.
    QString persistentStoragePath() const;
    QString cachePath() const;

    void start() override;
    void stop() override;

protected:
    void clearPersistentData() override;

signals:
    void urlChanged();

private:
    QString m_url;
};

} // namespace Hesh
