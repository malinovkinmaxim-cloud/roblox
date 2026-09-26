--[[
	Full balance simulation on the REAL server logic (Logic/Session, Growth, Pets, Boosts,
	Rewards, AutoPlay) - pets, gem upgrades, boosts from rewards, random server events and
	one-button autopilot included. Run from ChileSimulator/:

	    lune run tests/balance_full.luau [minutes] [tapsPerSecond] [seed]

	Complements tests/balance.luau (baseline: tapping + upgrades only). Used by tests/run.luau
	to make sure extra multipliers speed the game up but never make it explode.
]]

local process = require("@lune/process")
local H = require("./harness")

local Config = H.Require("ReplicatedStorage.Shared.Config")
local ZoneConfig = H.Require("ReplicatedStorage.Shared.ZoneConfig")
local EventConfig = H.Require("ReplicatedStorage.Shared.EventConfig")
local Format = H.Require("ReplicatedStorage.Shared.Util.Format")
local Defaults = H.Require("ServerScriptService.Server.Logic.Defaults")
local Session = H.Require("ServerScriptService.Server.Logic.Session")
local Growth = H.Require("ServerScriptService.Server.Logic.Growth")
local Boosts = H.Require("ServerScriptService.Server.Logic.Boosts")
local AutoPlay = H.Require("ServerScriptService.Server.Logic.AutoPlay")

local NOW = 1_780_000_000

local Sim = {}

function Sim.Run(minutes: number, tps: number, seed: number, log: boolean)
	local rng = H.Random.new(seed)
	local session = Session.new(1, "Sim", Defaults.New(), 0)
	local reach, rebirthTimes = {}, {}
	local thresholds = { 10, 100, 1e3, 1e4, 1e6, 1e9, 1e12, 1e15 }
	local event, eventEnds = nil, 0
	-- players join servers that are already running: the first event comes at a random moment
	local nextEvent = rng:NextNumber(30, EventConfig.MaxInterval)
	local readySince = nil
	local lines = {}
	local function note(t, text)
		if log then
			table.insert(lines, string.format("  %8s  %s", Format.Time(t), text))
		end
	end

	for t = 1, minutes * 60 do
		-- server events, same timing and weights as EventService
		if event and t >= eventEnds then
			event = nil
			nextEvent = t + rng:NextNumber(EventConfig.MinInterval, EventConfig.MaxInterval)
		elseif not event and t >= nextEvent then
			local total = 0
			for _, id in EventConfig.Order do
				total += EventConfig.Events[id].Weight
			end
			local r = rng:NextNumber(0, total)
			for _, id in EventConfig.Order do
				r -= EventConfig.Events[id].Weight
				if r <= 0 then
					event = EventConfig.Events[id]
					break
				end
			end
			event = event or EventConfig.Events.MegaGrowth
			eventEnds = t + event.Duration
		end
		local world = { Now = NOW + t, Event = event }
		session.ZoneIndex = ZoneConfig.HighestUnlocked(session.Data.BestHeight)
		Growth.Tap(session, tps, world, t)
		Boosts.Tick(session, 1)
		Growth.Tick(session, 1, world, t)
		AutoPlay.Tick(session, world, rng, t)
		-- the one-button player presses the purple REBIRTH button ~1 s after it appears
		if Growth.CanRebirth(session) then
			readySince = readySince or t
			if t - readySince >= 1 then
				Growth.Rebirth(session, world)
				readySince = nil
				table.insert(rebirthTimes, t)
				note(t, string.format("REBIRTH %d", session.Data.Rebirths))
			end
		else
			readySince = nil
		end
		for _, m in thresholds do
			if not reach[m] and session.Data.BestHeight >= m * 100 then
				reach[m] = t
				note(t, "reached " .. Format.Length(m * 100))
			end
		end
		table.clear(session.Out)
	end
	local pets = 0
	for _ in session.Data.Pets do
		pets += 1
	end
	return {
		Session = session,
		Reach = reach,
		Thresholds = thresholds,
		RebirthTimes = rebirthTimes,
		Pets = pets,
		Lines = lines,
	}
end

-- smallest gap between two rebirths after `after` seconds (runaway detector)
function Sim.MinGap(result, after: number): number
	local best = math.huge
	local times = result.RebirthTimes
	for i = 2, #times do
		if times[i - 1] >= after then
			best = math.min(best, times[i] - times[i - 1])
		end
	end
	return best
end

if not _G.BALANCE_QUIET then
	local minutes = tonumber(process.args[1]) or 240
	local tps = tonumber(process.args[2]) or 6
	local seed = tonumber(process.args[3]) or 1
	local r = Sim.Run(minutes, tps, seed, true)
	for _, line in r.Lines do
		print(line)
	end
	local s = r.Session
	print(string.format(
		"\nafter %d min: best %s, %d rebirths, tap level %d, auto level %d, %d pets, pet bonus %s, min rebirth gap after 30 min: %ss",
		minutes,
		Format.Length(s.Data.BestHeight),
		s.Data.Rebirths,
		s.Data.TapLevel,
		s.Data.AutoLevel,
		r.Pets,
		Format.Mult(s.PetMultCache or 1),
		tostring(Sim.MinGap(r, 1800))
	))
end

return Sim
