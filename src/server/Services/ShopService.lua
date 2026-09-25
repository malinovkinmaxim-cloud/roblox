--[[
	ShopService
	Buy / equip cosmetics (skins, trails, emotes) and equip earned titles.
	Every request is validated on the server: item exists, category, price, coins, ownership,
	title requirements.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CosmeticsConfig = require(ReplicatedStorage.Shared.CosmeticsConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local TitleConfig = require(ReplicatedStorage.Shared.TitleConfig)
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
		elseif action == "EquipTitle" then
			ok, message = self:EquipTitle(player, itemId)
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
	local field = CosmeticsConfig.EquipField[item.Category]
	self.Services.DataService:Update(player, function(d)
		d.Coins -= item.Price
		d.OwnedCosmetics[itemId] = true
		if field then
			d[field] = itemId
		end
	end)
	self:_onEquipped(player, item.Category)
	return true, "Unlocked " .. item.DisplayName .. "!"
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
	local field = CosmeticsConfig.EquipField[item.Category]
	if not field then
		return false, nil
	end
	self.Services.DataService:Update(player, function(d)
		d[field] = itemId
	end)
	self:_onEquipped(player, item.Category)
	return true, item.DisplayName .. " equipped."
end

function ShopService:EquipTitle(player: Player, titleId: string): (boolean, string?)
	local title = TitleConfig.Titles[titleId]
	if not title then
		return false, nil
	end
	local data = self.Services.DataService:GetData(player)
	if not data then
		return false, nil
	end
	if not TitleConfig.IsUnlocked(data, titleId) then
		return false, "Not unlocked yet: " .. title.Description
	end
	self.Services.DataService:Update(player, function(d)
		d.EquippedTitle = titleId
	end)
	self.Services.CharacterService:ApplyCosmetics(player)
	return true, "Title: " .. title.Text
end

-- make the change visible right away
function ShopService:_onEquipped(player: Player, category: string)
	if category == "Trail" then
		self.Services.CharacterService:ApplyCosmetics(player)
	elseif category == "Skin" or category == "Emote" then
		local DoppelgangerService = self.Services.DoppelgangerService
		if not self.Services.RoundService:GetRun(player) then
			DoppelgangerService:RemoveLobbyDoppel(player)
			DoppelgangerService:EnsureLobbyDoppel(player)
		end
	end
end

return ShopService
