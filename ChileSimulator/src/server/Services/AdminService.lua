--[[
	AdminService - testing tools. Only works in Studio, for the place owner, or for
	Config.ADMIN_USER_IDS. The client shows an ADMIN section in Settings for these players.

	Commands (remote "Admin"):  coins | gems | height | rebirth | event <id> | chest |
	                            boosts | pet <id> | pass <key> | reset
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local EventConfig = require(Shared.EventConfig)
local BoostConfig = require(Shared.BoostConfig)
local PetConfig = require(Shared.PetConfig)
local ShopConfig = require(Shared.ShopConfig)
local Num = require(Shared.Util.Num)

local Logic = script.Parent.Parent.Logic
local Session = require(Logic.Session)
local Growth = require(Logic.Growth)
local Boosts = require(Logic.Boosts)
local Pets = require(Logic.Pets)
local Defaults = require(Logic.Defaults)
local Guard = require(script.Parent.Parent.Util.Guard)

local AdminService = {}

function AdminService:Init(services)
	self.Services = services
end

function AdminService:IsAdmin(userId: number): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId == userId then
		return true
	end
	return table.find(Config.ADMIN_USER_IDS, userId) ~= nil
end

function AdminService:Run(session, player: Player, command: string, arg: any)
	local data = session.Data
	local world = self.Services.PlayerService:World()
	if command == "coins" then
		data.Coins = Num.Add(data.Coins, math.max(1e6, data.Coins * 10))
	elseif command == "gems" then
		data.Gems = Num.Add(data.Gems, 1000)
	elseif command == "height" then
		Growth.AddHeight(session, math.max(data.Height * 9, 10000), world)
	elseif command == "rebirth" then
		Growth.Rebirth(session, world, true)
	elseif command == "event" then
		local id = if type(arg) == "string" and EventConfig.Events[arg] then arg else self.Services.EventService:Pick()
		self.Services.EventService:StartEvent(id)
	elseif command == "chest" then
		self.Services.RewardService:SpawnChest()
	elseif command == "boosts" then
		for id in BoostConfig.Boosts do
			Boosts.Add(session, id, 1)
		end
	elseif command == "pet" then
		local id = if type(arg) == "string" and PetConfig.Pets[arg] then arg else "TallNoob"
		Pets.Give(session, id)
		Session.Effect(session, "PetReward", { Id = id })
	elseif command == "pass" then
		if type(arg) == "string" and ShopConfig.Passes[arg] then
			self.Services.MonetizationService:GrantPass(session, arg)
		end
	elseif command == "reset" then
		session.Data = Defaults.New()
		session.PetMultCache = nil
		session.RecordArmed = false
		session.AttrDirty = true
		session.Dirty.All = true
		Session.Notify(session, "Info", "Data reset")
		return
	else
		return
	end
	session.AttrDirty = true
	Session.MarkDirty(session, "Stats", "Rates", "Pets", "Boosts")
	Session.Notify(session, "Info", "[admin] " .. command .. " ✓")
	print(string.format("[Admin] %s ran %s %s", player.Name, command, tostring(arg)))
end

function AdminService:Start()
	Guard.On("Admin", 5, function(session, player, command, arg)
		if type(command) ~= "string" or not self:IsAdmin(player.UserId) then
			return
		end
		self:Run(session, player, command, arg)
	end)
end

return AdminService
