#include "AccentPalette.hpp"

#include <QVariantMap>

namespace Hesh {

const QList<AccentPreset>& accentPalette()
{
    // Indigo is the shipped application accent and the value the selected
    // device card and empty-state badge used to hardcode as #454a75.
    static const QList<AccentPreset> presets {
        {QStringLiteral("Indigo"), QColor(QStringLiteral("#a4a7ff")), QColor(QStringLiteral("#8589f0")),
         QColor(QStringLiteral("#292c4a")), QColor(QStringLiteral("#454a75"))},
        {QStringLiteral("Cyan"), QColor(QStringLiteral("#66d9e8")), QColor(QStringLiteral("#45bed0")),
         QColor(QStringLiteral("#1f3a41")), QColor(QStringLiteral("#33626c"))},
        {QStringLiteral("Green"), QColor(QStringLiteral("#66d6a3")), QColor(QStringLiteral("#4bbf8c")),
         QColor(QStringLiteral("#1e3a30")), QColor(QStringLiteral("#356b56"))},
        {QStringLiteral("Amber"), QColor(QStringLiteral("#efbd75")), QColor(QStringLiteral("#d9a457")),
         QColor(QStringLiteral("#3a2f1e")), QColor(QStringLiteral("#6b5734"))},
        {QStringLiteral("Rose"), QColor(QStringLiteral("#f291a5")), QColor(QStringLiteral("#d97287")),
         QColor(QStringLiteral("#3a2129")), QColor(QStringLiteral("#6b3644"))},
        {QStringLiteral("Violet"), QColor(QStringLiteral("#c9a6ff")), QColor(QStringLiteral("#ad83f0")),
         QColor(QStringLiteral("#332a4a")), QColor(QStringLiteral("#584273"))},
    };
    return presets;
}

const AccentPreset& accentPresetFor(const QString& name)
{
    const auto& presets = accentPalette();
    for (const auto& preset : presets) {
        if (preset.name.compare(name, Qt::CaseInsensitive) == 0) {
            return preset;
        }
    }
    return presets.constFirst();
}

bool isKnownAccent(const QString& name)
{
    const auto trimmed = name.trimmed();
    if (trimmed.isEmpty()) {
        return false;
    }
    for (const auto& preset : accentPalette()) {
        if (preset.name.compare(trimmed, Qt::CaseInsensitive) == 0) {
            return true;
        }
    }
    return false;
}

QVariantList accentPaletteForQml()
{
    QVariantList presets;
    for (const auto& preset : accentPalette()) {
        presets.append(QVariantMap {
            {QStringLiteral("name"), preset.name},
            {QStringLiteral("accent"), preset.accent.name()},
            {QStringLiteral("strong"), preset.strong.name()},
            {QStringLiteral("soft"), preset.soft.name()},
            {QStringLiteral("border"), preset.border.name()},
        });
    }
    return presets;
}

} // namespace Hesh
