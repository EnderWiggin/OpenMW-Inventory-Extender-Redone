---@omw-context player

local I = require 'openmw.interfaces'

local D = require('scripts.ier_pickpocket_tweaks.config.defaults')

local IER = I.InventoryExtenderRedone
if not IER or not IER.Pickpocket then return end
