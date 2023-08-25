
QBCore = QBCore or exports['qb-core']:GetCoreObject()

local function CreateDrugProduct(drugName, itemName, data)
    local methods = data.methods or {}
    local effects = data.effects
    local fallbackInfo = data.fallbackInfo
    local drugName = drugName
    QBCore.Functions.CreateUseableItem(itemName, function(source, item)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player.Functions.GetItemByName(item.name) then return TriggerClientEvent('QBCore:Notify', src, 'You do not have this item', 'error') end
        local slot = item.slot
        local info = item.info or item.metadata or fallbackInfo
        local updateMeta = false
        if not info.purity then
            info.purity = fallbackInfo.purity or 0.0
            updateMeta = true
        end
        if not info.drugName then
            info.drugName = drugName
            updateMeta = true
        end
        if updateMeta then
            if Player.Functions.RemoveItem(itemName, 1, slot) then
                Player.Functions.AddItem(itemName, 1, slot, info)
            else
                return TriggerClientEvent('QBCore:Notify', src, 'You do not have this item', 'error')
            end
        end
        local hasMethodItem = false
        local hasAdditionalRequiredItems = true
        local selectedMethod = 'Eat'
        local requiredItems = {}
        -- for method, _ in pairs(methods) do
        --     local methodItems = Config.Methods[method] or false
        --     hasMethodItem = not methodItems and true or false
        --     local additionalRequiredItems = Config.AdditionalRequirements and Config.AdditionalRequirements[method] or {}
        --     for itemName, _ in pairs(methodItems or {}) do
        --         if Player.Functions.GetItemByName(itemName) then
        --             hasMethodItem = true
        --             selectedMethod = method
        --             requiredItems[#requiredItems + 1] = itemName
        --             break
        --         end
        --     end
        --     if not hasMethodItem then return TriggerClientEvent('QBCore:Notify', src, 'You do not have the required items to use this drug', 'error') end

        --     for itemName, _ in pairs(additionalRequiredItems) do
        --         if not Player.Functions.GetItemByName(itemName) then
        --             hasAdditionalRequiredItems = false
        --         else
        --             requiredItems[#requiredItems + 1] = itemName
        --         end
        --     end
        --     if not hasAdditionalRequiredItems then return TriggerClientEvent('QBCore:Notify', src, 'You do not have the required items to use this drug', 'error') end
        -- end

        local chanceOfBreaking = methods[selectedMethod] and methods[selectedMethod].chanceOfBreaking
        if chanceOfBreaking then
            local chance = math.random(1,100)/100
            if chance < chanceOfBreaking then
                local itemData = QBCore.Shared.Items[itemToBreak]
                local itemToBreak = requiredItems[math.random(1, #requiredItems)]
                Player.Functions.RemoveItem(itemToBreak, 1) -- I dont really care if this fails
                return TriggerClientEvent('QBCore:Notify', src, 'You broke your '..itemData.label, 'error')
            end
        end
        local qty = methods[selectedMethod] and methods[selectedMethod].consumeQty or 1
        if not Player.Functions.RemoveItem(itemName, qty, slot) then
            local formatedError = string.format('You need %s %s to %s this drug', qty, itemName, selectedMethod)
            return TriggerClientEvent('QBCore:Notify', src, formatedError , 'error')
        end
        TriggerClientEvent('pandadrugs:client:UseDrug', src, drugName, selectedMethod, itemName, effects, info)
    end)
end

local function CreateDrugProducts()
    for drugName, details in pairs(Config.Drugs) do
        local products = details.DrugProducts or {}
        for itemName, data in pairs(products) do
            CreateDrugProduct(drugName, itemName, data)
        end
    end
end

-- local function CreateMethodItems()
--     for method, items in pairs(Config.MethodRequirements or {}) do
--         for itemName, useableData in pairs(items or {}) do
--             QBCore.Functions.CreateUseableItem(itemName, function(source, item)
--                 local src = source
--                 local Player = QBCore.Functions.GetPlayer(src)
--                 if not Player.Functions.GetItemByName(item.name) then return end
--                 TriggerClientEvent('pandadrugs:client:PerformMethod', src, method, useableData)
--             end)
--         end
--     end
-- end

QBCore.Functions.CreateCallback('pandadrugs:cb:TestDrug', function(source, cb, drug)
    local info = drug.info or drug.metadata
    local drugName = info.drugName
    local testTable = Config.Drugs[drugName] and Config.Drugs[drugName].Testing or {}
    local processingTime = testTable.processingTime or 10000
    local failChance = testTable.failChance or 0.5
    -- local removalAmount = testTable.removalAmount or 1
    -- local player = QBCore.Functions.GetPlayer(source)
    -- if not player.Functions.RemoveItem(drug.name, removalAmount, drug.slot ) then
    --     return TriggerClientEvent('QBCore:Notify', source, 'You do not have this item', 'error')
    -- end
    local didIFailed = math.random(1,100)/100 < failChance
    Citizen.SetTimeout(processingTime, function()
        cb(didIFailed)
    end)
end)


CreateThread(function()
    CreateDrugProducts()
end)