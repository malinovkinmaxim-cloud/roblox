--[[
	ShopManager - spending BRAIN COINS between runs: permanent upgrades, characters and
	weapons (each can also be unlocked for free through its achievement), character
	selection, starting weapon (Extra Loadout pass).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local Net = require(Shared.Net)
local MetaData = require(Shared.MetaData)
local CharacterData = require(Shared.CharacterData)
local WeaponData = require(Shared.WeaponData)

local Guard = require(script.Parent.Parent.Util.Guard)

local ShopManager = {}

function ShopManager:Init(services)
	self.Services = services
end

local function spend(session, cost: number): boolean
	if session.Data.Coins < cost then
		return false
	end
	session.Data.Coins -= cost
	return true
end

-- the lobby only: buying mid-run could change a running build
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
	if not spend(session, cost) then
		PM:Notify(player, "Not enough coins", "Error")
		return
	end
	session.Data.Meta[key] = level + 1
	PM:Notify(player, string.format("%s %s -> level %d", def.Icon, def.Name, level + 1), "Success")
	PM:Sync(player)
end

function ShopManager:UnlockCharacter(player: Player, key: string)
	local session = self:Session(player)
	local def = CharacterData.ByKey[key]
	local PM = self.Services.PlayerManager
	if not session or not def or session.Data.Characters[key] then
		return
	end
	local cost = def.Unlock.Cost
	if not cost then
		PM:Notify(player, "Unlock it through its achievement", "Error")
		return
	end
	if not spend(session, cost) then
		PM:Notify(player, "Not enough coins", "Error")
		return
	end
	session.Data.Characters[key] = true
	session.Data.Selected = key
	PM:Notify(player, "UNLOCKED: " .. def.Icon .. " " .. def.Name, "Unlock")
	PM:Sync(player)
	self.Services.CharacterManager:Refresh(player)
end

function ShopManager:SelectCharacter(player: Player, key: string)
	local session = self.Services.PlayerManager:Get(player)
	if not session or not session.Data.Characters[key] or self.Services.GameManager:GetRun(player) then
		return
	end
	session.Data.Selected = key
	self.Services.PlayerManager:Sync(player)
	self.Services.CharacterManager:Refresh(player)
end

function ShopManager:UnlockWeapon(player: Player, key: string)
	local session = self:Session(player)
	local def = WeaponData.ByKey[key]
	local PM = self.Services.PlayerManager
	if not session or not def or session.Data.Weapons[key] then
		return
	end
	local cost = def.Unlock.Cost
	if not cost then
		return
	end
	if not spend(session, cost) then
		PM:Notify(player, "Not enough coins", "Error")
		return
	end
	session.Data.Weapons[key] = true
	PM:Notify(player, "UNLOCKED: " .. def.Icon .. " " .. def.Name, "Unlock")
	PM:Sync(player)
end

function ShopManager:SetStartWeapon(player: Player, key: string)
	local session = self:Session(player)
	if not session then
		return
	end
	if key ~= "" and not (WeaponData.ByKey[key] and session.Data.Weapons[key]) then
		return
	end
	if key ~= "" and not self.Services.MonetizationManager:HasPass(player, "ExtraLoadout") then
		self.Services.MonetizationManager:PromptPass(player, "ExtraLoadout")
		return
	end
	session.Data.StartWeapon = key
	self.Services.PlayerManager:Sync(player)
end

function ShopManager:Start()
	Guard.Connect(Net.Event("BuyMeta"), { Rate = 4, Burst = 6 }, function(player, key)
		if Guard.Str(key, 32) then
			self:BuyMeta(player, key)
		end
	end)
	Guard.Connect(Net.Event("UnlockCharacter"), { Rate = 2, Burst = 3 }, function(player, key)
		if Guard.Str(key, 32) then
			self:UnlockCharacter(player, key)
		end
	end)
	Guard.Connect(Net.Event("SelectCharacter"), { Rate = 4, Burst = 6 }, function(player, key)
		if Guard.Str(key, 32) then
			self:SelectCharacter(player, key)
		end
	end)
	Guard.Connect(Net.Event("UnlockWeapon"), { Rate = 2, Burst = 3 }, function(player, key)
		if Guard.Str(key, 32) then
			self:UnlockWeapon(player, key)
		end
	end)
	Guard.Connect(Net.Event("SetStartWeapon"), { Rate = 2, Burst = 4 }, function(player, key)
		if Guard.Str(key, 32) then
			self:SetStartWeapon(player, key)
		end
	end)
end

return ShopManager
