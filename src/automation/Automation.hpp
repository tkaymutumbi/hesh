#pragma once
#include <QObject>
#include <QPointer>
#include <QHash>
#include <QJsonObject>
#include <QSet>
#include <QTimer>
#include <functional>

namespace Hesh {
class Device;
class Automation final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString activeDevice READ activeDevice NOTIFY activityChanged)
    Q_PROPERTY(QString activity READ activity NOTIFY activityChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY activityChanged)
    Q_PROPERTY(bool sessionActive READ sessionActive NOTIFY activityChanged)
public:
    explicit Automation(QObject* parent = nullptr);
    ~Automation() override;
    void setNameResolver(std::function<QString(const QString&)> resolver) { m_nameOf = std::move(resolver); }
    bool sessionActive() const { return m_session; }
    // Agent session lifecycle: start, done, pause, resume, status. The overlay
    // shown by the shell plugin follows this state through the status file.
    QJsonObject session(const QString& op, const QJsonObject& request, bool fromAgent);
    QString activeDevice() const { return m_activeDevice; }
    QString activity() const { return m_activity; }
    bool paused() const { return m_paused; }
    void setPaused(bool paused);
    Q_INVOKABLE void registerSurface(const QString& id, QObject* surface);
    Q_INVOKABLE void unregisterSurface(const QString& id, QObject* surface);
    Q_INVOKABLE void complete(const QString& token, const QString& result);
    Q_INVOKABLE void request(const QString& token, const QVariantMap& command);
    Q_INVOKABLE QVariantList accounts() const;
    Q_INVOKABLE void copyAgentPrompt(QObject* device, bool standalone);
    Q_INVOKABLE void copyDeviceId(const QString& id);
    Q_INVOKABLE void openLogins(const QString& id);
    QString presentation(const QString& id) const;
    QJsonObject deviceContext(Device* device, const QString& host) const;
    QString agentPrompt(Device* device, const QString& host) const;
    void noteActivity(const QString& id, const QString& client, const QString& action);
    void execute(const QString& token, const QJsonObject& command);
signals:
    void finished(const QString& token, const QJsonObject& reply);
    void activityChanged();
    void loginsRequested(const QString& id);
private:
    void finish(const QString& token, const QJsonObject& reply);
    void runPage(const QString& token, const QJsonObject& command);
    void vault(const QString& token, const QJsonObject& command);
    bool saveState();
    void publish();
    void armSession(bool implicitStart);
    void endSession();
    QHash<QString, QPointer<QObject>> m_surfaces;
    QHash<QString, QString> m_pending;
    QSet<QString> m_busyDevices;
    QJsonObject m_state;
    QString m_path, m_script, m_activeDevice, m_activity;
    QString m_client, m_task, m_lastDevice;
    std::function<QString(const QString&)> m_nameOf;
    QString m_statusPath;
    bool m_paused = false, m_pausedByUser = false, m_session = false;
    QTimer m_sessionTimer;
    QTimer m_activityTimer;
};
}
