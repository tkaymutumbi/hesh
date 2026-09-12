#pragma once

#include <QColor>
#include <QList>
#include <QString>
#include <QVariantList>

namespace Hesh {

// One entry of the accent catalog: a base colour plus the shades the UI derives
// from it. A preset table is the only thing that keeps those shades coherent,
// which is why accents are chosen rather than picked freely.
struct AccentPreset
{
    QString name;
    QColor accent;
    QColor strong;
    QColor soft;
    QColor border;
};

// The shipped accent catalog, in display order. The first entry is the default
// application accent.
const QList<AccentPreset>& accentPalette();

// Falls back to the first entry for an unknown or empty name, so a stale or
// hand-edited value can never leave a surface without an accent. Callers that
// need "no accent at all" — a device that follows the application accent — test
// the name for emptiness before calling.
const AccentPreset& accentPresetFor(const QString& name);

// True when the name matches a catalog entry exactly enough to store it.
bool isKnownAccent(const QString& name);

// The catalog as QML reads it: name plus colour names, one map per preset.
QVariantList accentPaletteForQml();

} // namespace Hesh
