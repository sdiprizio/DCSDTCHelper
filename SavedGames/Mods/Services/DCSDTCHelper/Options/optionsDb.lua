local DbOption = require("Options.DbOption")

return {
    shortcutLeftCtrl = DbOption.new():setValue(true):checkbox(),
    shortcutRightCtrl = DbOption.new():setValue(false):checkbox(),
    shortcutLeftShift = DbOption.new():setValue(true):checkbox(),
    shortcutRightShift = DbOption.new():setValue(false):checkbox(),
    shortcutLeftAlt = DbOption.new():setValue(false):checkbox(),
    shortcutRightAlt = DbOption.new():setValue(false):checkbox(),
    shortcutKey = DbOption.new():setValue("V"):editbox(),
}
