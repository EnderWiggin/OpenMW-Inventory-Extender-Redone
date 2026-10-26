---@omw-context global
local I = require('openmw.interfaces')
local D = require('scripts.InventoryExtenderRedone.config.defaults')

-- The dropdown stores the integer rank itself (n_LogLevel) as the item id; labels come from the
-- LogLevel_* l10n keys, and the logger compares that integer at runtime.
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
