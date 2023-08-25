Database = {}

function Database.Setup()
	MySQL.query.await('CREATE TABLE IF NOT EXISTS pandadrugs (id VARCHAR(50), PRIMARY KEY(id), ownerCID VARCHAR(50), pin SMALLINT, upgrades LONGTEXT, security TEXT)')
end

function Database.GetDrugLab(id)
    local result = MySQL.query.await('SELECT * FROM pandadrugs WHERE id = ?', {id})
    if result[1] then
        result[1].upgrades = json.decode(result[1].upgrades)
        return result[1]
    end
end

function Database.DeleteDrugLab(id)
    MySQL.query.await('DELETE FROM pandadrugs WHERE id = ?', {id})
end

function Database.UpdateOwner(id, newOwnerCID)
    MySQL.query.await('UPDATE pandadrugs SET ownerCID = ? WHERE id = ?', {newOwnerCID, id})
end

function Database.UpdateUpgrades(id, upgrades)
    upgrades = json.encode(upgrades)
    MySQL.query.await('UPDATE pandadrugs SET upgrades = ? WHERE id = ?', {upgrades, id})
end

function Database.UpdatePin(id, pin)
    MySQL.query.await('UPDATE pandadrugs SET pin = ? WHERE id = ?', {pin, id})
end

function Database.UpdateSecurity(id, security)
    MySQL.query.await('UPDATE pandadrugs SET security = ? WHERE id = ?', {security, id})
end

function Database.CreateDrugLab(id, ownerCID, upgrades, security)
    upgrades = json.encode(upgrades)
    MySQL.query.await('INSERT INTO pandadrugs (id, ownerCID, pin, upgrades, security) VALUES (?, ?, ?, ?, ?)', {id, ownerCID, nil,  upgrades, security})
end

function Database.GetAll()
    local result = MySQL.query.await('SELECT * FROM pandadrugs')
    local labs = {}
    for k, v in pairs(result) do
        v.upgrades = json.decode(v.upgrades)
        labs[v.id] = v
    end
    return labs
end
-- --Makes sure the database is setup
CreateThread(function()
    Database.Setup()
end)