local async = require('openmw.async')
local storage = require('openmw.storage')

local keybinds = storage.playerSection('Settings/InventoryExtender/1_Keybinds')
local window = storage.playerSection('Settings/InventoryExtender/2_WindowOptions')
local tweaks = storage.playerSection('Settings/InventoryExtender/3_Tweaks')
local modIntegration = storage.playerSection('Settings/InventoryExtender/4_ModIntegration')
local misc = storage.playerSection('Settings/InventoryExtender/5_Misc')
local configPlayer = {}

local function updateConfig()
	configPlayer.keybinds = keybinds:asTable()
	configPlayer.window = window:asTable()
	configPlayer.tweaks = tweaks:asTable()
	configPlayer.modIntegration = modIntegration:asTable()
	configPlayer.misc = misc:asTable()
end

updateConfig()
keybinds:subscribe(async:callback(updateConfig))
window:subscribe(async:callback(updateConfig))
tweaks:subscribe(async:callback(updateConfig))
modIntegration:subscribe(async:callback(updateConfig))
misc:subscribe(async:callback(updateConfig))

return configPlayer