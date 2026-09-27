--[[
	WaveManager - the run director: follows the timeline (shared/WaveData.lua), spawns the
	horde around the player, bursts, bosses, loot crates, rare random events (67 EVENT,
	GOOBER RAIN, NPC INVASION, SIGMA MOMENT, BRAINROT STORM, WHY IS HE RUNNING?) and secrets.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local EnemyData = require(Shared.EnemyData)
local WaveData = require(Shared.WaveData)
local Protocol = require(Shared.Protocol)

local EnemyManager = require(script.Parent.EnemyManager)
local CombatManager = require(script.Parent.CombatManager)

local WaveManager = {}

local cos, sin, min = math.cos, math.sin, math.min
local TAU = math.pi * 2

local function pickWeighted(rng, entries: { any }, weightOf: (any) -> number)
	local total = 0
	for _, entry in entries do
		total += weightOf(entry)
	end
	local r = rng:NextNumber(0, total)
	for _, entry in entries do
		r -= weightOf(entry)
		if r <= 0 then
			return entry
		end
	end
	return entries[#entries]
end

function WaveManager.Init(run, midBoss: string?)
	local rng = run.Rng
	local midBosses = EnemyData.MidBosses
	run.Wave = {
		Entry = 0,
		Acc = 0,
		NextEventAt = rng:NextNumber(WaveData.EventFirstAt[1], WaveData.EventFirstAt[2]),
		LastEvent = nil,
		EventUntil = 0,
		CrateAt = GameConfig.Drops.CrateEvery * 0.6,
		PendingBoss = nil,
		MidBoss = if midBoss and EnemyData.ByKey[midBoss] then midBoss else midBosses[rng:NextInteger(1, #midBosses)],
		Secret67Checked = false,
		StareDone = false,
		NPCSpawned = false,
		FirstSpawned = false,
		StormNext = 0,
		Invasion = nil,
		RainLeft = 0,
		RainNext = 0,
	}
	if run.Character == "SixSeven" then
		run.Wave.NextEventAt *= 0.7
	end
end

---------------------------------------------------------------------------
-- spawning
---------------------------------------------------------------------------
local function spawnKind(run, key: string)
	local x, z = EnemyManager.RingPoint(run, GameConfig.Arena.SpawnRadiusMin, GameConfig.Arena.SpawnRadiusMax)
	local w = run.Wave
	local luck = run.Stats.Luck
	local rng = run.Rng
	-- very rare specials replace a normal spawn
	if key == "Goober" and rng:NextNumber() < 1 / 500 * luck then
		return EnemyManager.Spawn(run, "GoldenGoober", x, z, { Golden = true })
	end
	if not w.NPCSpawned and run.Time > 120 and rng:NextNumber() < 1 / 3500 * luck then
		w.NPCSpawned = true
		return EnemyManager.Spawn(run, "TheNPC", x, z, { Force = true, NoScale = true })
	end
	if run.Time > 45 and rng:NextNumber() < 0.0005 * luck * (if run.Character == "SixSeven" then 2 else 1) then
		return EnemyManager.Spawn(run, "Goblin67", x, z, { Force = true, NoScale = true })
	end
	return EnemyManager.Spawn(run, key, x, z)
end

local function burst(run, b)
	if b.Kind == "Ring" then
		for i = 1, b.Count do
			local a = (i / b.Count) * TAU
			EnemyManager.Spawn(run, b.Key, run.PX + cos(a) * b.Radius, run.PZ + sin(a) * b.Radius, { Force = true })
		end
	elseif b.Kind == "Wall" then
		-- a line of enemies rushing in from one side
		local a = run.Rng:NextNumber(0, TAU)
		local cx, cz = run.PX + cos(a) * 60, run.PZ + sin(a) * 60
		local tx, tz = -sin(a), cos(a)
		for i = 1, b.Count do
			local off = (i - (b.Count + 1) / 2) * 2.4
			EnemyManager.Spawn(run, b.Key, cx + tx * off, cz + tz * off, { Force = true })
		end
	end
end

local function spawnBoss(run, key: string)
	local def = EnemyData.Get(key)
	local x, z = EnemyManager.RingPoint(run, 38, 46)
	EnemyManager.Spawn(run, key, x, z, { Force = true })
	run:Write("Fx", 0, x, z, 0, def.Radius * 3, 0, Protocol.Fx.Enrage)
end

---------------------------------------------------------------------------
-- random events
---------------------------------------------------------------------------
local EVENTS = {}

function EVENTS.GooberRain(run)
	run.Wave.RainLeft = 36
	run.Wave.RainNext = 0
end

function EVENTS.NPCInvasion(run)
	local a = run.Rng:NextNumber(0, TAU)
	local cx, cz = run.PX + cos(a) * 62, run.PZ + sin(a) * 62
	local dirX, dirZ = -cos(a), -sin(a)
	local tx, tz = -dirZ, dirX
	for row = 0, 2 do
		for i = 1, 16 do
			local off = (i - 8.5) * 3.2
			EnemyManager.Spawn(run, "NPC", cx + tx * off - dirX * row * 3.5, cz + tz * off - dirZ * row * 3.5, {
				Force = true,
				Behavior = "March",
				DirX = dirX,
				DirZ = dirZ,
				Life = 22,
			})
		end
	end
end

function EVENTS.SigmaMoment(run, e)
	run:AddBuff("Sigma", e.Duration)
end

function EVENTS.BrainrotStorm(run, e)
	run:AddBuff("Storm", e.Duration)
	run.Wave.StormNext = 0
end

function EVENTS.WhyRunning(run)
	local x, z = EnemyManager.RingPoint(run, 24, 30)
	EnemyManager.Spawn(run, "Runner", x, z, { Force = true, NoScale = true })
end

function EVENTS.Event67(run, e)
	local variant = pickWeighted(run.Rng, WaveData.Variants67, function(v)
		return v.Weight
	end)
	run.Result.Events67 += 1
	if variant.Key == "Shrink" then
		for _, en in run.Enemies do
			if not en.IsBoss and not en.Tiny and en.Def.Behavior ~= "Static" and run.Rng:NextNumber() < 0.67 then
				en.Tiny = true
				en.HP *= 0.34
				en.MaxHP *= 0.34
				en.Radius *= 0.6
				en.Speed *= 1.15
				run:Write("Shrink", en.Id)
			end
		end
		run:Write("Fx", 0, run.PX, run.PZ, 0, 60, 0, Protocol.Fx.Shrink)
	elseif variant.Key == "MoreXP" then
		run:AddBuff("XP67", e.Duration)
	elseif variant.Key == "Damage" then
		run:AddBuff("Damage67", e.Duration)
	else
		for i = 1, 3 do
			local x, z = EnemyManager.RingPoint(run, 22 + i * 3, 30 + i * 3)
			EnemyManager.Spawn(run, "Goblin67", x, z, { Force = true, NoScale = true })
		end
	end
	return variant
end

function WaveManager.TriggerEvent(run, key: string)
	local e = WaveData.EventByKey[key]
	if not e then
		return
	end
	local w = run.Wave
	w.LastEvent = key
	w.EventUntil = run.Time + e.Duration
	local variant = EVENTS[key](run, e)
	run:Event("RandomEvent", {
		Key = key,
		Title = e.Title,
		Sub = e.Sub,
		Duration = e.Duration,
		Variant = if variant then variant.Key else nil,
		VariantTitle = if variant then variant.Title else nil,
	})
end

local function stepEvents(run, dt: number)
	local w = run.Wave
	local now = run.Time

	-- ongoing effects
	if w.RainLeft > 0 then
		w.RainNext -= dt
		while w.RainNext <= 0 and w.RainLeft > 0 do
			w.RainNext += 0.16
			w.RainLeft -= 1
			local a = run.Rng:NextNumber(0, TAU)
			local r = run.Rng:NextNumber(10, 36)
			EnemyManager.Spawn(run, "Goober", run.PX + cos(a) * r, run.PZ + sin(a) * r, { FromSky = true, Force = true, Tiny = true })
		end
	end
	if run:Buff("Storm") then
		w.StormNext -= dt
		if w.StormNext <= 0 then
			w.StormNext = 0.45
			local target = CombatManager.Nearest(run, run.PX + run.Rng:NextNumber(-40, 40), run.PZ + run.Rng:NextNumber(-40, 40), 40)
			if target then
				run:Write("Fx", 0, target.X, target.Z, 0, 4, 0, Protocol.Fx.Storm)
				CombatManager.Area(run, target.X, target.Z, 4, 25 * WaveData.HPScale(now), 2)
			end
		end
	end

	-- next event: never during a boss fight
	if now >= w.NextEventAt and now >= w.EventUntil then
		if run.Boss or w.PendingBoss then
			w.NextEventAt = now + 10
			return
		end
		local e = pickWeighted(run.Rng, WaveData.Events, function(ev)
			if ev.Key == w.LastEvent then
				return 0
			end
			local weight = ev.Weight
			if ev.Key == "Event67" and (run.Character == "SixSeven" or run.Rares.Percent67) then
				weight *= 3
			end
			return weight
		end)
		if w.Force67 then
			-- picking the 67% card promises a 67 EVENT within 6.7 seconds
			w.Force67 = false
			e = WaveData.EventByKey.Event67
		end
		WaveManager.TriggerEvent(run, e.Key)
		local gap = run.Rng:NextNumber(WaveData.EventGap[1], WaveData.EventGap[2])
		if run.Character == "SixSeven" then
			gap *= 0.8
		end
		w.NextEventAt = now + gap
	end
end

---------------------------------------------------------------------------
-- secrets
---------------------------------------------------------------------------
local function stepSecrets(run)
	local w = run.Wave
	local now = run.Time
	local flags = run.Result.Flags

	-- SECRET 67: be level 6 or 7 at 1:07
	if not w.Secret67Checked and now >= 67 then
		w.Secret67Checked = true
		if run.Level == 6 or run.Level == 7 then
			flags.Secret67 = true
			run:Event("Secret", { Key = "Secret67", Title = "SECRET 67", Sub = "Level " .. run.Level .. " at 1:07. You found it." })
			run.Result.Events67 += 1
			run.Bonus67 = true -- the next offer contains the 67% card
			run.PendingChests += 1
		end
	end

	-- SIGMA STARE: stand still for 6.7 s with a horde around
	if not w.StareDone and now > 45 and run.StillFor >= GameConfig.Run.StandStillSecret then
		local near = 0
		for _, e in run.Enemies do
			if (e.X - run.PX) ^ 2 + (e.Z - run.PZ) ^ 2 < 30 * 30 then
				near += 1
			end
		end
		if near >= 12 then
			w.StareDone = true
			flags.SigmaStare = true
			for _, e in run.Enemies do
				if not e.IsBoss then
					e.FrozenUntil = now + 6.7
					run:Write("EState", e.Id, 3)
				end
			end
			run:Write("Fx", 0, run.PX, run.PZ, 0, 40, 0, Protocol.Fx.SigmaStare)
			run:Event("Secret", { Key = "SigmaStare", Title = "SIGMA STARE", Sub = "WHAT ARE YOU DOING BRO?" })
			w.UnfreezeAt = now + 6.7
		end
	end
	if w.UnfreezeAt and now >= w.UnfreezeAt then
		w.UnfreezeAt = nil
		for _, e in run.Enemies do
			if e.FrozenUntil > 0 then
				run:Write("EState", e.Id, 0)
			end
		end
	end

	-- UNTOUCHABLE: no damage in the first 3 minutes
	if not w.UntouchableChecked and now >= 180 then
		w.UntouchableChecked = true
		if run.DamageTaken <= 0 then
			flags.Untouchable = true
			run:Banner("UNTOUCHABLE", "3 minutes without a scratch", "Secret")
		end
	end
end

---------------------------------------------------------------------------
-- step
---------------------------------------------------------------------------
function WaveManager.Step(run, dt: number)
	local w = run.Wave
	local now = run.Time

	-- the very first enemy shows up right away, close enough to understand the game
	if not w.FirstSpawned and now >= GameConfig.Run.FirstEnemyDelay then
		w.FirstSpawned = true
		local a = run.Rng:NextNumber(0, TAU)
		for i = 0, 2 do
			EnemyManager.Spawn(run, "Goober", run.PX + cos(a + i * 0.4) * 24, run.PZ + sin(a + i * 0.4) * 24)
		end
	end

	local index, entry = WaveData.EntryAt(now)
	if index ~= w.Entry then
		w.Entry = index
		if entry.Banner then
			run:Banner(entry.Banner.Title, entry.Banner.Sub, "Wave")
		end
		if entry.Burst then
			burst(run, entry.Burst)
		end
		if entry.Boss then
			local key = if entry.Boss == "Mid" then w.MidBoss else entry.Boss
			w.PendingBoss = { Key = key, At = now + 3.5 }
			local def = EnemyData.Get(key)
			run:Event("BossWarning", { Key = key, Title = def.Params.Title, Delay = 3.5 })
		end
	end

	if w.PendingBoss and now >= w.PendingBoss.At then
		local key = w.PendingBoss.Key
		w.PendingBoss = nil
		spawnBoss(run, key)
	end

	-- steady spawns (+ catch-up when the screen is too empty)
	local alive = #run.Enemies
	local rate = entry.Rate * (if run.Boss then 0.55 else 1)
	w.Acc += rate * dt
	if alive < entry.MinAlive then
		w.Acc += (entry.MinAlive - alive) * dt * 0.8
	end
	local spawned = 0
	while w.Acc >= 1 and spawned < 12 do
		w.Acc -= 1
		spawned += 1
		if #run.Enemies >= run.MaxEnemies then
			w.Acc = min(w.Acc, 3)
			break
		end
		local pick = pickWeighted(run.Rng, (WaveManager.MixList(entry)), function(m)
			return m[2]
		end)
		spawnKind(run, pick[1])
	end

	-- loot crates
	if now >= w.CrateAt then
		w.CrateAt = now + GameConfig.Drops.CrateEvery
		local x, z = EnemyManager.RingPoint(run, 22, 34)
		EnemyManager.Spawn(run, "Crate", x, z, { Force = true, NoScale = true })
	end

	stepEvents(run, dt)
	stepSecrets(run)
end

-- timeline mixes as arrays (cached)
local mixCache = {}
function WaveManager.MixList(entry): { { any } }
	local cached = mixCache[entry]
	if cached then
		return cached
	end
	local list = {}
	for key, weight in entry.Mix do
		table.insert(list, { key, weight })
	end
	table.sort(list, function(a, b)
		return a[1] < b[1]
	end)
	mixCache[entry] = list
	return list
end

return WaveManager
