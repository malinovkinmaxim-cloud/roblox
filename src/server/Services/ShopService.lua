--[[
	ShopService
	Buy / equip doppelgänger skins. Every request is validated on the server:
	item exists, price, enough coins, ownership.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CosmeticsConfig = require(ReplicatedStorage.Shared.CosmeticsConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local ShopService = {}

function ShopService:Init(services)
	self.Services = services
end

function ShopService:Start()
	local limiter = RateLimiter.new(3, 5)
	Net.Event("ShopAction").OnServerEvent:Connect(function(player, action, itemId)
		if not limiter:Allow(player) then
			return
		end
		if type(action) ~= "string" or type(itemId) ~= "string" or #itemId > 40 then
			return
		end
		local ok, message
		if action == "Buy" then
			ok, message = self:Buy(player, itemId)
		elseif action == "Equip" then
			ok, message = self:Equip(player, itemId)
		else
			return
		end
		if message then
			Net.Event("Toast"):FireClient(player, message, if ok then "Success" else "Error")
		end
	end)
end

function ShopService:Buy(player: Player, itemId: string): (boolean, string?)
	local item = CosmeticsConfig.Get(itemId)
	if not item then
		return false, "That item does not exist."
	end
	local data = self.Services.DataService:GetData(player)
	if not data then
		return false, "Your data is still loading."
	end
	if data.OwnedCosmetics[itemId] then
		return false, "You already own " .. item.DisplayName .. "."
	end
	if data.Coins < item.Price then
		return false, "Not enough coins."
	end
	self.Services.DataService:Update(player, function(d)
		d.Coins -= item.Price
		d.OwnedCosmetics[itemId] = true
		d.EquippedCosmetic = itemId
	end)
	return true, "Unlocked " .. item.DisplayName .. "! Equipped for your next doppelgänger."
end

function ShopService:Equip(player: Player, itemId: string): (boolean, string?)
	local item = CosmeticsConfig.Get(itemId)
	if not item then
		return false, "That item does not exist."
	end
	local data = self.Services.DataService:GetData(player)
	if not data then
		return false, nil
	end
	if not data.OwnedCosmetics[itemId] then
		return false, "You don't own that yet."
	end
	self.Services.DataService:Update(player, function(d)
		d.EquippedCosmetic = itemId
	end)
	-- refresh the lobby doppelgänger so the new look is visible right away
	local DoppelgangerService = self.Services.DoppelgangerService
	if not self.Services.RoundService:GetRun(player) then
		DoppelgangerService:RemoveLobbyDoppel(player)
		DoppelgangerService:EnsureLobbyDoppel(player)
	end
	return true, item.DisplayName .. " equipped."
end

return ShopService
