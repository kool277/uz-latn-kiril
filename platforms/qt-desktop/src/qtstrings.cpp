// Strings of Qt's own widgets that this app shows: the context menus of the editors and line edits, scroll bar
// menus and message box buttons. Listing them here makes lupdate put them into the app's .ts files, so the Uzbek
// interface is complete although Qt ships no Uzbek translation (and the Russian one works without qtbase_ru.qm).
// The source texts are Qt's (contexts QWidgetTextControl, QLineEdit, QScrollBar, QMessageBox, QPlatformTheme).
#include <QtGlobal>

namespace {

[[maybe_unused]] const char *const qtStrings[] = {
    QT_TRANSLATE_NOOP("QWidgetTextControl", "&Undo"),
    QT_TRANSLATE_NOOP("QWidgetTextControl", "&Redo"),
    QT_TRANSLATE_NOOP("QWidgetTextControl", "Cu&t"),
    QT_TRANSLATE_NOOP("QWidgetTextControl", "&Copy"),
    QT_TRANSLATE_NOOP("QWidgetTextControl", "Copy &Link Location"),
    QT_TRANSLATE_NOOP("QWidgetTextControl", "&Paste"),
    QT_TRANSLATE_NOOP("QWidgetTextControl", "Delete"),
    QT_TRANSLATE_NOOP("QWidgetTextControl", "Select All"),
    QT_TRANSLATE_NOOP("QLineEdit", "&Undo"),
    QT_TRANSLATE_NOOP("QLineEdit", "&Redo"),
    QT_TRANSLATE_NOOP("QLineEdit", "Cu&t"),
    QT_TRANSLATE_NOOP("QLineEdit", "&Copy"),
    QT_TRANSLATE_NOOP("QLineEdit", "&Paste"),
    QT_TRANSLATE_NOOP("QLineEdit", "Delete"),
    QT_TRANSLATE_NOOP("QLineEdit", "Select All"),
    QT_TRANSLATE_NOOP("QScrollBar", "Scroll here"),
    QT_TRANSLATE_NOOP("QScrollBar", "Left edge"),
    QT_TRANSLATE_NOOP("QScrollBar", "Top"),
    QT_TRANSLATE_NOOP("QScrollBar", "Right edge"),
    QT_TRANSLATE_NOOP("QScrollBar", "Bottom"),
    QT_TRANSLATE_NOOP("QScrollBar", "Page left"),
    QT_TRANSLATE_NOOP("QScrollBar", "Page up"),
    QT_TRANSLATE_NOOP("QScrollBar", "Page right"),
    QT_TRANSLATE_NOOP("QScrollBar", "Page down"),
    QT_TRANSLATE_NOOP("QScrollBar", "Scroll left"),
    QT_TRANSLATE_NOOP("QScrollBar", "Scroll up"),
    QT_TRANSLATE_NOOP("QScrollBar", "Scroll right"),
    QT_TRANSLATE_NOOP("QScrollBar", "Scroll down"),
    QT_TRANSLATE_NOOP("QMessageBox", "About Qt"),
    QT_TRANSLATE_NOOP("QMessageBox", "Show Details..."),
    QT_TRANSLATE_NOOP("QMessageBox", "Hide Details..."),
    QT_TRANSLATE_NOOP("QPlatformTheme", "OK"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "Cancel"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "Close"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "&Yes"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "&No"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "Yes to &All"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "N&o to All"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "Save"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "Save All"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "Open"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "Apply"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "Discard"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "Reset"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "Restore Defaults"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "Retry"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "Ignore"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "Abort"),
    QT_TRANSLATE_NOOP("QPlatformTheme", "Help"),
};

} // namespace
