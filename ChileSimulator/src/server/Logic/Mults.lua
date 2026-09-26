--[[
	Mults - builds the multiplier set for a session from everything the server knows:
	rebirths, zone (verified), pets, boosts, current server event, game passes, gem upgrades.

	world = { Now = unix seconds, Event = EventConfig entry | nil }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)

local Pets = require(script.Parent.Pets)
local Boosts = require(script.Parent.Boosts)

local Mults = {}

-- includeTemporary = false ignores boosts and events (used to size coin rewards)
function Mults.Get(session, world, includeTemporary: boolean?)
	local temp = includeTemporary ~= false
	local boostHeight, boostCoins = 1, 1
	if temp then
		boostHeight, boostCoins = Boosts.Multipliers(session)
	end
	local event = temp and world and world.Event or nil
	return Formulas.Multipliers({
		Rebirths = session.Data.Rebirths,
		ZoneIndex = session.ZoneIndex,
		PetMult = Pets.Multiplier(session),
		BoostHeight = boostHeight,
		BoostCoins = boostCoins,
		EventHeight = event and event.Height or 1,
		EventCoins = event and event.Coins or 1,
		Passes = session.Passes,
		Gem = session.Data.Gem,
		VIPArea = session.InVIPArea == true and session.Passes.VIP == true,
	})
end

-- Values the HUD shows ("+12 cm per tap", "+3 coins per tap", "+5 cm/s")
function Mults.Rates(session, world)
	local m = Mults.Get(session, world)
	local data = session.Data
	local tapCount = world and world.Event and world.Event.TapCount or 1
	return {
		TapGain = Formulas.TapGain(data.TapLevel, m) * tapCount,
		TapCoins = Formulas.TapCoins(data.TapLevel, m, data.Height) * tapCount,
		AutoGain = Formulas.AutoGain(data.AutoLevel, m),
		AutoCoins = Formulas.AutoCoins(data.AutoLevel, m, data.Height),
		Rebirth = m.Rebirth,
		Zone = m.Zone,
		Pet = m.Pet,
		Height = m.TapHeight,
		Coins = m.Coins,
	}
end

return Mults
