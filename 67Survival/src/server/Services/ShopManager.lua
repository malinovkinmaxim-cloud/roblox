--[[
	ShopManager - spending between runs:
	  coins     -> permanent upgrades, cosmetics (AFK camp slots: AfkManager)
	  fragments -> heroes and new abilities (both can also come from achievements)
	  CHIPS     -> premium items and boss relics (shared/ItemData.lua): an unlock adds the item
	               to the loot of runs, it still has to be found (and levelled) in a run
	and choosing: hero, starting ability, loadouts (1 slot, 3 with the Extra Loadout pass),
	equipped cosmetics. Codes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local Net = require(Shared.Net)
local MetaData = require(Shared.MetaData)
local HeroData = require(Shared.HeroData)
local WeaponData = require(Shared.WeaponData)
local CosmeticData = require(Shared.CosmeticData)
local ItemData = require(Shared.ItemData)

local Guard = require(script.Parent.Parent.Util.Guard)
local Codes = require(script.Parent.Parent.Data.Codes)

local ShopManager = {}

function ShopManager:Init(services)
	self.Services = services
end

-- the lobby only: changing things mid-run could change a running build
function ShopManager:Session(player: Player)
	local session = self.Services.PlayerManager:Get(player)
	if not session or self.Services.GameManager:GetRun(player) then
		return nil
	end
	return session
end

function ShopManager:BuyMeta(player: Player, key: string)
	local session = self:Session(player)
	local def = MetaData.ByKey[key]
	if not session or not def then
		return
	end
	local level = session.Data.Meta[key] or 0
	local cost = MetaData.Cost(key, level)
	local PM = self.Services.PlayerManager
	if not cost then
		PM:Notify(player, def.Name .. " is maxed!", "Error")
		return
	end
	if session.Data.Coins < cost then
		PM:Notify(player, "Not enough coins", "Error")
		return
	end
	session.Data.Coins -= cost
	session.Data.Meta[key] = level + 1
	PM:Notify(player, string.format("%s upgraded to level %d", def.Name, level + 1), "Success")
	PM:Sync(player)
end

---------------------------------------------------------------------------
-- heroes & abilities (fragments)
---------------------------------------------------------------------------
local function spendFragments(self, player: Player, session, cost: number?): boolean
	local PM = self.Services.PlayerManager
	if not cost then
		PM:Notify(player, "Unlock it through its achievement", "Error")
		return false
	end
	if session.Data.Fragments < cost then
		PM:Notify(player, string.format("Needs %d fragments (you have %d)", cost, session.Data.Fragments), "Error")
		return false
	end
	session.Data.Fragments -= cost
	return true
end

function ShopManager:UnlockHero(player: Player, key: string)
	local session = self:Session(player)
	local def = HeroData.ByKey[key]
	if not session or not def or session.Data.Heroes[key] then
		return
	end
	if not spendFragments(self, player, session, def.Unlock.Fragments) then
		return
	end
	session.Data.Heroes[key] = true
	session.Data.Selected = key
	local loadout = session.Data.Loadouts[session.Data.Loadout]
	loadout.Hero = key
	local PM = self.Services.PlayerManager
	PM:Notify(player, "Unlocked: " .. def.Name, "Unlock")
	self.Services.RewardManager:CheckAchievements(session)
	PM:Sync(player)
	self.Services.CharacterManager:Refresh(player)
end

function ShopManager:SelectHero(player: Player, key: string)
	local session = self:Session(player)
	if not session or not session.Data.Heroes[key] then
		return
	end
	session.Data.Selected = key
	session.Data.Loadouts[session.Data.Loadout].Hero = key
	self.Services.PlayerManager:Sync(player)
	self.Services.CharacterManager:Refresh(player)
end

function ShopManager:UnlockWeapon(player: Player, key: string)
	local session = self:Session(player)
	local def = WeaponData.ByKey[key]
	-- (premium abilities are bought with Robux: Services/MonetizationManager)
	if not session or not def or def.Evolution or session.Data.Weapons[key] or def.Unlock.Secret or def.Premium then
		return
	end
	if not spendFragments(self, player, session, def.Unlock.Fragments) then
		return
	end
	session.Data.Weapons[key] = true
	self.Services.PlayerManager:Notify(player, "Unlocked: " .. def.Name, "Unlock")
	self.Services.PlayerManager:Sync(player)
end

---------------------------------------------------------------------------
-- items (CHIPS)
---------------------------------------------------------------------------
function ShopManager:UnlockItem(player: Player, key: string)
	local session = self:Session(player)
	local def = ItemData.ByKey[key]
	if not session or not def or not ItemData.NeedsUnlock(def) or session.Data.ItemUnlocks[key] then
		return
	end
	local PM = self.Services.PlayerManager
	local price = def.Price or 0
	if price <= 0 then
		return
	end
	if session.Data.Chips < price then
		PM:Notify(player, string.format("Needs %d CHIPS (you have %d)", price, session.Data.Chips), "Error")
		return
	end
	session.Data.Chips -= price
	session.Data.ItemUnlocks[key] = true
	PM:Notify(player, "Unlocked: " .. def.Name .. " - it can now drop in runs", "Unlock")
	self.Services.RewardManager:CheckAchievements(session)
	PM:Sync(player)
end

-- the starting ability of the active loadout ("" = the hero's own)
function ShopManager:SetStartWeapon(player: Player, key: string)
	local session = self:Session(player)
	if not session then
		return
	end
	if key ~= "" and not (WeaponData.IsBase(key) and session.Data.Weapons[key]) then
		return
	end
	session.Data.StartWeapon = key
	session.Data.Loadouts[session.Data.Loadout].StartWeapon = key
	self.Services.PlayerManager:Sync(player)
end

function ShopManager:SelectLoadout(player: Player, index: number)
	local session = self:Session(player)
	if not session then
		return
	end
	local slots = if self.Services.MonetizationManager:HasPass(player, "ExtraLoadout") then 3 else 1
	if index > slots then
		self.Services.MonetizationManager:PromptPass(player, "ExtraLoadout")
		return
	end
	local data = session.Data
	data.Loadout = index
	local loadout = data.Loadouts[index]
	if loadout.Hero == "" or not data.Heroes[loadout.Hero] then
		loadout.Hero = data.Selected
	end
	data.Selected = loadout.Hero
	data.StartWeapon = loadout.StartWeapon
	self.Services.PlayerManager:Sync(player)
	self.Services.CharacterManager:Refresh(player)
end

---------------------------------------------------------------------------
-- cosmetics
---------------------------------------------------------------------------
function ShopManager:BuyCosmetic(player: Player, id: string)
	local session = self.Services.PlayerManager:Get(player)
	local def = CosmeticData.ById[id]
	local PM = self.Services.PlayerManager
	if not session or not def or session.Data.Cosmetics.Owned[id] then
		return
	end
	if not def.Cost then
		PM:Notify(player, "This one is earned, not bought", "Error")
		return
	end
	if session.Data.Coins < def.Cost then
		PM:Notify(player, "Not enough coins", "Error")
		return
	end
	session.Data.Coins -= def.Cost
	session.Data.Cosmetics.Owned[id] = true
	session.Data.Cosmetics.Equipped[def.Category] = id
	PM:Notify(player, "Unlocked: " .. def.Name, "Unlock")
	PM:Sync(player)
	self.Services.CharacterManager:Refresh(player)
end

function ShopManager:EquipCosmetic(player: Player, id: string)
	local session = self.Services.PlayerManager:Get(player)
	local def = CosmeticData.ById[id]
	if not session or not def or not session.Data.Cosmetics.Owned[id] then
		return
	end
	session.Data.Cosmetics.Equipped[def.Category] = id
	session.Data.Cosmetics.New[id] = nil
	self.Services.PlayerManager:Sync(player)
	self.Services.CharacterManager:Refresh(player)
end

-- the player looked at the new cosmetics (clears the NEW badges)
function ShopManager:SeenCosmetics(player: Player)
	local session = self.Services.PlayerManager:Get(player)
	if session and next(session.Data.Cosmetics.New) then
		session.Data.Cosmetics.New = {}
		self.Services.PlayerManager:Sync(player)
	end
end

---------------------------------------------------------------------------
-- codes
---------------------------------------------------------------------------
function ShopManager:RedeemCode(player: Player, text: string)
	local session = self.Services.PlayerManager:Get(player)
	if not session then
		return
	end
	local PM = self.Services.PlayerManager
	local code = string.upper((string.gsub(text, "%s", "")))
	local reward = Codes[code]
	if not reward then
		PM:Notify(player, "That code doesn't exist", "Error")
		return
	end
	if session.Data.RedeemedCodes[code] then
		PM:Notify(player, "Code already redeemed", "Error")
		return
	end
	session.Data.RedeemedCodes[code] = true
	self.Services.RewardManager:GiveCoins(session, reward.Coins or 0)
	self.Services.RewardManager:GiveFragments(session, reward.Fragments or 0)
	PM:Notify(player, "CODE: " .. reward.Text, "Reward")
	PM:Sync(player)
end

function ShopManager:Start()
	local function key(handler)
		return function(player, k)
			if Guard.Str(k, 40) then
				handler(self, player, k)
			end
		end
	end
	Guard.Connect(Net.Event("BuyMeta"), { Rate = 4, Burst = 6 }, key(ShopManager.BuyMeta))
	Guard.Connect(Net.Event("UnlockHero"), { Rate = 2, Burst = 3 }, key(ShopManager.UnlockHero))
	Guard.Connect(Net.Event("SelectHero"), { Rate = 4, Burst = 6 }, key(ShopManager.SelectHero))
	Guard.Connect(Net.Event("UnlockWeapon"), { Rate = 2, Burst = 3 }, key(ShopManager.UnlockWeapon))
	Guard.Connect(Net.Event("UnlockItem"), { Rate = 2, Burst = 3 }, key(ShopManager.UnlockItem))
	Guard.Connect(Net.Event("SetStartWeapon"), { Rate = 2, Burst = 4 }, function(player, k)
		if Guard.Str(k, 40) or k == "" then
			self:SetStartWeapon(player, k)
		end
	end)
	Guard.Connect(Net.Event("SelectLoadout"), { Rate = 2, Burst = 4 }, function(player, index)
		local i = Guard.Int(index, 1, 3)
		if i then
			self:SelectLoadout(player, i)
		end
	end)
	Guard.Connect(Net.Event("BuyCosmetic"), { Rate = 2, Burst = 3 }, key(ShopManager.BuyCosmetic))
	Guard.Connect(Net.Event("EquipCosmetic"), { Rate = 4, Burst = 6 }, key(ShopManager.EquipCosmetic))
	Guard.Connect(Net.Event("SeenCosmetics"), { Rate = 1, Burst = 2 }, function(player)
		self:SeenCosmetics(player)
	end)
	Guard.Connect(Net.Event("RedeemCode"), { Rate = 0.5, Burst = 3 }, function(player, code)
		if Guard.Str(code, 24) then
			self:RedeemCode(player, code)
		end
	end)
end

return ShopManager
