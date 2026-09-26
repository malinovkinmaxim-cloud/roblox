--[[
	CosmeticService - buy / equip Trails and Auras. The look itself is rendered by every client
	from the replicated "Trail" / "Aura" attributes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CosmeticConfig = require(Shared.CosmeticConfig)
local Format = require(Shared.Util.Format)

local Logic = script.Parent.Parent.Logic
local Session = require(Logic.Session)
local Guard = require(script.Parent.Parent.Util.Guard)

local CosmeticService = {}

local KINDS = { Trail = "Trails", Aura = "Auras" }

function CosmeticService:Init(services)
	self.Services = services
end

-- Owned = bought, or granted by a game pass
function CosmeticService.Owns(session, kind: string, id: string): boolean
	local def = CosmeticConfig.Get(kind, id)
	if not def then
		return false
	end
	if def.Pass then
		return session.Passes[def.Pass] == true
	end
	return session.Data[KINDS[kind]].Owned[id] == true
end

function CosmeticService.Buy(session, kind: any, id: any): (boolean, string?)
	if type(kind) ~= "string" or type(id) ~= "string" or not KINDS[kind] then
		return false, "Unknown item"
	end
	local def = CosmeticConfig.Get(kind, id)
	if not def then
		return false, "Unknown item"
	end
	if CosmeticService.Owns(session, kind, id) then
		return false, "Already owned"
	end
	if def.Pass or not def.Price then
		return false, "Get the " .. tostring(def.Pass or "VIP") .. " pass for this!"
	end
	local data = session.Data
	local field = if def.Price.Currency == "Gems" then "Gems" else "Coins"
	if data[field] < def.Price.Amount then
		return false, "Not enough " .. string.lower(field) .. " (" .. Format.Number(def.Price.Amount) .. ")"
	end
	data[field] -= def.Price.Amount
	data[KINDS[kind]].Owned[id] = true
	data[KINDS[kind]].Equipped = id
	session.AttrDirty = true
	Session.MarkDirty(session, "Stats", "Cosmetics")
	Session.Notify(session, "Success", "✨ " .. def.Name .. " " .. kind .. " unlocked!", { Sound = "Reward" })
	return true
end

function CosmeticService.Equip(session, kind: any, id: any): (boolean, string?)
	if type(kind) ~= "string" or not KINDS[kind] or type(id) ~= "string" then
		return false
	end
	if id ~= "" and not CosmeticService.Owns(session, kind, id) then
		return false, "You don't own this"
	end
	session.Data[KINDS[kind]].Equipped = id
	session.AttrDirty = true
	Session.MarkDirty(session, "Cosmetics")
	return true
end

function CosmeticService:Start()
	Guard.On("BuyCosmetic", 4, function(session, _player, kind, id)
		local ok, err = CosmeticService.Buy(session, kind, id)
		if not ok and err then
			Session.Notify(session, "Error", err)
		end
	end)
	Guard.On("EquipCosmetic", 6, function(session, _player, kind, id)
		local ok, err = CosmeticService.Equip(session, kind, id)
		if not ok and err then
			Session.Notify(session, "Error", err)
		end
	end)
end

return CosmeticService
