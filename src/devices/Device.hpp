#pragma once

#include <QColor>
#include <QObject>
#include <QString>

#include "DeviceProfile.hpp"

namespace Hesh {

class Device : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString id READ id CONSTANT)
    Q_PROPERTY(QString name READ name WRITE setName NOTIFY nameChanged)
    Q_PROPERTY(QString type READ typeName CONSTANT)
    Q_PROPERTY(QString typeLabel READ typeLabel CONSTANT)
    Q_PROPERTY(QString status READ statusName NOTIFY statusChanged)
    Q_PROPERTY(QString profileName READ profileName NOTIFY profileChanged)
    Q_PROPERTY(int viewportWidth READ viewportWidth NOTIFY profileChanged)
    Q_PROPERTY(int viewportHeight READ viewportHeight NOTIFY profileChanged)
    Q_PROPERTY(double devicePixelRatio READ devicePixelRatio NOTIFY profileChanged)
    Q_PROPERTY(QString userAgent READ userAgent NOTIFY profileChanged)
    Q_PROPERTY(QString accentName READ accentName WRITE setAccentName NOTIFY accentChanged)
    Q_PROPERTY(bool hasAccent READ hasAccent NOTIFY accentChanged)
    Q_PROPERTY(QColor accent READ accent NOTIFY accentChanged)
    Q_PROPERTY(QColor accentStrong READ accentStrong NOTIFY accentChanged)
    Q_PROPERTY(QColor accentSoft READ accentSoft NOTIFY accentChanged)
    Q_PROPERTY(QColor accentBorder READ accentBorder NOTIFY accentChanged)

public:
    enum class Status {
        Stopped,
        Starting,
        Running,
        Paused,
        Error,
    };
    Q_ENUM(Status)

    Device(QString id,
           QString name,
           DeviceType type,
           DeviceProfile profile,
           QObject* parent = nullptr);
    ~Device() override;

    QString id() const;
    QString name() const;
    void setName(const QString& name);

    DeviceType deviceType() const;
    QString typeName() const;
    QString typeLabel() const;

    Status status() const;
    QString statusName() const;
    void setStatus(Status status);

    const DeviceProfile& profile() const;
    QString profileName() const;
    int viewportWidth() const;
    int viewportHeight() const;
    double devicePixelRatio() const;
    QString userAgent() const;
    void setProfile(const DeviceProfile& profile);

    // The accent this device is shown with. An empty name means the device
    // follows the application accent: the presentation layer resolves that
    // fallback, so the device model never reads application preferences. Names
    // outside the catalog are rejected back to "follow the app accent" rather
    // than leaving the device with no palette.
    QString accentName() const;
    void setAccentName(const QString& name);
    bool hasAccent() const;
    // Meaningful as a colour only while hasAccent() is true.
    QColor accent() const;
    QColor accentStrong() const;
    QColor accentSoft() const;
    QColor accentBorder() const;

    virtual void start();
    virtual void stop();

    // Wipes the device's persistent runtime data (for a web device: cookies,
    // local storage, IndexedDB, and caches). Presentation hosts release their
    // browser surface when dataClearing() is emitted, the data is removed on
    // the next event-loop turn, and hosts may restore the surface when
    // dataCleared() arrives.
    void clearData();

signals:
    void nameChanged();
    void statusChanged();
    void profileChanged();
    void accentChanged();
    void dataChanged();
    // Emitted before and after clearData() removes the persistent data.
    void dataClearing();
    void dataCleared();

protected:
    // Removes the data that clearData() targets. Subclasses that own storage
    // override this; the base device keeps nothing on disk.
    virtual void clearPersistentData();

private:
    QString m_id;
    QString m_name;
    DeviceType m_type;
    DeviceProfile m_profile;
    QString m_accentName;
    Status m_status = Status::Stopped;
};

} // namespace Hesh
