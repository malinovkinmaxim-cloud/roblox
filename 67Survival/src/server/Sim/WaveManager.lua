--[[
	WaveManager - the run director: follows the timeline (shared/WaveData.lua), spawns the
	horde around the player (packs, elites, bursts), bosses, loot crates, the rare 67 EVENTS
	and the in-run secrets.

	67 EVENTS (WaveData.Events): "6... 7... 67 EVENT" then one of
	  67% EVENT   +67% damage, +67% XP, +67% enemies
	  67 CHEST    a golden chest spawns nearby (rare cards only)
	  67 INVASION the enemy cap is raised: the whole screen fills with a weaker horde
	  67 LUCK     huge luck: rare cards, drops, loot boxes, a goblin
	  67 CHAOS    random things every few seconds
	  67 MODE     a rule change: TINY / TURBO / GLASS / GIANT
	  67 BOSS     THE 67 KING appears
	  THE 67      the rarest enemy: circles you, leaves after 50 s if not defeated

	In a party, members' runs are Followers: their events come from the leader's run
	(GameManager calls WaveManager.TriggerEvent on them) so everyone sees the same moment.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local EnemyData = require(Shared.EnemyData)
local WaveData = require(Shared.WaveData)
local Protocol = require(Shared.Protocol)

local EnemyManager = require(script.Parent.EnemyManager)
local CombatManager = require(script.Parent.CombatManager)
local Pickups = require(script.Parent.Pickups)

local WaveManager = {}

local cos, sin, min, max = math.cos, math.sin, math.min, math.max
local TAU = math.pi * 2
local GFX = Protocol.Fx

local function pickWeighted(rng, entries: { any }, weightOf: (any) -> number)
	local total = 0
	for _, entry in entries do
		total += max(0, weightOf(entry))
	end
	if total <= 0 then
		return nil
	end
	local r = rng:NextNumber(0, total)
	for _, entry in entries do
		r -= max(0, weightOf(entry))
		if r <= 0 then
			return entry
		end
	end
	return entries[#entries]
end

-- how much sooner 67 events come for this run (difficulty, heroes, limited-time events)
local function eventRate(run): number
	local rate = (run.LiveEvent.EventRate or 1) * (if run.Diff then run.Diff.Events else 1)
	if run.Mech == "Jackpot" then
		rate *= 1.3
	elseif run.Mech == "SixtySeven" then
		rate *= 1.5
	end
	return rate
end

function WaveManager.Init(run, bossPicks: { string }?)
	local rng = run.Rng
	local bosses = {}
	for i, pair in EnemyData.BossSlots do
		local forced = bossPicks and bossPicks[i]
		bosses[i] = if forced and table.find(pair, forced) then forced else pair[rng:NextInteger(1, #pair)]
	end
	run.Wave = {
		Entry = 0,
		Acc = 0,
		Bosses = bosses,
		NextEventAt = rng:NextNumber(WaveData.EventFirstAt[1], WaveData.EventFirstAt[2]) / eventRate(run),
		LastEvent = nil,
		EventKey = nil,
		EventUntil = 0,
		CrateAt = GameConfig.Drops.CrateEvery * 0.6,
		PendingBoss = nil,
		InvasionUntil = 0,
		ChaosUntil = 0,
		ChaosNext = 0,
		RainLeft = 0,
		RainNext = 0,
		Secret67Checked = false,
		StareDone = false,
		FirstSpawned = false,
		-- difficulty rules (no random draws without them: tier II stays the classic run)
		SurpriseAt = if run.Mods and run.Mods.Chaos then 60 + rng:NextNumber(0, 15) else math.huge, -- CHAOS: arena surprises
		GlitchAt = if run.Mods and run.Mods.Glitch then 40 + rng:NextNumber(0, 10) else math.huge, -- GLITCH: the horde glitches in close
	}
	if run.Follower then
		run.Wave.NextEventAt = math.huge
	end
end

---------------------------------------------------------------------------
-- spawning
---------------------------------------------------------------------------
local function spawnKind(run, key: string, entry)
	local x, z = EnemyManager.RingPoint(run, GameConfig.Arena.SpawnRadiusMin, GameConfig.Arena.SpawnRadiusMax)
	local luck = run.Stats.Luck
	local rng = run.Rng
	local now = run.Time
	-- very rare specials replace a normal spawn
	if key == "Goober" and rng:NextNumber() < 1 / 500 * luck then
		return EnemyManager.Spawn(run, "GoldenGoober", x, z, { Golden = true })
	end
	if now > 45 and rng:NextNumber() < 0.0004 * luck * (if run.Mech == "SixtySeven" then 2 else 1) then
		return EnemyManager.Spawn(run, "Goblin67", x, z, { Force = true, NoScale = true })
	end
	local invasion = now < run.Wave.InvasionUntil
	-- ELITE INVASION difficulty: elites a minute sooner; every tier scales how many
	local eliteFrom = if run.Mods and run.Mods.EliteInvasion then 90 else GameConfig.Drops.EliteFrom
	local eliteChance = GameConfig.Drops.EliteChance * (if run.Diff then run.Diff.Elite else 1)
	local elite = not invasion and now >= eliteFrom and key ~= "Skitter" and rng:NextNumber() < eliteChance
	local opts = if elite then { Elite = true } elseif invasion then { HPMult = 0.4 } else nil
	local e = EnemyManager.Spawn(run, key, x, z, opts)
	-- packs: some enemies come in groups
	local pack = entry.Pack and entry.Pack[key]
	if e and pack and pack > 1 then
		for i = 2, pack do
			local a = rng:NextNumber(0, TAU)
			local r = 1.5 + i * 0.35
			EnemyManager.Spawn(run, key, x + cos(a) * r, z + sin(a) * r, opts)
		end
	end
	return e
end

local function burst(run, b, opts)
	if b.Kind == "Ring" then
		for i = 1, b.Count do
			local a = (i / b.Count) * TAU
			EnemyManager.Spawn(run, b.Key, run.PX + cos(a) * b.Radius, run.PZ + sin(a) * b.Radius, opts or { Force = true })
		end
	elseif b.Kind == "Wall" then
		-- a line of enemies rushing in from one side
		local a = run.Rng:NextNumber(0, TAU)
		local cx, cz = run.PX + cos(a) * 60, run.PZ + sin(a) * 60
		local tx, tz = -sin(a), cos(a)
		for i = 1, b.Count do
			local off = (i - (b.Count + 1) / 2) * 2.4
			EnemyManager.Spawn(run, b.Key, cx + tx * off, cz + tz * off, opts or { Force = true })
		end
	end
end

local function warnBoss(run, key: string)
	local def = EnemyData.Get(key)
	run.Wave.PendingBoss = { Key = key, At = run.Time + 3.5 }
	run:Event("BossWarning", { Key = key, Title = def.Params.Title, Delay = 3.5, Final = def.Params.Final == true })
end

local function spawnBoss(run, key: string)
	local def = EnemyData.Get(key)
	local x, z = EnemyManager.RingPoint(run, 38, 46)
	EnemyManager.Spawn(run, key, x, z, { Force = true })
	run:Write("Fx", 0, x, z, 0, def.Radius * 3, 0, GFX.Enrage)
end

---------------------------------------------------------------------------
-- 67 events
---------------------------------------------------------------------------
local EVENTS = {}

function EVENTS.Percent67(run, ev)
	run:AddBuff("P67", ev.Duration)
end

-- 67 CHAOS difficulty: 67 events are stronger (longer, double loot)
local function chaos67(run): boolean
	return run.Mods ~= nil and run.Mods.Chaos67 == true
end

function EVENTS.Chest67(run)
	for i = 1, if chaos67(run) then 2 else 1 do
		local a = run.Rng:NextNumber(0, TAU) + (i - 1) * 2
		local r = run.Rng:NextNumber(14, 20)
		Pickups.SpawnItem(run, "Chest67", run.PX + cos(a) * r, run.PZ + sin(a) * r)
	end
end

function EVENTS.Invasion67(run, ev)
	local w = run.Wave
	w.InvasionUntil = run.Time + ev.Duration
	run.MaxEnemies = max(run.MaxEnemies, WaveManager.InvasionCap(run))
	local opts = { Force = true, HPMult = 0.4 }
	burst(run, { Kind = "Ring", Key = "Goober", Count = 40, Radius = 34 }, opts)
	burst(run, { Kind = "Ring", Key = "Skitter", Count = 30, Radius = 44 }, opts)
	burst(run, { Kind = "Wall", Key = "Husk", Count = 24 }, opts)
end

function EVENTS.Luck67(run, ev)
	run:AddBuff("Luck67", ev.Duration)
	local more = chaos67(run)
	for i = 1, if more then 5 else 3 do
		local x, z = EnemyManager.RingPoint(run, 16 + i * 4, 22 + i * 4)
		EnemyManager.Spawn(run, "Crate", x, z, { Force = true, NoScale = true })
	end
	for _ = 1, if more then 2 else 1 do
		local x, z = EnemyManager.RingPoint(run, 26, 32)
		EnemyManager.Spawn(run, "Goblin67", x, z, { Force = true, NoScale = true })
	end
end

function EVENTS.Chaos67(run, ev)
	local w = run.Wave
	w.ChaosUntil = run.Time + ev.Duration
	w.ChaosNext = 1
end

function EVENTS.Mode67(run, ev, variantKey: string?)
	local variant = nil
	for _, m in WaveData.Modes67 do
		if m.Key == variantKey then
			variant = m
		end
	end
	variant = variant or pickWeighted(run.Rng, WaveData.Modes67, function(m)
		return m.Weight
	end)
	if variant.Key == "Tiny" then
		run:AddBuff("TinyMode", ev.Duration)
		EnemyManager.ShrinkAll(run, 0.67)
		run:Write("Fx", 0, run.PX, run.PZ, 0, 60, 0, GFX.Shrink)
	else
		run:AddBuff(variant.Key .. "Mode", ev.Duration)
	end
	return variant
end

function EVENTS.Boss67(run)
	warnBoss(run, "King67")
end

function EVENTS.The67(run)
	local x, z = EnemyManager.RingPoint(run, 26, 32)
	EnemyManager.Spawn(run, "The67", x, z, { Force = true, NoScale = true, HPMult = 1 + max(0, run.Level - 15) * 0.03 })
end

-- starts a 67 event now (also called by GameManager to sync a party). Returns the variant key.
function WaveManager.TriggerEvent(run, key: string, variantKey: string?): string?
	local ev = WaveData.EventByKey[key]
	if not ev or run.Ended then
		return nil
	end
	if chaos67(run) then
		ev = table.clone(ev)
		ev.Duration *= 1.5
	end
	local w = run.Wave
	w.LastEvent = key
	w.EventKey = key
	w.EventUntil = run.Time + ev.Duration
	run.Result.Events67 += 1
	run.Result.EventsSeen[key] = true
	local variant = EVENTS[key](run, ev, variantKey)
	run:Write("Fx", 0, run.PX, run.PZ, 0, 40, 0, GFX.Event67)
	run:Event("Event67", {
		Key = key,
		Title = if variant then variant.Title else ev.Title,
		Sub = if variant then variant.Sub else ev.Sub,
		Event = ev.Title,
		Duration = ev.Duration,
		Variant = if variant then variant.Key else nil,
	})
	if run.OnEvent67 then
		run.OnEvent67(key, if variant then variant.Key else nil)
	end
	return if variant then variant.Key else nil
end

-- a 67 CHAOS tick: something random happens
local function chaosTick(run)
	local rng = run.Rng
	local roll = rng:NextInteger(1, 6)
	local now = run.Time
	if roll == 1 then
		-- meteor shower on the horde
		for _ = 1, 4 do
			local target = CombatManager.Nearest(run, run.PX + rng:NextNumber(-30, 30), run.PZ + rng:NextNumber(-30, 30), 30)
			if target then
				run:Write("Fx", 0, target.X, target.Z, 0, 6, 0, GFX.Chaos67)
				CombatManager.Area(run, target.X, target.Z, 6, 40 * WaveData.HPScale(now), 6)
			end
		end
	elseif roll == 2 then
		EnemyManager.ShrinkAll(run, 0.4)
		run:Write("Fx", 0, run.PX, run.PZ, 0, 50, 0, GFX.Shrink)
	elseif roll == 3 then
		-- goober rain (tiny, from the sky)
		run.Wave.RainLeft += 20
	elseif roll == 4 then
		run:AddBuff("TurboMode", 4)
	elseif roll == 5 then
		run.MagnetAll = true
		run:Heal(10)
	else
		local x, z = EnemyManager.RingPoint(run, 20, 28)
		EnemyManager.Spawn(run, "Crate", x, z, { Force = true, NoScale = true })
		for _, e in run.Enemies do
			if not e.IsBoss and rng:NextNumber() < 0.3 then
				EnemyManager.Slow(e, 0.4, 3, now)
			end
		end
		run:Write("Fx", 0, run.PX, run.PZ, 0, 40, 0, GFX.Freeze)
	end
end

-- GLITCH difficulty: a few far-away enemies glitch in on a ring around the player
local function glitchHorde(run)
	local rng = run.Rng
	local half = GameConfig.Arena.HalfSize
	local moved = 0
	for _, e in run.Enemies do
		if moved >= 4 then
			break
		end
		local b = e.Behavior
		if not e.IsBoss and not e.Dormant and not e.Lit and not e.Air and e.State == 0 and b ~= "Static" and b ~= "Flee" and b ~= "Sixty" and rng:NextNumber() < 0.35 then
			local dx, dz = e.X - run.PX, e.Z - run.PZ
			if dx * dx + dz * dz > 26 * 26 then
				local a = rng:NextNumber(0, TAU)
				local r = rng:NextNumber(14, 18)
				local x = math.clamp(run.PX + cos(a) * r, -half, half)
				local z = math.clamp(run.PZ + sin(a) * r, -half, half)
				run:Write("Fx", 0, e.X, e.Z, 0, 3, 0, GFX.Teleport)
				e.X, e.Z = x, z
				e.SentX, e.SentZ = x, z
				run:Write("Blink", e.Id, x, z)
				run:Write("Fx", 0, x, z, 0, 3, 0, GFX.Teleport)
				moved += 1
			end
		end
	end
end

local function stepEvents(run, dt: number)
	local w = run.Wave
	local now = run.Time
	local mods = run.Mods or {}

	-- difficulty rules
	if mods.Chaos and now >= w.SurpriseAt then
		-- CHAOS: the arena throws a random surprise (never during a boss fight)
		w.SurpriseAt = now + run.Rng:NextNumber(35, 50)
		if not run.Boss and not w.PendingBoss then
			chaosTick(run)
		end
	end
	if mods.Glitch and now >= w.GlitchAt then
		w.GlitchAt = now + run.Rng:NextNumber(10, 14)
		glitchHorde(run)
	end

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
	if now < w.ChaosUntil then
		w.ChaosNext -= dt
		if w.ChaosNext <= 0 then
			w.ChaosNext = 2.5
			chaosTick(run)
		end
	end
	if w.InvasionUntil > 0 and now >= w.InvasionUntil then
		w.InvasionUntil = 0
		run.MaxEnemies = run.BaseMaxEnemies
	end

	-- next event: never during a boss fight
	if now >= w.NextEventAt and now >= w.EventUntil then
		if run.Boss or w.PendingBoss then
			w.NextEventAt = now + 10
			return
		end
		local ev
		if w.Force67 then
			-- picking the 67% card promises a 67% EVENT within 6.7 seconds
			w.Force67 = false
			ev = WaveData.EventByKey.Percent67
		else
			ev = pickWeighted(run.Rng, WaveData.Events, function(e)
				if e.Key == w.LastEvent or (e.MinTime and now < e.MinTime) then
					return 0
				end
				local weight = e.Weight
				if e.Key == "Boss67" or e.Key == "The67" then
					if run.Mech == "SixtySeven" then
						weight *= 3
					end
					if chaos67(run) then
						weight *= 2
					end
				end
				return weight
			end)
		end
		if ev then
			WaveManager.TriggerEvent(run, ev.Key)
		end
		w.NextEventAt = now + run.Rng:NextNumber(WaveData.EventGap[1], WaveData.EventGap[2]) / eventRate(run)
		if run.Follower then
			w.NextEventAt = math.huge -- party members get their events from the leader
		end
	end
end

function WaveManager.InvasionCap(run): number
	local base = run.BaseMaxEnemies or GameConfig.Sim.MaxEnemiesPerRun
	return math.floor(base * GameConfig.Sim.InvasionEnemies / GameConfig.Sim.MaxEnemiesPerRun)
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
					e.Thaw = true
					run:Write("EState", e.Id, Protocol.EState.Frozen)
				end
			end
			run:Write("Fx", 0, run.PX, run.PZ, 0, 40, 0, GFX.SigmaStare)
			run:Event("Secret", { Key = "SigmaStare", Title = "SIGMA STARE", Sub = "The horde froze. A new ability was unlocked." })
		end
	end

	-- UNTOUCHABLE: no damage in the first 3 minutes
	if not w.UntouchableChecked and now >= 180 then
		w.UntouchableChecked = true
		if run.DamageTaken <= 0 then
			flags.Untouchable = true
			run:Event("Secret", { Key = "Untouchable", Title = "UNTOUCHABLE", Sub = "3 minutes without a scratch" })
		end
	end
end

---------------------------------------------------------------------------
-- step
---------------------------------------------------------------------------
function WaveManager.Step(run, dt: number)
	local w = run.Wave
	local now = run.Time

	-- the very first enemies show up right away, close enough to understand the game
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
			local key = if type(entry.Boss) == "number" then w.Bosses[entry.Boss] else entry.Boss
			if key then
				warnBoss(run, key)
			end
		end
	end

	if w.PendingBoss and now >= w.PendingBoss.At then
		local key = w.PendingBoss.Key
		w.PendingBoss = nil
		spawnBoss(run, key)
	end

	-- steady spawns (+ catch-up when the screen is too empty)
	local alive = #run.Enemies
	local invasion = now < w.InvasionUntil
	-- difficulty: a bigger horde (NO MERCY: denser still)
	local density = (if run.Diff then run.Diff.Spawn else 1) * (if run.Mods and run.Mods.NoMercy then 1.15 else 1)
	local rate = entry.Rate * density * (if run.Boss then 0.55 else 1)
	if run:Buff("P67") then
		rate *= 1.67
	end
	local minAlive = math.floor(entry.MinAlive * density)
	if invasion then
		rate *= 3
		minAlive = run.MaxEnemies
	end
	w.Acc += rate * dt
	if alive < minAlive then
		w.Acc += (minAlive - alive) * dt * (if invasion then 2 else 0.8)
	end
	local spawned = 0
	while w.Acc >= 1 and spawned < (if invasion then 30 else 12) do
		w.Acc -= 1
		spawned += 1
		if #run.Enemies >= run.MaxEnemies then
			w.Acc = min(w.Acc, 3)
			break
		end
		local pick = pickWeighted(run.Rng, WaveManager.MixList(entry), function(m)
			return m[2]
		end)
		spawnKind(run, pick[1], entry)
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
