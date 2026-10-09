#include "SurfaceProbe.hpp"
#include <QImage>
#include <QDir>

namespace Hesh {
SurfaceProbe::SurfaceProbe(QObject* parent) : QObject(parent) {
    const QByteArray signature = qgetenv("HYPRLAND_INSTANCE_SIGNATURE");
    if (signature.isEmpty()) return;
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    connect(&m_events, &QLocalSocket::readyRead, this, [this] {
        m_buffer += m_events.readAll();
        bool changed = false;
        int newline;
        while ((newline = m_buffer.indexOf('\n')) >= 0) {
            const QByteArray line = m_buffer.left(newline);
            m_buffer.remove(0, newline + 1);
            if (line.startsWith("workspacev2>>") || line.startsWith("focusedmonv2>>")
                || line.startsWith("activespecial>>") || line.startsWith("monitoraddedv2>>"))
                changed = true;
        }
        if (changed) emit desktopChanged();
    });
    m_events.connectToServer(runtime + "/hypr/" + QString::fromLatin1(signature) + "/.socket2.sock");
}
bool SurfaceProbe::isBlack(const QVariant& image) const {
    const QImage frame = image.value<QImage>();
    if (frame.isNull()) return false;
    for (int y = 0; y < frame.height(); ++y)
        for (int x = 0; x < frame.width(); ++x) {
            const QRgb pixel = frame.pixel(x, y);
            if (qRed(pixel) > 4 || qGreen(pixel) > 4 || qBlue(pixel) > 4) return false;
        }
    return true;
}
}
