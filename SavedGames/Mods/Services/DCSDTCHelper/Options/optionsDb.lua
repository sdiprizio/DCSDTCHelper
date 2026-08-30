local DbOption = require("Options.DbOption")

return {
    shortcutLeftCtrl = DbOption.new():setValue(true):checkbox(),
    shortcutRightCtrl = DbOption.new():setValue(false):checkbox(),
    shortcutLeftShift = DbOption.new():setValue(true):checkbox(),
    shortcutRightShift = DbOption.new():setValue(false):checkbox(),
    shortcutLeftAlt = DbOption.new():setValue(false):checkbox(),
    shortcutRightAlt = DbOption.new():setValue(false):checkbox(),
    shortcutKey = DbOption.new():setValue("V"):editbox(),
    coordinateListShortcutLeftCtrl = DbOption.new():setValue(true):checkbox(),
    coordinateListShortcutRightCtrl = DbOption.new():setValue(false):checkbox(),
    coordinateListShortcutLeftShift = DbOption.new():setValue(true):checkbox(),
    coordinateListShortcutRightShift = DbOption.new():setValue(false):checkbox(),
    coordinateListShortcutLeftAlt = DbOption.new():setValue(false):checkbox(),
    coordinateListShortcutRightAlt = DbOption.new():setValue(false):checkbox(),
    coordinateListShortcutKey = DbOption.new():setValue("C"):editbox(),
}
