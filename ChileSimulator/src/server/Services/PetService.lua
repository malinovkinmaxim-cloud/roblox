--[[
	PetService - hatch / equip / delete remotes.
	RNG runs on the server; the client only plays the reveal animation for the result.
	You must stand next to the egg to hatch it (checked against the egg stand position).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.PetConfig)

local Logic = script.Parent.Parent.Logic
local Pets = require(Logic.Pets)
local Session = require(Logic.Session)
local Rewards = require(Logic.Rewards)
local Guard = require(script.Parent.Parent.Util.Guard)

local HATCH_RANGE = 40

local PetService = {}

function PetService:Init(services)
	self.Services = services
	self.Rng = Random.new()
end

-- server-wide "X hatched a LEGENDARY Unicorn!" (Legendary and rarer)
function PetService:AnnounceHatch(player: Player, session, results)
	local PlayerService = self.Services.PlayerService
	for _, r in results do
		local def = PetConfig.Pets[r.Id]
		local order = PetConfig.Rarities[def.Rarity].Order
		if order >= PetConfig.Rarities.Legendary.Order then
			local big = def.Rarity == "Secret" or def.Rarity == "Mythic"
			PlayerService:NotifyAll(
				if big then "Big" else "Info",
				string.format("%s %s hatched a %s %s!", if big then "🚨" else "🎉", player.DisplayName, string.upper(def.Rarity), def.Name),
				{ Sound = if def.Rarity == "Secret" then "PetSecret" else "PetLegendary", Delay = if session.Passes.FasterHatch then 1 else 3 }
			)
		end
	end
end

function PetService:Start()
	local WorldService = self.Services.WorldService

	Guard.On("Hatch", 2, function(session, player, eggId, count)
		if type(eggId) ~= "string" then
			return
		end
		local eggPos = WorldService:EggPosition(eggId)
		local root = WorldService:RootPosition(player)
		if not eggPos or not root or (root - eggPos).Magnitude > HATCH_RANGE then
			Session.Notify(session, "Error", "Walk up to the egg to hatch it!")
			return
		end
		local results, err = Pets.Hatch(session, eggId, count, self.Rng)
		if not results then
			Session.Notify(session, "Error", err or "Can't hatch")
			return
		end
		Session.Effect(session, "Hatch", {
			Egg = eggId,
			Results = results,
			Fast = session.Passes.FasterHatch == true,
		})
		self:AnnounceHatch(player, session, results)
		Rewards.CheckAchievements(session)
	end)

	Guard.On("EquipPet", 10, function(session, _player, uid, equip)
		if type(uid) ~= "string" or type(equip) ~= "boolean" then
			return
		end
		local ok, err = Pets.Equip(session, uid, equip)
		if not ok and err then
			Session.Notify(session, "Error", err)
		end
	end)

	Guard.On("EquipBest", 2, function(session)
		Pets.EquipBest(session)
	end)

	Guard.On("DeletePet", 10, function(session, _player, uid)
		if type(uid) ~= "string" then
			return
		end
		Pets.Delete(session, uid)
	end)
end

return PetService
