--[[
	MonetizationService - game passes + developer products.

	  * passes are checked with UserOwnsGamePassAsync on join and granted live after a purchase
	  * ProcessReceipt is idempotent: processed receipt ids are stored in the player's data, the
	    grant is saved immediately and only then reported as PurchaseGranted
	  * items with Id = 0 are "not configured": in Studio they can be test-bought for free
	    (StudioPurchase remote), in a live game they are hidden by the client and rejected here
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig = require(Shared.ShopConfig)

local Logic = script.Parent.Parent.Logic
local Defaults = require(Logic.Defaults)
local Session = require(Logic.Session)
local Rewards = require(Logic.Rewards)
local Growth = require(Logic.Growth)
local Pets = require(Logic.Pets)
local Guard = require(script.Parent.Parent.Util.Guard)

local MonetizationService = {}

function MonetizationService:Init(services)
	self.Services = services
	self.Rng = Random.new()
	self.PassById = {}
	self.ProductById = {}
	for key, pass in ShopConfig.Passes do
		if pass.Id > 0 then
			self.PassById[pass.Id] = key
		end
	end
	for key, product in ShopConfig.Products do
		if product.Id > 0 then
			self.ProductById[product.Id] = key
		end
	end
end

function MonetizationService:GrantPass(session, key: string)
	if not ShopConfig.Passes[key] or session.Passes[key] then
		return
	end
	session.Passes[key] = true
	session.PetMultCache = nil
	session.AttrDirty = true
	Session.MarkDirty(session, "Passes", "Pets", "Rates", "Cosmetics")
	local pass = ShopConfig.Passes[key]
	Session.Notify(session, "Big", pass.Icon .. " " .. string.upper(pass.Name) .. " UNLOCKED! Thank you! 💛", { Sound = "Reward" })
	if key == "VIP" and session.Data.Auras.Equipped == "" then
		session.Data.Auras.Equipped = "Royal"
	end
end

function MonetizationService:LoadPasses(player: Player, session)
	local threads = 0
	for key, pass in ShopConfig.Passes do
		if pass.Id > 0 then
			threads += 1
			task.spawn(function()
				for _ = 1, 2 do
					local ok, owns = pcall(function()
						return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
					end)
					if ok then
						session.Passes[key] = owns == true
						break
					end
					task.wait(1)
				end
				threads -= 1
			end)
		end
	end
	local started = os.clock()
	while threads > 0 and os.clock() - started < 8 do
		task.wait(0.1)
	end
	-- Studio test purchases survive respawns in the same play session
	local studio = self.StudioPasses and self.StudioPasses[player.UserId]
	if studio then
		for key in studio do
			session.Passes[key] = true
		end
	end
end

-- Applies a product grant. Returns true if applied.
function MonetizationService:ApplyProduct(session, key: string): boolean
	local product = ShopConfig.Products[key]
	if not product then
		return false
	end
	local world = self.Services.PlayerService:World()
	if product.Grant.Kind == "Rebirth" then
		Growth.Rebirth(session, world, true)
		Session.Notify(session, "Big", "♻️ INSTANT REBIRTH! Thank you! 💛", { Sound = "Reward" })
	else
		local labels = Rewards.Grant(session, product.Grant, world, self.Rng)
		Session.Notify(session, "Reward", "💛 Thank you!  " .. table.concat(labels, "  "), { Sound = "Reward" })
	end
	Rewards.CheckAchievements(session)
	return true
end

function MonetizationService:ProcessReceipt(info)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local session = player and self.Services.PlayerService:Get(player)
	if not session then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- will be retried when they rejoin
	end
	local receiptId = tostring(info.PurchaseId)
	if table.find(session.Data.Receipts, receiptId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key = self.ProductById[info.ProductId]
	if not key then
		warn("[Monetization] unknown product " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	self:ApplyProduct(session, key)
	table.insert(session.Data.Receipts, receiptId)
	while #session.Data.Receipts > Defaults.MAX_RECEIPTS do
		table.remove(session.Data.Receipts, 1)
	end
	if self.Services.DataService:Save(session, false) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MonetizationService:Start()
	MarketplaceService.ProcessReceipt = function(info)
		return self:ProcessReceipt(info)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local key = self.PassById[passId]
		local session = self.Services.PlayerService:Get(player)
		if key and session then
			self:GrantPass(session, key)
			Pets.Validate(session)
		end
	end)

	-- Studio only: test unconfigured (Id = 0) passes and products for free
	self.StudioPasses = {}
	Guard.On("StudioPurchase", 2, function(session, player, kind, key)
		if not RunService:IsStudio() or type(key) ~= "string" then
			return
		end
		if kind == "Pass" and ShopConfig.Passes[key] then
			self.StudioPasses[player.UserId] = self.StudioPasses[player.UserId] or {}
			self.StudioPasses[player.UserId][key] = true
			self:GrantPass(session, key)
		elseif kind == "Product" and ShopConfig.Products[key] then
			self:ApplyProduct(session, key)
		end
	end)
end

return MonetizationService
