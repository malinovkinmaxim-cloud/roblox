--[[
	BossDirector - WHEN the bosses come. The only place bosses are started (no random extra
	bosses): shared/BossData.lua Slots and Main.

	  run starts   every slot draws its boss from its pool (tests can force them: BossPicks)
	  At - lead    BOSS n is announced at the lair of its zone (marker, arrow, minimap);
	               bosses nobody is fighting leave with their loot
	  At           it spawns there and waits for you (Sim/MiniBosses: lair rules)
	  15:00        THE FINAL ONE appears in the 67 ARENA (the centre of the map)

	lead = BossData.WarnLead (+ the Compass item). The 67 BOSS event crowns the boss that is out
	(or the next one): tougher, double loot.
	run.BossPlan[slot] = the BossData key of each slot; run.BossNext = the next slot to announce.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local ArenaData = require(Shared.ArenaData)
local BossData = require(Shared.BossData)

local MiniBosses = require(script.Parent.MiniBosses)

local BossDirector = {}

local MAIN = BossData.Main

-- picks: forced BossData keys by slot (tests / debug)
function BossDirector.Init(run, picks: { string }?)
	local plan = {}
	for i, slot in BossData.Slots do
		local forced = picks and picks[i]
		plan[i] = if forced and table.find(slot.Pool, forced) then forced else slot.Pool[run.Rng:NextInteger(1, #slot.Pool)]
	end
	run.BossPlan = plan
	run.BossNext = 1
	run.MainAnnounced = false
	run.CrownNext = false
end

-- seconds of warning before a boss (the Compass announces it earlier)
function BossDirector.Lead(run): number
	local compass = run.IP and run.IP.Compass
	return BossData.WarnLead + (if compass then compass.Lead or 0 else 0)
end

-- the arena of THE FINAL ONE
local ARENA_LAIR = { Key = "Arena", X = MAIN.X, Z = MAIN.Z, R = MAIN.ArenaR, Main = true }

function BossDirector.Step(run, EM)
	local now = run.Time
	local lead = BossDirector.Lead(run)
	-- a debug time jump went past a slot: that boss is skipped (never late, never twice)
	while BossData.Slots[run.BossNext] and now > BossData.Slots[run.BossNext].At + BossData.WarnLead do
		run.BossNext += 1
	end
	local slot = BossData.Slots[run.BossNext]
	if slot and now >= slot.At - lead then
		run.BossNext += 1
		MiniBosses.LeaveIdle(run, EM)
		local def = BossData.Get(run.BossPlan[slot.Index])
		local lair = ArenaData.LairOfZone[slot.Zone]
		local crowned = run.CrownNext
		run.CrownNext = false
		MiniBosses.Announce(run, def, slot.Index, lair.X, lair.Z, lair, slot.At, crowned)
	end
	if not run.MainAnnounced and now >= MAIN.At - BossData.WarnLead and now <= MAIN.At + 60 then
		run.MainAnnounced = true
		MiniBosses.LeaveIdle(run, EM)
		run.Map.MainOut = true
		MiniBosses.Announce(run, BossData.Get(MAIN.Key), 5, MAIN.X, MAIN.Z, ARENA_LAIR, MAIN.At)
	end
	MiniBosses.StepEncounters(run, EM)
end

-- 67 BOSS event: crown the boss that is out now, else the next one
function BossDirector.Crown(run): string?
	for _, enc in run.Map.Encounters do
		if not enc.Main and not enc.Crowned then
			MiniBosses.Crown(run, enc)
			return enc.Def.Title
		end
	end
	if run.BossNext <= #BossData.Slots then
		run.CrownNext = true
		return BossData.Get(run.BossPlan[run.BossNext]).Title
	end
	return nil
end

-- debug: announce a slot's boss now (it spawns after the warning)
function BossDirector.Force(run, slotIndex: number, key: string?, EM)
	local slot = BossData.Slots[slotIndex]
	if not slot then
		return false
	end
	local def = BossData.ByKey[key or ""] or BossData.Get(run.BossPlan[slotIndex])
	local lair = ArenaData.LairOfZone[slot.Zone]
	MiniBosses.Announce(run, def, slotIndex, lair.X, lair.Z, lair, run.Time + 3)
	local _ = EM
	return true
end

-- debug: THE FINAL ONE now
function BossDirector.ForceMain(run)
	if run.MainAnnounced then
		return false
	end
	run.MainAnnounced = true
	run.Map.MainOut = true
	MiniBosses.Announce(run, BossData.Get(MAIN.Key), 5, MAIN.X, MAIN.Z, ARENA_LAIR, run.Time + 3)
	return true
end

return BossDirector
