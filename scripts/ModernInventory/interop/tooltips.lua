local tooltipsData = {}

-- Tooltips Complete
local success, data = pcall(require, 'mwse.mods.Tooltips Complete.data')
if success and type(data) == 'table' then
    for typeTable, tableData in pairs(data) do
        for itemId, tooltipText in pairs(tableData) do
            tooltipsData[itemId] = tooltipText
        end
    end
end
return tooltipsData