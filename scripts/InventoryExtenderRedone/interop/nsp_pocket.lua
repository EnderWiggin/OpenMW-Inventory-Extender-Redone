---@omw-context player

local CELL_ID = 'nsp_pocketspace'

local M = {}

---@param container openmw.Object
---@return boolean
function M.isPocketSpaceContainer(container)
    if not container or not container:isValid() then return false end
    local cell = container.cell
    return cell ~= nil and cell.id == CELL_ID
end

return M
