---@omw-context global
local I = require('openmw.interfaces')
local D = require('scripts.InventoryExtenderRedone.config.defaults')

-- Debug section: kept separate from settings/global.lua so it can later hold more debug knobs.
-- The dropdown stores the integer rank itself (n_LogLevel) via numeric ids; labels come from
-- the l10n text keys. The logger reads the same n_LogLevel and compares integers at runtime.
I.Settings.registerGroup {
    key = D.Section.Debug,
    order = 7,
    page = D.PageKey,
    l10n = D.L10N,
    name = 'ConfigCategoryDebug',
    permanentStorage = true,
    settings = {
        {
            key = 'n_LogLevel',
            renderer = 'UIToolkit/Dropbox',
            name = 'ConfigLogLevel',
            description = 'ConfigLogLevelDesc',
            default = D.LogLevelDefault,
            argument = {
                l10n = D.L10N,
                items = {
                    { id = D.LogLevels.Error,   text = 'LogLevel_Error' },
                    { id = D.LogLevels.Warning, text = 'LogLevel_Warning' },
                    { id = D.LogLevels.Info,    text = 'LogLevel_Info' },
                    { id = D.LogLevels.Debug,   text = 'LogLevel_Debug' },
                },
            },
        },
    },
}
