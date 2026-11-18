#pragma once
#include <QObject>
#include <QHash>
#include <QJsonObject>
#include <QPointer>
#include <QTimer>

class QProcess;
namespace Hesh {
class WebDevice;
class DesktopBrowsers final : public QObject {
    Q_OBJECT
public:
    explicit DesktopBrowsers(QObject* parent = nullptr);
    ~DesktopBrowsers() override;
    Q_INVOKABLE bool usesNative(QObject* device) const;
    Q_INVOKABLE void open(QObject* device, bool focus = true);
    Q_INVOKABLE void close(const QString& id);
    Q_INVOKABLE void focusForLogin(const QString& id);
    bool running(const QString& id) const;
    QJsonObject context(const QString& id) const;
    void execute(const QString& id, const QString& token, const QJsonObject& command);
    Q_INVOKABLE void reload(const QString& id);
signals:
    void finished(const QString& token, const QJsonObject& reply);
    void opened(const QString& id);
    void closed(const QString& id);
    void loginFocused(const QString& id);
    void console(const QString& id, int level, const QString& message, int line, const QString& source);
private:
    struct Browser {
        QPointer<QProcess> process;
        QPointer<WebDevice> device;
        QByteArray buffer;
        QJsonObject state;
        QStringList pending;
    };
    void read(const QString& id);
    void send(const QString& id, const QString& token, const QJsonObject& command);
    QHash<QString, Browser> m_browsers;
    QString m_binary;
    QTimer m_poll;
};
}
