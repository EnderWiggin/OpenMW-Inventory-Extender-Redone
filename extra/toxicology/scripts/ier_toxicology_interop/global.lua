---@omw-context global

local function updateInventory(data)
    local player = data and data.actor
    if not player then return end
    player:sendEvent('IER_Update')
end

return {
    eventHandlers = {
        Toxicology_ConfirmApply = updateInventory,
        Toxicology_RefreshCharges = updateInventory,
    },
}
