---@omw-context all
local async = require('openmw.async')
local storage = require('openmw.storage')
local D = require('scripts.InventoryExtenderRedone.config.defaults')

local section = storage.globalSection(D.Section.Debug)

-- cached integer threshold; re-read on every storage change so the setting applies live,
-- including to printers already handed out by get()
local threshold = section:asTable().n_LogLevel or D.LogLevelDefault
section:subscribe(async:callback(function()
    threshold = section:asTable().n_LogLevel or D.LogLevelDefault
end))

-- method name -> rank + the single-letter mark printed in the "<X>" prefix. a statement prints
-- when its rank <= threshold (error is least verbose, debug most). lowercase keys are the
-- public method names.
local LEVELS = {
    error = { rank = D.LogLevels.Error,   mark = 'E' },
    warn  = { rank = D.LogLevels.Warning, mark = 'W' },
    info  = { rank = D.LogLevels.Info,    mark = 'I' },
    debug = { rank = D.LogLevels.Debug,   mark = 'D' },
}

-- emit one statement: prefix "<level> [tag] " into the first argument, forward the rest
-- exactly like print
---@param tag string? when set, prefixes "[tag] " to the first argument
---@param mark string the level letter printed as "<X>"
---@param level integer rank of this call
---@param first string|any the message
---@param ... any forwarded to print
local function emit(tag, mark, level, first, ...)
    if level > threshold then
        return
    end
    if tag then
        print(string.format('<%s> [%s] %s', mark, tag, tostring(first)), ...)
    else
        print(string.format('<%s> %s', mark, tostring(first)), ...)
    end
end

-- bind the four level methods, optionally carrying a tag
---@param tag string?
local function bindLevels(target, tag)
    for name, spec in pairs(LEVELS) do
        target[name] = function(...)
            emit(tag, spec.mark, spec.rank, ...)
        end
    end
end

---@class InventoryExtenderRedone.Logger : InventoryExtenderRedone.Printer
---@field get fun(tag:string):InventoryExtenderRedone.Printer
local M = {}

-- bare level methods (no tag)
bindLevels(M, nil)

---@param tag string the label prefixed to every statement this printer emits
---@return InventoryExtenderRedone.Printer a printer with .error/.warn/.info/.debug methods
function M.get(tag)
    local printer = {}
    bindLevels(printer, tag)
    return printer
end

return M --[[@as InventoryExtenderRedone.Logger]]
