--[[
	MonetizationManager - Game Passes and Developer Products (see shared/MonetizationData.lua).

	  * pass ownership is cached per player (checked on join, updated on purchase)
	  * ProcessReceipt is idempotent (receipt ids are stored in the profile) and saves before
	    it reports PurchaseGranted
	  * items with Id = 0 are "not configured": in Studio a purchase is simulated so every
	    reward can be tested; in live servers the shop shows them as SOON
	  * prices come from Roblox (GetProductInfo) so the shop shows what the dashboard says
	  * SUPPORT products are donations: a thank you and a count in the profile, no reward
	  * PREMIUM abilities (shared/AbilityConfig.lua Premium): a pass is checked live, a product
	    is saved in the profile (Premium.Owned); OwnsAbility / PremiumOwned answer both. The
	    daily TRIAL (ArmTrial from the Premium tab, TakeTrial at run start) lends one premium
	    ability the player does not own to one run a day
	  * ability skins and the trail pack: passes / products that give cosmetics
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Net = require(Shared.Net)
local MonetizationData = require(Shared.MonetizationData)
local WeaponData = require(Shared.WeaponData)
local AbilityConfig = require(Shared.AbilityConfig)

local Guard = require(script.Parent.Parent.Util.Guard)

local MonetizationManager = {}

function MonetizationManager:Init(services)
	self.Services = services
	self.Owned = {} -- [Player] = { [passKey] = true }
	self.Prices = {} -- [key] = the live price in Robux (read from Roblox for configured items)
end

-- reads the real prices of the configured passes / products (in the background)
function MonetizationManager:LoadPrices()
	local function load(def, infoType)
		if def.Id == 0 then
			return
		end
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(def.Id, infoType)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			self.Prices[def.Key] = info.PriceInRobux
		end
	end
	for _, def in MonetizationData.Passes do
		load(def, Enum.InfoType.GamePass)
	end
	for _, def in MonetizationData.Products do
		load(def, Enum.InfoType.Product)
	end
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

-- does the player own this premium ability (its pass, or its product saved in the profile)?
function MonetizationManager:OwnsAbility(player: Player, key: string): boolean
	local sale = MonetizationData.ForAbility(key)
	if not sale then
		return false
	end
	if MonetizationData.PassByKey[sale.Key] then
		return self:HasPass(player, sale.Key)
	end
	local session = self.Services.PlayerManager:Get(player)
	return session ~= nil and session.Data.Premium.Owned[key] == true
end

-- the premium abilities the player owns: { [key] = true }
function MonetizationManager:PremiumOwned(player: Player): { [string]: boolean }
	local out = {}
	for _, def in WeaponData.Premium do
		if self:OwnsAbility(player, def.Key) then
			out[def.Key] = true
		end
	end
	return out
end

---------------------------------------------------------------------------
-- the daily TRIAL
---------------------------------------------------------------------------
function MonetizationManager.TrialDay(now: number?): number
	return math.floor((now or os.time()) / (AbilityConfig.Trial.Hours * 3600))
end

-- today's trial ability for this player (a different one every day, one they do not own), or nil
function MonetizationManager:TrialOf(player: Player): string?
	local owned = self:PremiumOwned(player)
	local pool = {}
	for _, def in WeaponData.Premium do
		if not owned[def.Key] then
			table.insert(pool, def.Key)
		end
	end
	if #pool == 0 then
		return nil
	end
	local day = MonetizationManager.TrialDay()
	return pool[(player.UserId + day * 7) % #pool + 1]
end

-- trials left today
function MonetizationManager:TrialsLeft(session): number
	local p = session.Data.Premium
	local used = if p.TrialUsedDay == MonetizationManager.TrialDay() then p.TrialUses else 0
	return math.max(0, AbilityConfig.Trial.PerDay - used)
end

-- the Premium tab's TRY IT: today's trial joins the next run
function MonetizationManager:ArmTrial(player: Player)
	local PM = self.Services.PlayerManager
	local session = PM:Get(player)
	if not session then
		return
	end
	local key = self:TrialOf(player)
	if not key then
		PM:Notify(player, "You own every premium ability!", "Info")
		return
	end
	if self:TrialsLeft(session) <= 0 then
		PM:Notify(player, "Your free trial is used today. A new one tomorrow!", "Error")
		return
	end
	local p = session.Data.Premium
	p.TrialDay = MonetizationManager.TrialDay()
	p.TrialKey = key
	PM:Notify(player, "FREE TRIAL: " .. WeaponData.Get(key).Name .. " joins your next run!", "Reward")
	PM:Sync(player)
end

-- run start: the armed trial ability (and it is used up), or nil
function MonetizationManager:TakeTrial(player: Player): string?
	local session = self.Services.PlayerManager:Get(player)
	if not session then
		return nil
	end
	local p = session.Data.Premium
	local day = MonetizationManager.TrialDay()
	local key = p.TrialKey
	if key == "" or p.TrialDay ~= day or self:TrialsLeft(session) <= 0 or self:OwnsAbility(player, key) then
		return nil
	end
	p.TrialUses = (if p.TrialUsedDay == day then p.TrialUses else 0) + 1
	p.TrialUsedDay = day
	p.TrialKey = ""
	return key
end

-- the Premium tab's view: owned abilities and the trial
function MonetizationManager:PremiumSnapshot(player: Player, session)
	local p = session.Data.Premium
	local trial = self:TrialOf(player)
	return {
		Owned = self:PremiumOwned(player),
		Trial = trial,
		TrialLeft = self:TrialsLeft(session),
		TrialArmed = trial ~= nil and p.TrialKey == trial and p.TrialDay == MonetizationManager.TrialDay(),
	}
end

-- what a pass / product gives besides itself: a premium ability, cosmetics
local function grantExtras(self, player: Player, session, def)
	local PM = self.Services.PlayerManager
	if def.Ability then
		PM:Notify(player, WeaponData.Get(def.Ability).Name .. " is yours: it shows up in your runs!", "Reward")
	end
	if def.Cosmetics and session then
		local cos = session.Data.Cosmetics
		for _, id in def.Cosmetics do
			if not cos.Owned[id] then
				cos.Owned[id] = true
				cos.New[id] = true
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
	grantExtras(self, player, PM:Get(player), def)
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
	if def.Donation then
		-- SUPPORT: a thank you, counted in the profile (no reward in the game)
		local stats = session.Data.Stats
		stats.Supported += 1
		stats.SupportedRobux += self.Prices[key] or def.Price
		PM:Notify(player, "Thank you so much for supporting 67 Survival!", "Reward")
		PM:Sync(player)
		return true
	end
	-- never take Robux for nothing: a product that can't apply any more is refunded in coins
	local function refund(coins: number)
		RM:GiveCoins(session, coins)
		PM:Notify(player, def.Name .. " refunded as +" .. coins .. " coins", "Reward")
	end
	if def.Ability or def.Cosmetics then
		-- a premium ability / an ability skin / the trail pack sold as a product: saved for good
		if def.Ability then
			if session.Data.Premium.Owned[def.Ability] then
				refund(500)
				PM:Sync(player)
				return true
			end
			session.Data.Premium.Owned[def.Ability] = true
		end
		grantExtras(self, player, session, def)
		PM:Notify(player, "Thank you! " .. def.Name .. " is yours", "Reward")
	elseif key == "Revive" then
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
	task.spawn(function()
		self:LoadPrices()
	end)
	-- tell the creator which items can't be sold yet (see shared/MonetizationData.lua)
	local missing = MonetizationData.Unconfigured()
	if #missing > 0 then
		print(string.format("[67 SURVIVAL] %d Robux items have no id yet (shown as SOON in the published game): %s. Paste the ids in ReplicatedStorage.Modules.MonetizationData.", #missing, table.concat(missing, ", ")))
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

	-- the Premium tab: today's free trial joins the next run
	Guard.Connect(Net.Event("PremiumTrial"), { Rate = 1, Burst = 2 }, function(player)
		self:ArmTrial(player)
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
