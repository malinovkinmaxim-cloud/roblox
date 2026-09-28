--[[
	MonetizationManager - Game Passes and Developer Products (see shared/MonetizationData.lua).

	  * pass ownership is cached per player (checked on join, updated on purchase)
	  * ProcessReceipt is idempotent (receipt ids are stored in the profile) and saves before
	    it reports PurchaseGranted
	  * items with Id = 0 are "not configured": in Studio a purchase is simulated so every
	    reward can be tested; in live servers the shop says it's unavailable
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Net = require(Shared.Net)
local MonetizationData = require(Shared.MonetizationData)

local Guard = require(script.Parent.Parent.Util.Guard)

local MonetizationManager = {}

function MonetizationManager:Init(services)
	self.Services = services
	self.Owned = {} -- [Player] = { [passKey] = true }
end

function MonetizationManager:HasPass(player: Player, key: string): boolean
	local owned = self.Owned[player]
	if owned and owned[key] then
		return true
	end
	-- simulated Studio purchases never count in live servers (Studio can share the DataStore)
	if not RunService:IsStudio() then
		return false
	end
	local session = self.Services.PlayerManager:Get(player)
	return session ~= nil and session.Data.StudioPasses[key] == true
end

function MonetizationManager:LoadPasses(player: Player)
	local owned = {}
	self.Owned[player] = owned
	for _, def in MonetizationData.Passes do
		if def.Id ~= 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.Id)
			end)
			if ok and has then
				owned[def.Key] = true
			end
		end
	end
end

local function grantPass(self, player: Player, key: string)
	self.Owned[player] = self.Owned[player] or {}
	self.Owned[player][key] = true
	local PM = self.Services.PlayerManager
	local def = MonetizationData.PassByKey[key]
	PM:Notify(player, "Thank you! " .. def.Name .. " is active", "Reward")
	local session = PM:Get(player)
	if session then
		self.Services.RewardManager:CheckCosmetics(session)
	end
	PM:Sync(player)
	self.Services.CharacterManager:Refresh(player)
end

-- applies a developer product. Returns true when granted.
function MonetizationManager:GrantProduct(player: Player, key: string): boolean
	local session = self.Services.PlayerManager:Get(player)
	local def = MonetizationData.ProductByKey[key]
	if not session or not def then
		return false
	end
	local PM = self.Services.PlayerManager
	local RM = self.Services.RewardManager
	-- never take Robux for nothing: a product that can't apply any more is refunded in coins
	local function refund(coins: number)
		RM:GiveCoins(session, coins)
		PM:Notify(player, def.Name .. " refunded as +" .. coins .. " coins", "Reward")
	end
	if key == "Revive" then
		if not self.Services.GameManager:ApplyRobuxRevive(player) then
			refund(250)
		end
	elseif key == "ExtraReroll" then
		if self.Services.GameManager:ApplyExtraReroll(player) then
			PM:Notify(player, "+1 reroll", "Reward")
		else
			refund(100)
		end
	elseif key == "ExtraChest" then
		local ok, coins, fragments = RM:OpenExtraChest(session)
		if ok then
			PM:Notify(player, string.format("EXTRA CHEST: +%d coins, +%d fragment", coins, fragments), "Reward")
		else
			refund(250)
		end
	elseif key == "CosmeticBoost" then
		local now = os.time()
		session.Data.CosmeticBoostUntil = math.max(now, session.Data.CosmeticBoostUntil) + (def.Minutes or 30) * 60
		PM:Notify(player, "67 AURA active!", "Reward")
		self.Services.CharacterManager:Refresh(player)
	elseif key == "AfkBoost" then
		self.Services.AfkManager:Boost(session, def.Minutes or 240)
		PM:Notify(player, "AFK BOOST active: x2 camp rewards", "Reward")
	end
	PM:Sync(player)
	return true
end

function MonetizationManager:PromptPass(player: Player, key: string)
	local def = MonetizationData.PassByKey[key]
	if not def or self:HasPass(player, key) then
		return
	end
	if def.Id == 0 then
		local session = self.Services.PlayerManager:Get(player)
		if RunService:IsStudio() and session then
			-- Studio test: simulate the purchase
			session.Data.StudioPasses[key] = true
			grantPass(self, player, key)
		else
			self.Services.PlayerManager:Notify(player, def.Name .. " is not available yet", "Error")
		end
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, def.Id)
end

function MonetizationManager:PromptProduct(player: Player, key: string)
	local def = MonetizationData.ProductByKey[key]
	if not def then
		return
	end
	if def.Id == 0 then
		if RunService:IsStudio() then
			-- Studio test: simulate the purchase
			self:GrantProduct(player, key)
		else
			self.Services.PlayerManager:Notify(player, def.Name .. " is not available yet", "Error")
		end
		return
	end
	MarketplaceService:PromptProductPurchase(player, def.Id)
end

function MonetizationManager:ProcessReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local session = player and self.Services.PlayerManager:Get(player)
	if not player or not session then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receipts = session.Data.Receipts
	if table.find(receipts, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key = nil
	for _, def in MonetizationData.Products do
		if def.Id ~= 0 and def.Id == info.ProductId then
			key = def.Key
		end
	end
	if not key or not self:GrantProduct(player, key) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(receipts, 1, info.PurchaseId)
	while #receipts > 50 do
		table.remove(receipts)
	end
	if not self.Services.DataManager:Save(session, false) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationManager:Start()
	MarketplaceService.ProcessReceipt = function(info)
		return self:ProcessReceipt(info)
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for _, def in MonetizationData.Passes do
			if def.Id == passId then
				grantPass(self, player, def.Key)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.Owned[player] = nil
	end)

	Guard.Connect(Net.Event("Buy"), { Rate = 1, Burst = 3 }, function(player, kind, key)
		if kind == "Pass" and Guard.Str(key, 32) then
			self:PromptPass(player, key)
		elseif kind == "Product" and Guard.Str(key, 32) then
			self:PromptProduct(player, key)
		end
	end)
	-- Studio only: pretend a pass was bought (ids are not configured while testing)
	Guard.Connect(Net.Event("StudioPurchase"), { Rate = 1, Burst = 3 }, function(player, kind, key)
		if not RunService:IsStudio() then
			return
		end
		local session = self.Services.PlayerManager:Get(player)
		if not session or type(key) ~= "string" then
			return
		end
		if kind == "Pass" and MonetizationData.PassByKey[key] then
			session.Data.StudioPasses[key] = true
			grantPass(self, player, key)
		elseif kind == "Product" and MonetizationData.ProductByKey[key] then
			self:GrantProduct(player, key)
		end
	end)
end

return MonetizationManager
