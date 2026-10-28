---@omw-context menu
local I = require 'openmw.interfaces'

local D = require('scripts.ier_party_barter.config.defaults')

I.Settings.registerPage {
    key = D.PageKey,
    l10n = D.L10N,
    name = 'PageName',
    description = 'PageDesc',
}

I.Settings.registerGroup {
    key = D.Section,
    page = D.PageKey,
    l10n = D.L10N,
    name = 'SettingsName',
    description = 'SettingsDesc',
    order = 1,
    permanentStorage = true,
    settings = {
        {
            key = 'b_EnablePartyBarter',
            renderer = 'checkbox',
            name = 'EnableName',
            description = 'EnableDesc',
            default = true,
        },
        {
            key = 'b_OfferNonNpcFollowers',
            renderer = 'checkbox',
            name = 'OfferNonNpcFollowersName',
            description = 'OfferNonNpcFollowersDesc',
            default = false,
        },
    },
}
