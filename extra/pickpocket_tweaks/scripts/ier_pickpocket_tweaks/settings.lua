---@omw-context menu
local I = require 'openmw.interfaces'

local D = require('scripts.ier_pickpocket_tweaks.config.defaults')

I.Settings.registerPage {
    key = D.PageKey,
    l10n = D.L10N,
    name = 'PageName',
    description = 'PageDesc',
}
