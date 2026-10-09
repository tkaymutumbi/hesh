#pragma once
#include <QObject>
#include <QLocalSocket>
#include <QVariant>

namespace Hesh {
// Answers one question about a grabbed frame: is it solid black? A web surface
// that Chromium stopped repainting shows up this way, and QML cannot read
// pixels itself.
class SurfaceProbe final : public QObject {
    Q_OBJECT
public:
    explicit SurfaceProbe(QObject* parent = nullptr);
    Q_INVOKABLE bool isBlack(const QVariant& image) const;
signals:
    // The compositor changed what is on screen (workspace or monitor switch).
    // Qt gets no visibility event for that, so web surfaces need this nudge.
    void desktopChanged();
private:
    QLocalSocket m_events;
    QByteArray m_buffer;
};
}
