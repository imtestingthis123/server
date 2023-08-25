QBCore = QBCore or exports['qb-core']:GetCoreObject()
local LabCache = nil
local bucketsInUse = {}

local function isAdmin(id)
    return IsPlayerAceAllowed(id, "command")
end


function LabFunctions.LoadAll()
    LabCache = LabCache or Database.GetAll()
    return LabCache
end

function LabFunctions.GetLabCachedData(labID)
    local labCache = LabFunctions.LoadAll()
    labCache[labID] = labCache[labID] or Database.GetDrugLab(labID)
    return labCache[labID]
end

function LabFunctions.SetUnsavedLabValue(labID, key, value)
    local lab = LabFunctions.GetLabCachedData(labID)
    if not lab then return false end
    LabCache[labID][key] = value
    return true
end

function LabFunctions.GetUnsavedLabValue(labID, key)
    local lab = LabFunctions.GetLabCachedData(labID)
    if not lab then return false end
    return lab[key]
end

function LabFunctions.CreateFactoryForPlayer(labID, configId, src)
    local self =  LabFunctions.GetLabCachedData(labID)
    if not self then return false end
    local drugName, _ = SplitId(labID)
    if not drugName then return false end
    local factory = Factory.Create(labID, drugName, configId, self.bucket, src)
    if not factory then return false end
    if not self.factories then self.factories = {} end
    self.factories[factory] = configId

    Factory.AddPlayer(factory, src)
    LabFunctions.SetUnsavedLabValue(labID, 'factories', self.factories)
    return factory
end

function LabFunctions.CreateFactoriesForPlayer(labID, src)
    local drugName, locationName = SplitId(labID)
    if not drugName then return false end
    local factories = Factory.GetByLabID(lab)    
    if factories then
        Factory.SetUpgradesBasedOnLab(labid)
        for k, v in pairs(factories) do
            Factory.AddPlayer(v, src)
        end
    else
        factories = Factory.GetConfigFactories(drugName) or {}
        for configFactoryId, _ in pairs(factories) do

            LabFunctions.CreateFactoryForPlayer(labID, configFactoryId, src)
        end
    end
    return LabFunctions.GetUnsavedLabValue(labID, 'factories')
end

function LabFunctions.FormatConfigUpgrades(labID)
    local drugName, _ = SplitId(labID)
    local upgrades = Config.Drugs[drugName].Upgrades
    local formattedUpgrades = {}
    for k, v in pairs(upgrades) do
        formattedUpgrades[k] = 1
    end
    return formattedUpgrades
end

function LabFunctions.IsOwned(labID)
    local lab = LabFunctions.GetLabCachedData(labID)
    if not lab then return false end
    local ownerCID = lab.ownerCID
    if not ownerCID then return false end
    return true, ownerCID
end

function LabFunctions.IsOwner(source, labID)
    local isOwned, ownerCID = LabFunctions.IsOwned(labID)
    if not isOwned then return false end
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    return Player.PlayerData.citizenid == ownerCID
end

function LabFunctions.BuyUnownedLab(source, args)
    local labID = args.labid
    local drugName, locationName = SplitId(labID)
    local isOwned, ownerCID = LabFunctions.IsOwned(source, labID)
    if isOwned then return false end
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    local drug = Config.Drugs[drugName]
    if not drug then return false end
    local location = drug.Locations[locationName]
    if not location then return false end
    local price = location.Price
    if not price then return false end
    if not Player.Functions.RemoveMoney('cash', price) then return false end
    local upgrades = LabFunctions.FormatConfigUpgrades(labID)
    local factories = LabFunctions.CreateFactoriesForPlayer(labID, source)
    Database.CreateDrugLab(labID, Player.PlayerData.citizenid, upgrades, "none")
    LabFunctions.UpdateClients(labID)
    return true
end

function LabFunctions.UpgradeLab(source, labID, upgradeId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    local IsOwner = LabFunctions.IsOwner(source, labID)
    if not IsOwner then
        TriggerClientEvent('QBCore:Notify', source, "You do not own this lab", "error")
        return false
    end

    local lab = LabFunctions.GetLabCachedData(labID)
    assert(lab, "Lab not found")

    local drugName, locationName = SplitId(labID)
    local upgrades = lab.upgrades or Config.Drugs[drugName].Upgrades
    local currentUpgradeLevel = upgrades[upgradeId] or 1


    local configDrug = Config.Drugs[drugName]
    assert(configDrug, "Drug not found")

    local newUpgradeLevel = currentUpgradeLevel + 1
    local nextUpgradeLevel = currentUpgradeLevel < #configDrug.Upgrades[upgradeId] and newUpgradeLevel or false
    if not nextUpgradeLevel then return false end
    local configUpgrades = configDrug.Upgrades[upgradeId] and configDrug.Upgrades[upgradeId][newUpgradeLevel]
    assert(configUpgrades, "Upgrade not found")
    local price = configUpgrades.price
    assert(price, "Price not found")

    if not Player.Functions.RemoveMoney('cash', price) then TriggerClientEvent('QBCore:Notify', source, "You do not have enough money", "error") return end

    if upgradeId == "Security Upgrade" then
      if newUpgradeLevel == 2 then
        LabFunctions.GiveKeys(source, labID, 1)
      end
      if newUpgradeLevel == 3 then
        TriggerClientEvent('QBCore:Notify', source, "Congratulations on the upgrade, Please remember to set your pin at this door!", "success", "10000")
      end
    end

    TriggerClientEvent('QBCore:Notify', source, "You have upgraded your lab for $"..price, "success")
    upgrades[upgradeId] = currentUpgradeLevel + 1
    Database.UpdateUpgrades(labID, upgrades)
    LabCache[labID].upgrades = upgrades
    Factory.SetUpgradesBasedOnLab(labID)
    local factories = Factory.GetByLabID(labID)
    for k, v in pairs(factories) do
        Factory.UpdateClients(v)
    end
    TriggerClientEvent('pandadrugs:cl:UpgradeLab', -1, LabCache[labID])
    TriggerEvent('pandadrugs:sv:OnLabUpgrade', source, labID, upgradeId, newUpgradeLevel)
    return true
end

function LabFunctions.SellLab(labID, fromSrc, toSrc, price)
    local src = fromSrc
    if CheckPlayerDistance(src, toSrc) > 3.0 then return false end

    local lab = LabFunctions.GetLabCachedData(labID)
    if not lab then return false end
    local additionalValue = CalculateMaxValue(drugName, lab.upgrades)

    local ownerCID = lab.ownerCID
    if not ownerCID then return false end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    if Player.PlayerData.citizenid ~= ownerCID then return false end
    local toPlayer = QBCore.Functions.GetPlayer(toSrc)
    if not toPlayer then return false end
    if not toPlayer.Functions.RemoveMoney('cash', price) then return TriggerClientEvent('QBCore:Notify', src, "The buyer does not have enough money", "error") end
    TriggerClientEvent('QBCore:Notify', src, "You have sold your lab for $"..price, "success")
    Database.UpdateOwner(labID, toPlayer.PlayerData.citizenid)
    LabCache[labID].ownerCID = toPlayer.PlayerData.citizenid
    if Player.Functions.AddMoney('cash', price) then
        TriggerClientEvent('QBCore:Notify', src, "You have sold your lab for $"..price, "success")
    else
        TriggerClientEvent('QBCore:Notify', src, "There was an error with the sale, but your lab is now sold. Open a ticket to be reimbursed", "error")
    end
    LabFunctions.UpdateClients(labID)
end

function LabFunctions.GetLabUpgrades(labID)
    local lab = LabFunctions.GetLabCachedData(labID)
    local drugName, locationName = SplitId(labID)
    if not lab then return false end
    local formattedConfigUpgrades = LabFunctions.FormatConfigUpgrades(labID)
    local upgrades = lab.upgrades or {}
    local returnUpgrades = {}
    for k, v in pairs(formattedConfigUpgrades) do
        if upgrades[k] then
            returnUpgrades[k] = upgrades[k]
        else
            returnUpgrades[k] = 1
        end
    end
    return returnUpgrades
end

function LabFunctions.GetLabUpgradeById(labID, upgradeId)
    local lab = LabFunctions.GetLabCachedData(labID)
    if not lab then return false end
    local upgrades = lab.upgrades
    if not upgrades then return false end
    local upgrade = upgrades[upgradeId]
    if not upgrade then return false end
    return true, upgrade
end

function LabFunctions.IsValidPin(pin)
    if not pin then return false end
    if type(pin) ~= "number" then return false end
    if pin < 1000 or pin > 9999 then return false end
    return true
end

function LabFunctions.SetPin(src, labID,  pin)
    if not pin then return TriggerClientEvent('QBCore:Notify', src, "You must enter a pin", "error") end
    if not LabFunctions.IsValidPin(pin) then return TriggerClientEvent('QBCore:Notify', src, "You must enter a valid pin", "error") end
    local lab = LabFunctions.GetLabCachedData(labID)
    if not lab then return false end
    local ownerCID = lab.ownerCID
    if not ownerCID then return false end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    if Player.PlayerData.citizenid ~= ownerCID then return TriggerClientEvent('QBCore:Notify', src, "You do not own this lab", "error") end
    Database.UpdatePin(labID,  pin)
    LabCache[labID].pin = pin
    TriggerClientEvent('QBCore:Notify', src, "You have set your pin to "..pin, "success")
    LabFunctions.UpdateClients(labID)
    return true
end

function LabFunctions.GetPin(labID)
    local lab = LabFunctions.GetLabCachedData(labID)
    if not lab then return false end
    local pin = lab.pin
    if not pin then return false end
    return pin
end

function LabFunctions.PinMatches(labID, pincode)
    local labPin = tonumber(LabFunctions.GetPin(labID))
    local playerInput = tonumber(pincode)
    if not labPin then return true end
    if labPin ~= playerInput then return false end
    return true
end

function LabFunctions.SetSecurity(src, labID, security)
    local src = source
    local lab = LabFunctions.GetLabCachedData(labID)
    if not lab then return false end
    if not LabFunctions.IsOwner(src, labID) then return false end
    Database.UpdateSecurity(labID,  security)
    LabCache[labID].security = security
    return true
end

function LabFunctions.GetSecurity(labID)
    local lab = LabFunctions.GetLabCachedData(labID)
    if not lab then return false end
    local security = lab.security
    if not security then return false end
    return security
end

function LabFunctions.HasKey(labID, src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end

    local lab = LabFunctions.GetLabCachedData(labID)
    if not lab then return false end
    local keyItems = Player.Functions.GetItemsByName('pandadrugs_key')
    if not keyItems then return false end
    for k, v in pairs(keyItems) do
        local info = v.info or v.metadata
        if v.info.labID == labID then
            return true
        end
    end
    return false
end

function LabFunctions.GiveKeys(src, labID, quantity)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    local lab = LabFunctions.GetLabCachedData(labID)
    if not lab then return false end
    local keyPrice = Config.KeyPrice or 0 --default to 0 if no keyPrice is set
    local totalPurchasePrice = keyPrice * quantity
    if Player.Functions.RemoveMoney('cash', totalPurchasePrice, "Suspicious Key") then
        Player.Functions.AddItem('pandadrugs_key', quantity, false, {labID = labID})
        return true
    end
    TriggerClientEvent('QBCore:Notify', src, "You do not have enough money to buy a key", "error")
    return false
end

function LabFunctions.UpdateClients(labID)
    local lab = LabFunctions.GetLabCachedData(labID)
    if not lab then return false end
    local isOwned = LabFunctions.IsOwned(labID)
    local owner = lab.ownerCID
    local upgrades = LabFunctions.GetLabUpgrades(labID)
    TriggerClientEvent('pandadrugs:cl:UpdateLab', -1, labID, isOwned, owner, upgrades)
    return true
end

function LabFunctions.ResetBucket(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    Player.Functions.SetMetaData("insideLab", nil)
    Player.Functions.Save()
    SetPlayerRoutingBucket(src, 0)
end

function LabFunctions.SetBucket(source)
    SetPlayerRoutingBucket(source, bucket)
end

local ClientLoaded = false
RegisterNetEvent('pandadrugs:sv:ClientLoaded', function()
    if ClientLoaded then return end
    LabFunctions.UpdateAllLabs(-1)
    for k, v in pairs(QBCore.Functions.GetPlayers()) do
        LabFunctions.EnsureExit(v)
    end
    ClientLoaded = true
end)

function LabFunctions.UpdateAllLabs(src)
    LabCache = LabCache or Database.GetAll()
    local serverLabs = {}
    for k, v in pairs(LabCache) do
        local labID = k
        local isOwned = LabFunctions.IsOwned(labID)
        local owner = v.ownerCID
        local upgrades = LabFunctions.GetLabUpgrades(labID)
        serverLabs[k] = { isOwned = isOwned, owner = owner, upgrades = upgrades, security = v.security}
    end
    TriggerClientEvent('pandadrugs:cl:UpdateAllLabs', src, serverLabs)
end

function LabFunctions.GetBucketIfExists(labID)
    local lab = LabFunctions.GetLabCachedData(labID)
    if not lab then return false end
    local bucket = lab.bucket
    if not bucket then return false end
    return bucket
end

function LabFunctions.GenerateBucket(src, drugName, _recursion)
    _recursion = _recursion or 0
    if _recursion > 100 then return false end
    local bucket = math.random(1, 60)
    local id = drugName..':'..bucket
    if bucketsInUse[id] == nil then
        bucketsInUse[id] = true
        return bucket
    end
    return LabFunctions.GenerateBucket(src, drugName, _recursion + 1)
end

function LabFunctions.OnEnter(src, labID)
    Wait(100)
    local lab = LabFunctions.GetLabCachedData(labID)
    if not lab then return false end

    local drugName, locationName = SplitId(labID)
    local config = Config.Drugs[drugName] and Config.Drugs[drugName].Locations[locationName]
    if not config then return false end
    local shell = config.Shell
    if shell then
        local exit = config.Doors.Exit or {}
        local exitCoords = exit.coords or vector4(0, 0, 0, 0)
        local shellOffset = shell.offset or vector4(0, 0, 0, 0)
        local shellCoords = vector4(exitCoords.x + shellOffset.x, exitCoords.y + shellOffset.y, exitCoords.z + shellOffset.z -2.5, exitCoords.w + shellOffset.w)
        TriggerClientEvent('pandadrugs:cl:CreateShell', src, shell.name, shellCoords)
    end
   
    local bucket = LabFunctions.GetUnsavedLabValue(labID, 'bucket')
    if not bucket then
        bucket = LabFunctions.GenerateBucket(src, labID)
        lab.bucket = bucket
        LabFunctions.SetUnsavedLabValue(labID, 'bucket', bucket)
    end
    SetPlayerRoutingBucket(src, bucket)
    LabFunctions.SetUnsavedLabValue(labID, 'bucket', bucket)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    Player.Functions.SetMetaData("insideLab", { labID = labID})
    local labPlayers = LabFunctions.GetUnsavedLabValue(labID, 'players')
    if not labPlayers then
        labPlayers = src
    elseif type(labPlayers) == "number" then
        labPlayers = {labPlayers, src}
    elseif type(labPlayers) == "table" then
        labPlayers[#labPlayers + 1] = src
    end

    --if not drugName or not location, database is missaligned to config

    LabFunctions.SetUnsavedLabValue(labID, 'players', labPlayers)
    Wait(100)
    LabFunctions.CreateFactoriesForPlayer(labID, src)
    return true
end

function LabFunctions.EnsureExit(src)
    local Player = QBCore.Functions.GetPlayer(src)
    while not Player do
        Wait(100)
        Player = QBCore.Functions.GetPlayer(src)
    end
    local insideLab = Player.PlayerData.metadata.insideLab
    if not insideLab then return false end
    local labID = insideLab.labID
    if not labID then return false end
    LabFunctions.OnEnter(src, labID)
    TriggerClientEvent('pandadrugs:cl:EnsureExit', src, labID)
end

function LabFunctions.Destroy(src, labID)

end

local loaded = false
AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        loaded = true
        TriggerClientEvent("QBCore:Notify", -1, "PandaDrugs has been loaded", "success")
        LabCache = LabFunctions.LoadAll()
        LabFunctions.UpdateAllLabs(-1)
        for k, v in pairs(QBCore.Functions.GetPlayers()) do
            LabFunctions.EnsureExit(v)
        end
    end
end)

AddEventHandler('playerJoining', function()
    local src = source
    while not QBCore.Functions.GetPlayer(src) do
        Wait(100)
    end
    local labCache = loaded or LabFunctions.LoadAll()
    LabFunctions.UpdateAllLabs(src)
    Wait(1000)
    LabFunctions.EnsureExit(src)
end)

RegisterNetEvent('pandadrugs:sv:BuyLab', function(args)
    local src = source
    LabFunctions.BuyUnownedLab(src, args)
    -- DiscordLog(false, {title = "Bought Lab", description = GetPlayerName(src).." bought "..args.labID , colour = 16711680})
end)

RegisterNetEvent('pandadrugs:sv:UpgradeLab', function(args)
    local labID = args.labid
    local upgradeId = args.upgradeName
    local src = source
    LabFunctions.UpgradeLab(src, labID, upgradeId)
    DiscordLog(false, {title = "Upgraded Lab", description = GetPlayerName(src).." upgraded "..labID.." upgraded:"..upgradeId, colour = 16711680})
end)

RegisterNetEvent('pandadrugs:sv:SellLab', function(args)
    local src = source
    local labID = args.labid
    local tosrc = args.id
    local price = args.price
    LabFunctions.SellLab(labID, src, tosrc, price)
    DiscordLog(false, {title = "Sold Lab", description = GetPlayerName(src).." sold "..labID.." for: $"..price , colour = 16711680})
end)

RegisterNetEvent('pandadrugs:sv:SetPin', function(labID, pin)
    local src = source
    LabFunctions.SetPin(src, labID, pin)
    DiscordLog(false, {title = "Set Pin", description = GetPlayerName(src).." set the pin for "..labID.." to: "..pin , colour = 16711680})
end)

RegisterNetEvent('pandadrugs:sv:BuyKey', function(labID)
    local src = source
    LabFunctions.GiveKeys(src, labID, 1)
    DiscordLog(false, {title = "Bought Key", description = GetPlayerName(src).." bought a key for "..labID , colour = 16711680})
end)

RegisterNetEvent("pandadrugs:sv:Exit", function(labID)
    local src = source
    LabFunctions.ResetBucket(src)
    TriggerClientEvent("pandadrugs:cl:DestroyShell", src)
    DiscordLog(false, {title = "Exited Lab", description = GetPlayerName(src).." exited "..labID , colour = 16711680})
end)

RegisterNetEvent("pandadrugs:sv:Enter", function(labID)
    local src = source
    LabFunctions.OnEnter(src, labID)
    DiscordLog(false, {title = "Entered Lab", description = GetPlayerName(src).." entered "..labID , colour = 5763719})
end)

QBCore.Functions.CreateCallback("pandadrugs:cb:IsOwned", function(source, cb, labID)
    cb(LabFunctions.IsOwned(labID))
end)

QBCore.Functions.CreateCallback("pandadrugs:cb:IsOwner", function(source, cb, labID)
    local src = source
    cb(LabFunctions.IsOwner(src, labID))
end)

QBCore.Functions.CreateCallback("pandadrugs:cb:GetPin", function(source, cb, labID, pincode)
    cb(LabFunctions.PinMatches(labID, pincode))
end)

QBCore.Functions.CreateCallback("pandadrugs:cb:HasKey", function(source, cb, labID)
    local src = source
    cb(LabFunctions.HasKey(labID, src))
end)

RegisterCommand("givekey", function(source, args)
    if not source == 0 or isAdmin(source) then return end
    local src = tonumber(args[1])
    local labID = args[2]
    LabFunctions.GiveKeys(src, labID, 1)
    DiscordLog(false, {title = "Gave Key", description = GetPlayerName(src).." gave a key for "..labID , colour = 16711680})
end)

RegisterCommand("resetbucket", function(source, args)
    if not source == 0 or isAdmin(source) then return end
    local src = tonumber(args[1])
    local bucket = tonumber(args[2]) or 0
    SetPlayerRoutingBucket(src, bucket)
    DiscordLog(false, {title = "Reset Bucket", description = GetPlayerName(src).." reset bucket to "..bucket , colour = 16711680})
end)

exports('LabFunctions', function()
    return LabFunctions
end)