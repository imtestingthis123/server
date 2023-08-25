QBCore = QBCore or exports['qb-core']:GetCoreObject()
Factory = {}
Factories = {}

function Factory.Get(id)
    return Factories[id]
end

function Factory.Set(id, key, data)
    local self = Factory.Get(id)
    if self == nil then return end
    Factories[id][key] = data
end

function Factory.GetFactories()
    return Factories
end

function Factory.GetConfigRecipies(id)
    local self = Factory.Get(id)
    if not Config.Drugs[self.drugName] then return end
    if not Config.Drugs[self.drugName].Factories then return end
    if not Config.Drugs[self.drugName].Factories[self.configId] then return end
    if not Config.Drugs[self.drugName].Factories[self.configId].recipes then return end
    return Config.Drugs[self.drugName].Factories[self.configId].recipes
end

function Factory.GetConfigRecipieData(id, recipe)
    local self = Factory.Get(id)
    local recipeList = Factory.GetConfigRecipies(id)
    if not recipeList then return end
    return Config.Drugs[self.drugName].Recipes[recipe]
end

function Factory.GetConfigFactory(drugName, configId)
    return Config.Drugs[drugName] and Config.Drugs[drugName].Factories[configId]
end

function Factory.GetConfigFactories(drugName)
    return Config.Drugs[drugName] and Config.Drugs[drugName].Factories
end

function Factory.GetConfigUpgrades(drugName)
    return Config.Drugs[drugName] and Config.Drugs[drugName].Upgrades
end

function Factory.GetConfigUpgrade(drugName, configId)
    local config = Factory.GetConfigUpgrades(drugName)
    return config[configId]
end

function Factory.GetByLabID(labID)
    local factories = nil
    for id, factory in pairs(Factories) do
        if factory.labID == labID then
            if not factories then factories = {} end
            factories[#factories + 1] = id
        end
    end
    return factories
end

function Factory.SetUpgradesBasedOnLab(labID)
    local factories = Factory.GetByLabID(labID)
    if not factories then return end
    for _, id in ipairs(factories) do
        local self = Factory.Get(id)
        if not self then return end
        local labID = self.labID
        if not labID then return end
        local lab = LabFunctions.GetLabCachedData(labID)
        if not lab then return end
        local upgrades = lab.upgrades
        if not upgrades then return end
        local configUpgrades = Factory.GetConfigUpgrades(self.drugName)
        if not configUpgrades then return end
        for upgrade, amount in pairs(upgrades) do
            self.upgrades[upgrade] = configUpgrades[upgrade][amount].amount
        end
        Factory.Set(id, "upgrades", self.upgrades)
    end

    Factory.UpdateClients(id)
end

function Factory.Create(labid, drugName, configId, bucket, players, oldId)
    local config = Factory.GetConfigFactory(drugName, configId)
    if not config then return end
    local self = Factory.Get(oldId) or {}
    id = oldId or CreateUniqueId(8, "Factory:")
    local model = config.prop
    local coords = config.coords
    local rotation = config.rotation
    local configUpgrades = Factory.GetConfigUpgrades(drugName)
    self.id = id
    self.labID = labid
    self.drugName = drugName
    self.configId = configId
    self.bucket = bucket or 0
    self.players = players
    self.decay = config.decay or 0
    self.recipes = config.recipes
    self.upgrades = {}
    self.CanUse = true
    for k, v in pairs(configUpgrades) do
        self.upgrades[k] = v[1].amount
    end
    Factories[id] = self
    Factory.SetUpgradesBasedOnLab(labid)
    return id
end

function Factory.UpdateClients(id)
    local self = Factory.Get(id)
    if not self then return end
    local players = self.players
    if type(players) == "table" then
        for _, playerSrc in ipairs(players) do
            TriggerClientEvent("pandadrug:cl:UpgradeFactory", playerSrc, self)
        end
        return
    end
    TriggerClientEvent("pandadrug:cl:UpgradeFactory", players, self)
end

function Factory.AddPlayer(id, playerSrc)
    local self = Factory.Get(id)
    if not self then return end
    local players = self.players
    if not players then
        self.players = playerSrc
    elseif type(players) == "table" then
        local found = false
        for _, src in ipairs(players) do
            found = src == playerSrc
        end
        if not found then
            self.players[#self.players + 1] = playerSrc
        end
    elseif type(players) == "number" then
        if players ~= playerSrc then
            self.players = { self.players, playerSrc }
        end
    end
    TriggerClientEvent("pandadrug:cl:CreateFactory", playerSrc, self)
end

function Factory.RemovePlayer(id, playerSrc)
    local self = Factory.Get(id)
    if not self then return end
    local players = self.players
    if type(players) == "table" then
        for i, src in ipairs(players) do
            if src == playerSrc then
                table.remove(players, i)
                break
            end
        end
    elseif type(players) == "number" then
        if players == playerSrc then
            self.players = nil
        end
    end
    TriggerClientEvent("pandadrug:cl:DestroyFactory", playerSrc, id)
end

function Factory.RemoveAllPlayers(id)
    local self = Factory.Get(id)
    if not self then return end
    local players = self.players
    if not players then return end
    if type(players) == "table" then
        for _, playerSrc in ipairs(players) do
            TriggerClientEvent("pandadrug:cl:DestroyFactory", playerSrc, id)
        end
        return
    end
    TriggerClientEvent("pandadrug:cl:DestroyFactory", players, id)
end

function Factory.Destroy(id)
    Factory.RemoveAllPlayers(id)
    Factories[id] = nil
end

function Factory.SetProductionSpeed(id, speed)
    local self = Factory.Get(id)
    if not self then return false end
    self.upgrades["Production Speed"] = speed
    Factory.UpdateClients(id)
    return true
end

function Factory.Use(src, id, recipe)
    local Player = QBCore.Functions.GetPlayer(src)
    if Player == nil then return end
    local factory = Factory.Get(id)
    if not factory then return end

    local recipes = Factory.GetConfigRecipieData(id, recipe)
    local cooldown = recipes.cooldown
    if not cooldown then return end
    if not factory.CanUse then
        if recipes.cooldownMsg then
            TriggerClientEvent("QBCore:Notify", src, recipes.cooldownMsg, "error")
        end
        return
    end
    local lab = LabFunctions.GetLabCachedData(factory.labID)
    local factoryUpgradeIndex = lab.upgrades["Production Purity"] or 1
    local configUpgrades = Factory.GetConfigUpgrades(factory.drugName)

    local removeItems = recipes.requiredItems
    local givesItems = recipes.givesItems

    local purity = configUpgrades and configUpgrades["Production Purity"] and configUpgrades["Production Purity"][factoryUpgradeIndex] and configUpgrades["Production Purity"][factoryUpgradeIndex].amount or 0.1
    assert(purity, "There has been a critical error in the factory script.")
    local purityVals = {
        min = purity,
        max = purity + 0.09
    }
    
    purity = math.random(purityVals.min*100, purityVals.max * 100) / 100
    local hasItems = true

    local items = {}
    for k, v in pairs(Player.PlayerData.items) do
        if not items[v.name] then
            items[v.name] = v.amount
        else
            items[v.name] = items[v.name] + v.amount
        end
    end
    local puritymin = 0.1
    for k, v in pairs(removeItems) do
        local item = k
        local amount = v

        if items[item] == nil or items[item] < amount then
            hasItems = false
        end
    end

    if not hasItems then TriggerClientEvent("QBCore:Notify", src, "You do not have the required items to use this factory", "error") return end
    local failed = false
    for item, qty in pairs(removeItems) do
        for i = 1, qty do
            if not Player.Functions.RemoveItem(item, 1) then
                if not failed then failed = {} end
                failed[item] = qty
            else
                TriggerClientEvent("inventory:client:ItemBox", src, QBCore.Shared.Items[item], "remove")
            end
        end
    end

    if failed then
        TriggerClientEvent("QBCore:Notify", src, "There has been a critical error in the factory script. Please contact server owner for reimbursment", "error")
        return
    end
    assert(not failed, "There has been a critical error in the factory script. Please contact server owner for reimbursment".. json.encode(failed or {}))

    for _, item in pairs(givesItems) do
        local product = item.product
        local amount = item.amount
        local info = item.info
        info.purity = purity
        info.drugName = factory.drugName
        if Player.Functions.AddItem(product, amount, false, info) then
            TriggerClientEvent("inventory:client:ItemBox", src, QBCore.Shared.Items[product], "add")
        end
    end
    local factoryProductionSpeedIndex = lab.upgrades["Production Speed"] or 1
    local factoryProductionSpeed = configUpgrades and configUpgrades["Production Speed"] and configUpgrades["Production Speed"][factoryProductionSpeedIndex] and configUpgrades["Production Speed"][factoryProductionSpeedIndex].amount
    assert(factoryProductionSpeed, "There has been a critical error in the factory script.")
    local waitTime = cooldown * factoryProductionSpeed

    Factories[id].CanUse = false
    Citizen.SetTimeout(waitTime, function()
        Factories[id].CanUse = true
        Factory.UpdateClients(id)
    end)
end

RegisterNetEvent("pandadrug:sv:UseFactory", function(id, recipe)
    local src = source
    if not id or not recipe then return end
    Factory.Use(src, id, recipe)
end)


























