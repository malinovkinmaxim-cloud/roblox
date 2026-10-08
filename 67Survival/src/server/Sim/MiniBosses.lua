--[[
	MiniBosses - the BOSS ENCOUNTERS of a run. One system for every boss (who and when:
	shared/BossData.lua, the timeline: Sim/BossDirector.lua):
	  boss 1-4      in the lair of their zone ("mini-bosses" in the code)
	  THE FINAL ONE in the 67 ARENA in the centre of the map

	An ENCOUNTER is one boss (the twins are one encounter with two bodies):
	  Warn    announced BossData.WarnLead seconds early: the lair lights up, a marker on the
	          minimap, an arrow, "BOSS 2 · CARTZILLA in 10"
	  Fight   the bodies are in the world. Lair bosses guard their lair: they come for you when
	          you are close (Aggro), never stray further than Leash, walk home and heal when you
	          run away (Reset). THE FINAL ONE waits in the arena; walking in SEALS it (nobody
	          leaves, the horde stays out); if you never come it pulls you in (Main.PullAfter).
	  done    Defeated (items on the map, its boss relic if unlocked, XP, coins) / Left (it was
	          never fought and the next boss was announced) / Escaped (TICK TOCK's alarm)

	PHASES (BossData Phases): HP thresholds, each announced, faster attacks (e.Rate), more
	patterns. WEAK POINTS (BossData WeakPoint): after one of its attacks a boss is EXPOSED for a
	moment and takes more damage (Sim/Perks.ExposedMult). Every attack is telegraphed on the
	ground (Bosses.Telegraph) so it can be dodged.

	Called by EnemyManager (Behavior "Champion" / "Boss" with an encounter) and BossDirector.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local Protocol = require(Shared.Protocol)
local ArenaData = require(Shared.ArenaData)
local BossData = require(Shared.BossData)
local ItemData = require(Shared.ItemData)

local Bosses = require(script.Parent.Bosses)
local Pickups = require(script.Parent.Pickups)
local Items = require(script.Parent.Items)

local MiniBosses = {}

local sqrt, cos, sin, atan2, min, max, floor = math.sqrt, math.cos, math.sin, math.atan2, math.min, math.max, math.floor
local TAU = math.pi * 2
local GFX = Protocol.Fx
local ES = Protocol.EState
local SHAPE = Protocol.Shapes
local MF = Protocol.MiniFlags
local LAIR = BossData.Lair
local MAIN = BossData.Main
local PLAYER_R = GameConfig.Player.Radius
local telegraph = Bosses.Telegraph

local function state(run, e, s: number)
	if e.VState ~= s then
		e.VState = s
		run:Write("EState", e.Id, s)
	end
end

local function windup(run, seconds: number): number
	return seconds * (run.Windup or 1)
end

---------------------------------------------------------------------------
-- encounters
---------------------------------------------------------------------------
export type Encounter = {
	Def: any, -- BossData entry
	Slot: number, -- 1..4, 5 = THE FINAL ONE
	Main: boolean,
	X: number,
	Z: number,
	Zone: string,
	Lair: any?,
	Stage: string,
	At: number,
	Bodies: { any },
	SpawnedAt: number,
	LastEngaged: number,
	Engaged: boolean,
	AlarmAt: number?,
	Revive: any?,
	LastX: number,
	LastZ: number,
	Done: boolean?,
	Crowned: boolean?,
	Fragments: number,
	Fused: boolean?, -- THE 67 PRIME: its twins fused
}

function MiniBosses.Active(run): { Encounter }
	return run.Map.Encounters
end

-- is this boss (BossData key) out right now?
function MiniBosses.IsOut(run, key: string): boolean
	for _, enc in run.Map.Encounters do
		if enc.Def.Key == key then
			return true
		end
	end
	return false
end

-- a boss is being fought right now (the horde thins out, 67 events wait)
function MiniBosses.Fighting(run): boolean
	for _, enc in run.Map.Encounters do
		if enc.Stage == "Fight" and run.Time - enc.LastEngaged < 3 then
			return true
		end
	end
	return false
end

-- "BOSS 1 · THE BIG QUACK": the encounter is announced at its lair / the arena
function MiniBosses.Announce(run, def, slot: number, x: number, z: number, lair, spawnAt: number, crowned: boolean?): Encounter
	local main = slot == 5
	local zone = ArenaData.ZoneAt(x, z)
	local enc: Encounter = {
		Def = def,
		Slot = slot,
		Main = main,
		X = x,
		Z = z,
		Zone = zone.Key,
		Lair = lair,
		Stage = "Warn",
		At = spawnAt,
		Bodies = {},
		SpawnedAt = run.Time,
		LastEngaged = run.Time,
		Engaged = false,
		LastX = x,
		LastZ = z,
		Crowned = crowned == true,
		Fragments = 0,
	}
	table.insert(run.Map.Encounters, enc)
	run:Write("Fx", 0, x, z, 0, if lair then lair.R else 12, 0, GFX.MiniSpawn)
	local slotDef = BossData.Slots[slot]
	run:Event("MiniBoss", {
		Phase = "Warn",
		Key = def.Key,
		Title = def.Title,
		Slot = slot,
		Main = main,
		Zone = zone.Key,
		ZoneName = if main then "THE 67 ARENA" else zone.Name,
		X = x,
		Z = z,
		Delay = max(0, spawnAt - run.Time),
		Hint = def.Hint,
		Tests = if main then MAIN.Tests else slotDef and slotDef.Tests,
		Crowned = enc.Crowned,
	})
	return enc
end

local function bodyIds(enc: Encounter): { number }
	local ids = {}
	for _, e in enc.Bodies do
		if e.Alive then
			table.insert(ids, e.Id)
		end
	end
	return ids
end

-- HP of one body: the design value at its slot, the tier's BossHP, a strong build meets more
function MiniBosses.BodyHP(run, def, slot: number, crowned: boolean?): number
	local expected = if slot == 5 then MAIN.Level else BossData.Slots[slot].Level
	local level = 1 + max(0, run.Level - expected) * (if slot == 5 then 0.03 else 0.02)
	local diff = if run.Diff then run.Diff.BossHP else 1
	return def.HP * diff * level * (if crowned then 1.3 else 1)
end

-- the damage multiplier of a boss (shared/BossData.lua Slots / Main Damage)
local function bossDamage(enc: Encounter): number
	return (if enc.Main then MAIN.Damage else BossData.Slots[enc.Slot].Damage) * (if enc.Crowned then 1.15 else 1)
end

local function spawnBodies(run, enc: Encounter, EM)
	local def = enc.Def
	local hp = MiniBosses.BodyHP(run, def, enc.Slot, enc.Crowned)
	local damage = bossDamage(enc)
	for i, key in def.Bodies do
		local x, z = enc.X, enc.Z
		local pads = enc.Lair and enc.Lair.Pads
		if pads and pads[i] then
			x, z = pads[i][1], pads[i][2]
		end
		local e = EM.Spawn(run, key, x, z, { Force = true, Encounter = enc, HomeX = x, HomeZ = z, BossHP = hp, BossDamage = damage })
		if e then
			table.insert(enc.Bodies, e)
			run:Write("Fx", 0, x, z, 0, e.Radius * 3, 0, GFX.MiniSpawn)
		end
	end
	enc.Stage = "Fight"
	enc.SpawnedAt = run.Time
	enc.LastEngaged = run.Time
	run:Event("MiniBoss", {
		Phase = "Spawn",
		Key = def.Key,
		Title = def.Title,
		Slot = enc.Slot,
		Main = enc.Main,
		Zone = enc.Zone,
		Ids = bodyIds(enc),
		X = enc.X,
		Z = enc.Z,
		Timer = def.Timer,
		Hint = def.Hint,
		Crowned = enc.Crowned,
	})
end

local function anyAlive(enc: Encounter): boolean
	for _, e in enc.Bodies do
		if e.Alive then
			return true
		end
	end
	return false
end

local function remove(run, enc: Encounter)
	local list = run.Map.Encounters
	local i = table.find(list, enc)
	if i then
		table.remove(list, i)
	end
end

local function despawnAll(run, enc: Encounter, EM)
	for _, e in enc.Bodies do
		if e.Pylons then
			for _, py in e.Pylons do
				EM.Despawn(run, py)
			end
		end
		EM.Despawn(run, e)
	end
end

-- the loot of a beaten boss: items on the map (better for every slot), its relic, XP, coins
local function reward(run, enc: Encounter, EM)
	local def = enc.Def
	local x, z = enc.LastX, enc.LastZ
	local rng = run.Rng
	if not enc.Main then
		-- items (a crowned boss drops twice as many)
		local source = "Boss" .. enc.Slot
		local count = if enc.Crowned then 2 else nil
		if count then
			Items.DropFrom(run, source, x, z, (if enc.Slot == 4 then 2 else 1) * count)
		else
			Items.DropFrom(run, source, x, z)
		end
		-- its boss relic (unlocked with CHIPS), a hint when it is still locked
		if not Items.DropRelic(run, def.Key, x - 4, z) then
			local relic = ItemData.ByBoss[def.Key]
			if relic and not run.ItemUnlocks[relic.Key] then
				run:Event("LockedRelic", { Key = relic.Key, Name = relic.Name, Boss = def.Title, Price = relic.Price })
			end
		end
	end
	-- a burst of XP (grows with the run: XP needs grow too)
	local trophy = run.UP and run.UP.TrophyHunter
	local xp = def.XP * (1 + run.Time / 120) * (1 + (if trophy then trophy.XP else 0))
	if xp > 0 then
		for k = 1, 8 do
			local a = k * (TAU / 8) + rng:NextNumber(-0.3, 0.3)
			local r = rng:NextNumber(4, 7)
			Pickups.SpawnGem(run, x + cos(a) * r, z + sin(a) * r, xp / 8)
		end
	end
	if trophy and trophy.Level then
		run.PendingChests += 1
	end
	run:AddCoins(def.Coins)
	if not enc.Main then -- a boss always leaves a snack: the fight costs HP
		Pickups.SpawnItem(run, "Snack", x + rng:NextNumber(-3, 3), z + rng:NextNumber(-3, 3))
	end
	for k = 1, GameConfig.Rewards.FragmentsPerBoss + (run.LiveEvent.BossFragments or 0) do
		local a = k * 2.4
		Pickups.SpawnItem(run, "Fragment", x + cos(a) * 3, z + sin(a) * 3)
	end
	-- a boss kill clears some pressure
	local n = 0
	for _, other in table.clone(run.Enemies) do
		local dx, dz = other.X - x, other.Z - z
		if not other.IsBoss and other.Key ~= "Crate" and dx * dx + dz * dz < 30 * 30 and n < 40 then
			n += 1
			EM.Damage(run, other, other.HP + 1, 0, dx, dz, 8)
		end
	end
end

-- the encounter is over: Defeated / Left / Escaped
local function finish(run, enc: Encounter, outcome: string, EM)
	if enc.Done then
		return
	end
	enc.Done = true
	remove(run, enc)
	local def = enc.Def
	if run.Map.ArenaSealed and enc.Main then
		run.Map.ArenaSealed = nil
		run:Event("Arena", { Sealed = false })
	end
	if enc.Main then
		run.Map.MainOut = nil
		run.Map.DarkUntil = nil
		run.ShotRoom = nil
		run:Event("Arena", { Tint = false }) -- a BLOOD MOON / OVERCLOCK tint is over
	end
	if outcome == "Defeated" then
		reward(run, enc, EM)
		run.Result.BossesBeaten = (run.Result.BossesBeaten or 0) + 1
		run.Result.BossSlots = run.Result.BossSlots or {}
		table.insert(run.Result.BossSlots, enc.Slot)
		table.insert(run.Result.Bosses, if #def.Bodies == 1 then def.Bodies[1] else def.Key)
		local sub = "Loot dropped: grab it!"
		if def.Key == "TickTock" and enc.AlarmAt then
			local bonus = enc.Bodies[1] and enc.Bodies[1].Def.Params.OnTimeCoins or 0
			run:AddCoins(bonus)
			run.Result.Flags.OnTime = true
			sub = "Right on time! +" .. bonus .. " coins. Grab the loot!"
		end
		run:Event("MiniBoss", { Phase = "Defeated", Key = def.Key, Title = def.Title, Slot = enc.Slot, Main = enc.Main, X = enc.LastX, Z = enc.LastZ })
		run:Event("BossDefeated", { Key = def.Key, Title = def.Title, Final = enc.Main, Slot = enc.Slot })
		if enc.Main then
			run.Result.MainBoss = true
			run.VictoryAt = run.Time + 3.5
			run.Invulnerable = max(run.Invulnerable, 10) -- nothing can take this win away
			run:Write("Fx", 0, enc.LastX, enc.LastZ, 0, 40, 0, GFX.Blast67)
			run:Banner("VICTORY", def.Title .. " has been defeated", "Victory")
		else
			run:Banner(def.Title .. " DEFEATED", sub, "Reward")
		end
	else
		despawnAll(run, enc, EM)
		run:Event("MiniBoss", { Phase = outcome, Key = def.Key, Title = def.Title, Slot = enc.Slot })
		if outcome == "Escaped" then
			run:Banner("THE ALARM RANG", def.Title .. " escaped with its loot.", "Info")
		else
			run:Banner(def.Title .. " LEFT", "Nobody came. No loot this time.", "Info")
		end
	end
end
MiniBosses.Finish = finish

-- the next boss is announced: bosses nobody is fighting leave (with their loot)
function MiniBosses.LeaveIdle(run, EM)
	for _, enc in table.clone(run.Map.Encounters) do
		if not enc.Main and (enc.Stage == "Warn" or run.Time - enc.LastEngaged > 8) then
			finish(run, enc, "Left", EM)
		end
	end
end

-- 67 BOSS event: the boss that is out gets a golden crown (tougher, double loot)
function MiniBosses.Crown(run, enc: Encounter)
	if enc.Crowned or enc.Main then
		return
	end
	enc.Crowned = true
	for _, e in enc.Bodies do
		if e.Alive then
			e.MaxHP *= 1.3
			e.HP *= 1.3
			e.SentHP = -1
		end
	end
	run:Event("MiniBoss", { Phase = "Crowned", Key = enc.Def.Key, Title = enc.Def.Title, Ids = bodyIds(enc) })
end

-- THE FINAL ONE pulls you into its arena (you never came)
local function pull(run, enc: Encounter)
	local a = atan2(run.PZ - enc.Z, run.PX - enc.X)
	local r = MAIN.ArenaR - 8
	local x, z = enc.X + cos(a) * r, enc.Z + sin(a) * r
	run:Write("Fx", 0, run.PX, run.PZ, 0, 6, 0, GFX.Pull)
	run.PX, run.PZ = x, z
	run.TeleportTo = { X = x, Z = z }
	run.Invulnerable = max(run.Invulnerable, 1.5)
	run:Write("Fx", 0, x, z, 0, 6, 0, GFX.Pull)
	run:Banner("COME HERE", enc.Def.Title .. " pulled you into the arena", "Boss")
end

-- warn -> spawn, twins reviving, TICK TOCK's alarm, the arena pull
function MiniBosses.StepEncounters(run, EM)
	local now = run.Time
	for _, enc in table.clone(run.Map.Encounters) do
		if enc.Stage == "Warn" then
			if now >= enc.At then
				spawnBodies(run, enc, EM)
			end
		elseif not enc.Done then
			local revive = enc.Revive
			if revive and now >= revive.At then
				enc.Revive = nil
				if anyAlive(enc) then
					local hp = MiniBosses.BodyHP(run, enc.Def, enc.Slot, enc.Crowned)
					local e = EM.Spawn(run, revive.Key, revive.X, revive.Z, { Force = true, Encounter = enc, HomeX = revive.HomeX, HomeZ = revive.HomeZ, BossHP = hp, BossDamage = bossDamage(enc) })
					if e then
						-- back at half health (the bar shows the half that is missing)
						e.HP = e.MaxHP * 0.5
						for i, old in enc.Bodies do
							if old.Key == revive.Key and not old.Alive then
								enc.Bodies[i] = e
							end
						end
						run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 3, 0, GFX.TwinRevive)
						run:Event("MiniBoss", { Phase = "Revived", Key = enc.Def.Key, Id = e.Id, Body = revive.Key, Ids = bodyIds(enc) })
					end
				end
			end
			if enc.AlarmAt and now >= enc.AlarmAt then
				-- TICK TOCK: the alarm rings: a last ring of shots, and it is gone
				for _, e in enc.Bodies do
					if e.Alive then
						local p = e.Def.Params
						for i = 1, p.AlarmCount do
							local a = (i / p.AlarmCount) * TAU
							EM.Shoot(run, e.X, e.Z, cos(a) * p.AlarmSpeed, sin(a) * p.AlarmSpeed, 1.3, p.AlarmDamage * e.DmgScale, 4)
						end
						run:Write("Fx", 0, e.X, e.Z, 0, 14, 0, GFX.Alarm)
					end
				end
				finish(run, enc, "Escaped", EM)
			elseif enc.Main and not run.Map.ArenaSealed and now - enc.SpawnedAt >= MAIN.PullAfter and not MiniBosses.FightingOther(run, enc) then
				pull(run, enc)
			end
		end
	end
end

-- another boss than this one is being fought
function MiniBosses.FightingOther(run, enc: Encounter): boolean
	for _, other in run.Map.Encounters do
		if other ~= enc and other.Stage == "Fight" and run.Time - other.LastEngaged < 3 then
			return true
		end
	end
	return false
end

-- THE 67 PRIME's twins fused: its big body (phase 2 on) takes over the arena
local function fuse(run, enc: Encounter, EM)
	local def = enc.Def
	enc.Fused = true
	enc.Revive = nil
	local hp = MiniBosses.BodyHP(run, def, enc.Slot, enc.Crowned) * (def.FuseHP or 1)
	local x, z = enc.X, enc.Z
	local dx, dz = x - run.PX, z - run.PZ
	local d = sqrt(dx * dx + dz * dz)
	if d < 12 then
		-- not on top of you
		local a = if d > 0.1 then atan2(dz, dx) else run.Rng:NextNumber(0, TAU)
		x, z = run.PX + cos(a) * 14, run.PZ + sin(a) * 14
	end
	local e = EM.Spawn(run, def.Fused, x, z, { Force = true, Encounter = enc, HomeX = enc.X, HomeZ = enc.Z, BossHP = hp, BossDamage = bossDamage(enc) })
	if e then
		table.insert(enc.Bodies, e)
		run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 4, 0, GFX.Blast67)
		local ph = def.FusePhase
		run:Event("MiniBoss", { Phase = "Fused", Key = def.Key, Id = e.Id, Ids = bodyIds(enc), Index = 2, Name = ph and ph.Name, Text = ph and ph.Text, Main = enc.Main })
		run:Banner(def.Title .. " · " .. (if ph then ph.Name else "FUSED"), if ph then ph.Text else "", "Boss")
	end
end

-- a body died (EnemyManager.Kill)
function MiniBosses.OnKilled(run, e, EM)
	if e.Pylons then
		for _, py in e.Pylons do
			EM.Despawn(run, py)
		end
	end
	local enc = e.Encounter
	if not enc or enc.Done then
		return
	end
	enc.LastX, enc.LastZ = e.X, e.Z
	-- SIX & SEVEN: the other one brings this one back unless both go down together
	local twin = e.Def.Params.Twin
	if twin then
		for _, other in enc.Bodies do
			if other.Alive and other.Key == twin then
				local delay = e.Def.Params.ReviveTime
				enc.Revive = { Key = e.Key, X = e.X, Z = e.Z, HomeX = e.HomeX, HomeZ = e.HomeZ, At = run.Time + delay }
				run:Event("MiniBoss", { Phase = "Bond", Key = enc.Def.Key, Id = other.Id, Body = e.Key, Delay = delay })
				MiniBosses.Expose(run, other, "Bond") -- alone: its weak point
				return
			end
		end
	end
	-- THE 67 PRIME: both twins down within 6.7 s: they fuse into one
	if enc.Def.Fused and not enc.Fused and not anyAlive(enc) then
		fuse(run, enc, EM)
		return
	end
	if not anyAlive(enc) then
		finish(run, enc, "Defeated", EM)
	end
end

-- HP bars over the bosses (only what changed)
function MiniBosses.Flush(run)
	local now = run.Time
	for _, enc in run.Map.Encounters do
		for _, e in enc.Bodies do
			if e.Alive then
				local frac = floor(math.clamp(e.HP / e.MaxHP, 0, 1) * 65535)
				local flags = 0
				if e.Shielded then
					flags += MF.Shielded
				end
				if e.StunnedUntil and e.StunnedUntil > now then
					flags += MF.Stunned
				end
				if e.Phase and e.Phase >= 2 then
					flags += MF.Enraged
				end
				if e.GoingHome then
					flags += MF.Home
				end
				if e.ExposedUntil and e.ExposedUntil > now then
					flags += MF.Exposed
				end
				if enc.Crowned then
					flags += MF.Crowned
				end
				if e.DeathMark then
					flags += MF.Marked
				end
				if frac ~= e.SentHP or flags ~= e.SentFlags then
					e.SentHP, e.SentFlags = frac, flags
					run:Write("MiniHP", e.Id, frac, flags)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- phases and weak points
---------------------------------------------------------------------------
-- the boss is EXPOSED after this attack (when it is the one of its weak point)
function MiniBosses.Expose(run, e, reason: string)
	local enc = e.Encounter
	local def = if enc then enc.Def else BossData.ByBody[e.Key]
	local wp = def and def.WeakPoint
	if not wp or (wp.After ~= reason and wp.After ~= "*") or not e.Alive then
		return
	end
	local time = wp.Time
	local belt = run.IP and run.IP.ChampionBelt
	if belt and belt.Exposed then
		time *= 1 + belt.Exposed
	end
	if run.Synergies and run.Synergies.BossHunter then
		time += 1
	end
	e.ExposedUntil = run.Time + time
	e.SentFlags = -1
	run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 1.6, time, GFX.Exposed)
	run:Event("MiniBoss", { Phase = "Exposed", Key = def.Key, Id = e.Id, Text = wp.Text, Time = time })
end

-- a main boss enters a phase: THE FINAL ONE's 67 FRAGMENT breaks off (its relic; the main
-- bosses of the other tiers have none)
local function mainPhase(run, e, index: number)
	local enc = e.Encounter
	local relic = enc and ItemData.ByBoss[enc.Def.Key]
	if relic and run.ItemUnlocks[relic.Key] and enc and enc.Fragments < relic.MaxLevel then
		local have = (run.Items[relic.Key] or 0) + enc.Fragments
		if have < relic.MaxLevel then
			enc.Fragments += 1
			local a = run.Rng:NextNumber(0, TAU)
			local r = MAIN.ArenaR * 0.55
			Items.Drop(run, relic.Key, enc.X + cos(a) * r, enc.Z + sin(a) * r)
			run:Banner("THE 67 FRAGMENT BROKE OFF", "It's in the arena. Grab it if you dare.", "Boss")
		end
	end
	local _ = index
end

function MiniBosses.StepPhase(run, e)
	local enc = e.Encounter
	local def = if enc then enc.Def else BossData.ByBody[e.Key]
	local phases = def and def.Phases
	if not phases or e.Def.Params.NoPhases then
		return
	end
	e.Phase = e.Phase or 1 -- a boss body spawned on its own (debug) starts in phase 1
	local frac = e.HP / max(1, e.MaxHP)
	while e.Phase <= #phases and frac < phases[e.Phase].At do
		local ph = phases[e.Phase]
		e.Phase += 1
		e.Enraged = true
		e.Speed *= ph.Speed or 1
		e.Rate = ph.Rate or e.Rate
		e.SentFlags = -1
		if e.Patterns then
			Bosses.AddPhase(run, e, e.Phase)
		end
		run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2.2, 0, GFX.Phase)
		run:Event("MiniBoss", { Phase = "Phase", Key = def.Key, Id = e.Id, Index = e.Phase, Name = ph.Name, Text = ph.Text, Main = enc and enc.Main })
		run:Banner(def.Title .. " · " .. ph.Name, ph.Text, if enc and enc.Main then "Boss" else "MiniBoss")
		if enc and enc.Main then
			mainPhase(run, e, e.Phase)
		end
	end
end

---------------------------------------------------------------------------
-- the fights
---------------------------------------------------------------------------
function MiniBosses.Init(run, e, opts)
	e.Encounter = opts.Encounter
	e.HomeX = opts.HomeX or e.X
	e.HomeZ = opts.HomeZ or e.Z
	e.Timers = e.Timers or {}
	e.Busy = e.Busy or 0
	e.SentHP = -1
	e.SentFlags = -1
	e.HandT = 0
	e.HandA = run.Rng:NextNumber(0, TAU)
	e.HourA = e.HandA + math.pi
	e.Ticks = 0
	e.Phase = 1
	e.Rate = 1
	if run.Mods and run.Mods.BossRage then
		e.Rate = 1.15 -- BOSS RAGE: every boss fights a little faster from the start
	end
end

-- a point towards (x, z), but not further than `reach` from the lair
local function nearHome(e, x: number, z: number, reach: number): (number, number)
	local dx, dz = x - e.HomeX, z - e.HomeZ
	local d = sqrt(dx * dx + dz * dz)
	if d > reach then
		return e.HomeX + dx / d * reach, e.HomeZ + dz / d * reach
	end
	return x, z
end

local function timer(e, name: string, first: number): number
	local t = e.Timers[name]
	if t == nil then
		t = first
		e.Timers[name] = t
	end
	return t
end

local function barrage(run, e, count: number, radius: number, spread: number, delay: number, damage: number)
	local rng = run.Rng
	for i = 1, count do
		local x, z = run.PX, run.PZ
		if i > 1 then
			local a = rng:NextNumber(0, TAU)
			local r = rng:NextNumber(4, spread)
			x, z = run.PX + cos(a) * r, run.PZ + sin(a) * r
		end
		telegraph(run, e, SHAPE.Circle, x, z, 0, radius, 0, windup(run, delay) + (i - 1) * 0.1, damage, "Slam")
	end
end

local function ring(run, e, count: number, speed: number, damage: number, offset: number, EM)
	for i = 1, count do
		local a = offset + (i / count) * TAU
		EM.Shoot(run, e.X, e.Z, cos(a) * speed, sin(a) * speed, 1.3, damage, 4.5)
	end
end

local AI = {}

-- THE BIG QUACK: flops onto you (ring of drops + a slippery puddle), calls ducklings
function AI.BigQuack(run, e, dx, dz, d, dt, EM)
	local p = e.Def.Params
	if e.FlopT then
		e.FlopT += dt
		local f = min(1, e.FlopT / e.FlopDur)
		e.X = e.FromX + (e.ToX - e.FromX) * f
		e.Z = e.FromZ + (e.ToZ - e.FromZ) * f
		if f >= 1 then
			e.FlopT = nil
			e.Air = false
			state(run, e, ES.Normal)
			ring(run, e, p.DropCount, p.DropSpeed, p.DropDamage * e.DmgScale, run.Rng:NextNumber(0, TAU), EM)
			telegraph(run, e, SHAPE.Puddle, e.X, e.Z, 0, p.PuddleRadius, p.PuddleTime, 0.05, 0, nil, p.PuddleSlow)
			MiniBosses.Expose(run, e, "Flop")
			if e.Enraged then
				local a = run.Rng:NextNumber(0, TAU)
				telegraph(run, e, SHAPE.Puddle, e.X + cos(a) * 11, e.Z + sin(a) * 11, 0, p.PuddleRadius * 0.8, p.PuddleTime, 0.05, 0, nil, p.PuddleSlow)
			end
		end
		return 0, 0, 0
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	local rate = e.Rate
	e.Timers.Flop = timer(e, "Flop", p.FlopEvery * 0.35) - dt * rate
	e.Timers.Duck = timer(e, "Duck", p.DucklingEvery * 0.6) - dt * rate
	if e.Timers.Flop <= 0 then
		e.Timers.Flop = p.FlopEvery
		local tx, tz = nearHome(e, run.PX, run.PZ, LAIR.Leash + 8)
		local delay = windup(run, p.FlopDelay)
		telegraph(run, e, SHAPE.Circle, tx, tz, 0, p.FlopRadius, 0, delay, p.FlopDamage * e.DmgScale, "Land")
		e.FromX, e.FromZ, e.ToX, e.ToZ = e.X, e.Z, tx, tz
		e.FlopT, e.FlopDur = 0, delay
		e.Air = true
		state(run, e, ES.Dash)
		return 0, 0, 0
	elseif e.Timers.Duck <= 0 then
		e.Timers.Duck = p.DucklingEvery
		local bx, bz = -dx / d, -dz / d
		for i = 1, p.DucklingCount do
			EM.Spawn(run, "Duckling", e.X + bx * (e.Radius + i * 2.2), e.Z + bz * (e.Radius + i * 2.2), { Force = true })
		end
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 1
end

-- CARTZILLA: a chain of charges along red lines, spills behind, prices from the sky
local function aimCharge(run, e, p)
	local dx, dz = run.PX - e.X, run.PZ - e.Z
	local d = max(0.1, sqrt(dx * dx + dz * dz))
	e.DirX, e.DirZ = dx / d, dz / d
	local w = windup(run, p.DashWindup)
	e.DashAt = run.Time + w
	e.DashDamage = p.DashDamage * e.DmgScale
	telegraph(run, e, SHAPE.DashLine, e.X, e.Z, atan2(e.DirZ, e.DirX), p.DashLength, e.Radius * 2, w, 0)
	state(run, e, ES.Windup)
end

function AI.Cartzilla(run, e, dx, dz, d, dt, _EM)
	local p = e.Def.Params
	local now = run.Time
	if e.Dashing then
		local step = p.DashSpeed * dt
		e.DashLeft -= step
		e.SpillAcc += step
		if e.SpillAcc >= p.SpillEvery then
			e.SpillAcc = 0
			telegraph(run, e, SHAPE.Spill, e.X, e.Z, 0, p.SpillRadius, p.SpillTime, 0.05, p.SpillDamage * e.DmgScale)
		end
		if e.DashLeft <= 0 then
			e.Dashing = false
			state(run, e, ES.Normal)
			e.DashesLeft -= 1
			if e.DashesLeft > 0 then
				e.NextDashAt = now + 0.35
			else
				MiniBosses.Expose(run, e, "Charge") -- dizzy after the chain
			end
		end
		return e.DirX, e.DirZ, p.DashSpeed / e.Speed
	end
	if e.DashAt then
		if now >= e.DashAt then
			e.DashAt = nil
			e.Dashing = true
			e.DashLeft = p.DashLength
			e.SpillAcc = 0
			state(run, e, ES.Dash)
			return e.DirX, e.DirZ, p.DashSpeed / e.Speed
		end
		return 0, 0, 0
	end
	if e.NextDashAt then
		if now >= e.NextDashAt then
			e.NextDashAt = nil
			aimCharge(run, e, p)
		end
		return 0, 0, 0
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	e.Timers.Charge = timer(e, "Charge", p.ChargeEvery * 0.3) - dt * e.Rate
	e.Timers.Price = timer(e, "Price", p.PriceEvery * 0.7) - dt * e.Rate
	if e.Timers.Charge <= 0 then
		e.Timers.Charge = p.ChargeEvery
		e.DashesLeft = p.Dashes + (if e.Enraged then 1 else 0)
		aimCharge(run, e, p)
		return 0, 0, 0
	elseif e.Timers.Price <= 0 then
		e.Timers.Price = p.PriceEvery
		barrage(run, e, p.PriceCount, p.PriceRadius, p.PriceSpread, p.PriceDelay, p.PriceDamage * e.DmgScale)
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 0.8
end

-- JACKPOT JIMMY: the reels decide; half-way down it tilts behind a shield of coin stacks
local REEL_ORDER = { "Ring", "Cross", "Bombs", "Jackpot" }

local function spinResult(run, p, shielded: boolean): string
	local total = 0
	for _, key in REEL_ORDER do
		if not (shielded and key == "Jackpot") then
			total += p.Reels[key] or 0
		end
	end
	local r = run.Rng:NextNumber(0, total)
	for _, key in REEL_ORDER do
		if not (shielded and key == "Jackpot") then
			r -= p.Reels[key] or 0
			if r <= 0 then
				return key
			end
		end
	end
	return "Ring"
end

local function resolveSpin(run, e, p, result: string, EM)
	local scale = e.DmgScale
	if result == "Ring" then
		ring(run, e, p.RingCount, p.RingSpeed, p.RingDamage * scale, run.Rng:NextNumber(0, TAU), EM)
		e.SecondRingAt = run.Time + 0.55
	elseif result == "Cross" then
		local base = run.Rng:NextNumber(0, math.pi)
		for i = 1, p.CrossCount do
			local a = base + (i - 1) * (math.pi / p.CrossCount)
			local half = p.CrossLength / 2
			telegraph(run, e, SHAPE.Laser, run.PX - cos(a) * half, run.PZ - sin(a) * half, a, p.CrossLength, p.CrossWidth, windup(run, p.CrossDelay) + (i - 1) * 0.15, p.CrossDamage * scale, "Sweep")
		end
	elseif result == "Bombs" then
		barrage(run, e, p.BombCount, p.BombRadius, p.BombSpread, p.BombDelay, p.BombDamage * scale)
	else
		-- 7-7-7: coins everywhere, and it is stunned (hit it now)
		for i = 1, p.JackpotCoins do
			local a = (i / p.JackpotCoins) * TAU
			Pickups.SpawnItem(run, "Coin", e.X + cos(a) * (e.Radius + 3), e.Z + sin(a) * (e.Radius + 3))
		end
		e.StunnedUntil = run.Time + p.StunTime
		run:Write("Fx", 0, e.X, e.Z, 0, 10, 0, GFX.Jackpot)
		run:Event("MiniBoss", { Phase = "Jackpot", Key = "JackpotJimmy", Id = e.Id, Time = p.StunTime })
		MiniBosses.Expose(run, e, "Jackpot")
	end
end

local function tilt(run, e, p, EM)
	e.Tilted = true
	e.Shielded = true
	e.Pylons = {}
	local base = run.Rng:NextNumber(0, TAU)
	for i = 1, p.PylonCount do
		local a = base + (i / p.PylonCount) * TAU
		local x, z = e.HomeX + cos(a) * p.PylonDistance, e.HomeZ + sin(a) * p.PylonDistance
		if EM.InsideCollider(run, x, z, 2) then
			x, z = e.HomeX + cos(a) * p.PylonDistance * 0.6, e.HomeZ + sin(a) * p.PylonDistance * 0.6
		end
		local py = EM.Spawn(run, "CoinStack", x, z, { Force = true })
		if py then
			py.Owner = e
			table.insert(e.Pylons, py)
		end
	end
	run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 2, 0, GFX.Enrage)
	run:Event("MiniBoss", { Phase = "Shield", Key = "JackpotJimmy", Id = e.Id, Pylons = #e.Pylons })
	run:Banner("TILT!", "Break the " .. #e.Pylons .. " coin stacks to drop its shield", "MiniBoss")
end

function AI.JackpotJimmy(run, e, dx, dz, d, dt, EM)
	local p = e.Def.Params
	local now = run.Time
	if not e.Tilted and e.Phase >= 2 then
		tilt(run, e, p, EM)
	end
	if e.Shielded then
		local standing = 0
		for _, py in e.Pylons do
			if py.Alive then
				standing += 1
			end
		end
		if standing == 0 then
			e.Shielded = false
			run:Write("Fx", 0, e.X, e.Z, 0, e.Radius * 3, 0, GFX.Jackpot)
			run:Event("MiniBoss", { Phase = "ShieldDown", Key = "JackpotJimmy", Id = e.Id })
		end
	end
	if e.SecondRingAt and now >= e.SecondRingAt then
		e.SecondRingAt = nil
		ring(run, e, p.RingCount, p.RingSpeed, p.RingDamage * e.DmgScale, run.Rng:NextNumber(0, TAU), EM)
	end
	if e.SpinAt and now >= e.SpinAt then
		e.SpinAt = nil
		state(run, e, ES.Normal)
		resolveSpin(run, e, p, e.SpinResult, EM)
	end
	if e.StunnedUntil and now < e.StunnedUntil then
		return 0, 0, 0
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	e.Timers.Spin = timer(e, "Spin", p.SpinEvery * 0.35) - dt * (if e.Shielded then 1.3 else 1) * e.Rate
	if e.Timers.Spin <= 0 and not e.SpinAt then
		e.Timers.Spin = p.SpinEvery
		e.SpinResult = spinResult(run, p, e.Shielded == true)
		e.SpinAt = now + p.SpinTime
		run:Event("Reels", { Id = e.Id, Result = e.SpinResult, Time = p.SpinTime })
		state(run, e, ES.Windup)
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 0.7
end

-- SIX: keeps its distance, fans out six shots
function AI.Six(run, e, dx, dz, d, dt, EM)
	local p = e.Def.Params
	if not e.Engaged then
		return 0, 0, 0
	end
	e.Timers.Fan = timer(e, "Fan", p.FanEvery * 0.5) - dt * e.Rate
	if e.Timers.Fan <= 0 then
		e.Timers.Fan = p.FanEvery
		local base = atan2(dz, dx)
		local n = p.FanShots
		for i = 1, n do
			local a = base + (i - (n + 1) / 2) * (p.FanSpread / (n - 1))
			EM.Shoot(run, e.X, e.Z, cos(a) * p.FanSpeed, sin(a) * p.FanSpeed, 1.2, p.FanDamage * e.DmgScale, 3.5)
		end
	end
	if d < p.Keep - 2 then
		return -dx / d, -dz / d, 1
	elseif d > p.Keep + 4 then
		return dx / d, dz / d, 1
	end
	return -dz / d * e.Side, dx / d * e.Side, 0.7
end

-- SEVEN: walks up to you and lays seven mines where you are heading
function AI.Seven(run, e, dx, dz, d, dt, _EM)
	local p = e.Def.Params
	if e.Busy > 0 then
		e.Busy -= dt
		if e.Busy <= 0 then
			state(run, e, ES.Normal)
		end
		return 0, 0, 0
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	e.Timers.Mine = timer(e, "Mine", p.MineEvery * 0.4) - dt * e.Rate
	if e.Timers.Mine <= 0 then
		e.Timers.Mine = p.MineEvery
		local fx, fz = run.FX, run.FZ
		local rng = run.Rng
		for i = 0, p.MineCount - 1 do
			local x = run.PX + fx * (2 + i * 4.5) + rng:NextNumber(-1, 1)
			local z = run.PZ + fz * (2 + i * 4.5) + rng:NextNumber(-1, 1)
			telegraph(run, e, SHAPE.Circle, x, z, 0, p.MineRadius, 0, windup(run, p.MineDelay) + i * 0.08, p.MineDamage * e.DmgScale, "Slam")
		end
		e.Busy = 0.45
		state(run, e, ES.Windup)
		return 0, 0, 0
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 1
end

-- TICK TOCK: two laser hands sweep around it while you are close; TOCK slams where you stand
function AI.TickTock(run, e, dx, dz, d, dt, _EM)
	local p = e.Def.Params
	if d < p.HandLength + 16 then
		e.HandT -= dt * e.Rate
		if e.HandT <= 0 then
			e.HandT = p.HandEvery
			e.Ticks += 1
			e.HandA += p.HandSpeed * p.HandEvery
			local delay = windup(run, p.HandDelay)
			telegraph(run, e, SHAPE.Laser, e.X, e.Z, e.HandA, p.HandLength, p.HandWidth, delay, p.HandDamage * e.DmgScale, "Sweep")
			if e.Ticks % 2 == 0 then
				-- the hour hand: shorter, slower, the other way round
				e.HourA -= p.HandSpeed * 0.5 * p.HandEvery * 2
				telegraph(run, e, SHAPE.Laser, e.X, e.Z, e.HourA, p.HandLength * 0.55, p.HandWidth, delay, p.HandDamage * e.DmgScale, "Sweep")
			end
		end
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	e.Timers.Tock = timer(e, "Tock", p.TockEvery * 0.5) - dt * e.Rate
	if e.Timers.Tock <= 0 then
		e.Timers.Tock = p.TockEvery
		local delay = windup(run, p.TockDelay)
		telegraph(run, e, SHAPE.Circle, run.PX, run.PZ, 0, p.TockRadius, 0, delay, p.TockDamage * e.DmgScale, "Slam")
		e.PendingExpose = { Reason = "Tock", At = run.Time + delay }
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 0.6
end


---------------------------------------------------------------------------
-- the lair bosses of the harder tiers
---------------------------------------------------------------------------
-- a line on its name plate: what to do now
local function cue(run, e, text: string, time: number?)
	run:Event("BossCue", { Id = e.Id, Text = text, Time = time or 2.5 })
end

-- aims a straight charge at you: a red line, then it goes
local function aimDash(run, e, seconds: number, length: number, damage: number)
	local dx, dz = run.PX - e.X, run.PZ - e.Z
	local d = max(0.1, sqrt(dx * dx + dz * dz))
	e.DirX, e.DirZ = dx / d, dz / d
	local w = windup(run, seconds)
	e.DashAt = run.Time + w
	e.DashLen = length
	e.DashDamage = damage * e.DmgScale
	telegraph(run, e, SHAPE.DashLine, e.X, e.Z, atan2(e.DirZ, e.DirX), length, e.Radius * 2, w, 0)
	state(run, e, ES.Windup)
end

-- SIR SNAILSALOT: tucks into its shell (half damage), rolls down a line leaving slime, peeks out
local function aimRoll(run, e, p)
	aimDash(run, e, p.RollWindup, p.RollLength, p.RollDamage)
	e.ArmorCut = p.ShellArmor
end

function AI.SirSnailsalot(run, e, dx, dz, d, dt, EM)
	local p = e.Def.Params
	local now = run.Time
	if e.Dashing then
		local step = p.RollSpeed * dt
		e.DashLeft -= step
		e.SlimeAcc += step
		if e.SlimeAcc >= p.SlimeEvery then
			e.SlimeAcc = 0
			telegraph(run, e, SHAPE.Puddle, e.X, e.Z, 0, p.SlimeRadius, p.SlimeTime * (if e.Enraged then 1.5 else 1), 0.05, 0, nil, p.SlimeSlow)
		end
		if e.DashLeft <= 0 then
			e.Dashing = false
			e.RollsLeft -= 1
			if e.RollsLeft > 0 then
				e.NextDashAt = now + 0.5
			else
				-- it peeks out: soft and slow for a moment
				e.ArmorCut = nil
				state(run, e, ES.Normal)
				MiniBosses.Expose(run, e, "Peek")
			end
		end
		return e.DirX, e.DirZ, p.RollSpeed / e.Speed
	end
	if e.DashAt then
		if now >= e.DashAt then
			e.DashAt = nil
			e.Dashing = true
			e.DashLeft = e.DashLen
			e.SlimeAcc = 0
			state(run, e, ES.Dash)
			return e.DirX, e.DirZ, p.RollSpeed / e.Speed
		end
		return 0, 0, 0
	end
	if e.NextDashAt then
		if now >= e.NextDashAt then
			e.NextDashAt = nil
			aimRoll(run, e, p)
		end
		return 0, 0, 0
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	e.Timers.Roll = timer(e, "Roll", p.RollEvery * 0.4) - dt * e.Rate
	e.Timers.Spit = timer(e, "Spit", p.SpitEvery * 0.7) - dt * e.Rate
	if e.Timers.Roll <= 0 then
		e.Timers.Roll = p.RollEvery
		e.RollsLeft = if e.Enraged then 2 else 1
		aimRoll(run, e, p)
		return 0, 0, 0
	elseif e.Timers.Spit <= 0 then
		e.Timers.Spit = p.SpitEvery
		local base = atan2(dz, dx)
		for i = 1, p.SpitShots do
			local a = base + (i - (p.SpitShots + 1) / 2) * (p.SpitSpread / (p.SpitShots - 1))
			EM.Shoot(run, e.X, e.Z, cos(a) * p.SpitSpeed, sin(a) * p.SpitSpeed, 1.3, p.SpitDamage * e.DmgScale, 3.5)
		end
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 0.7
end

-- THE SCARECROW: two spins of its stick arms (a wide fan), crows; its pumpkin is soft after
function AI.Scarecrow(run, e, dx, dz, d, dt, EM)
	local p = e.Def.Params
	if e.Busy > 0 then
		e.Busy -= dt
		if e.Busy <= 0 then
			state(run, e, ES.Normal)
		end
		return 0, 0, 0
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	e.Timers.Spin = timer(e, "Spin", p.SpinEvery * 0.4) - dt * e.Rate
	e.Timers.Crow = timer(e, "Crow", p.CrowEvery * 0.6) - dt * e.Rate
	if e.Timers.Spin <= 0 then
		e.Timers.Spin = p.SpinEvery
		local arms = p.SpinArms + (if e.Enraged then 1 else 0)
		local base = atan2(dz, dx)
		local delay = windup(run, p.SpinDelay)
		for turn = 0, 1 do
			for k = 0, arms - 1 do
				local a = base + k * TAU / arms + turn * p.SpinTurn
				telegraph(run, e, SHAPE.Sector, e.X, e.Z, a, p.SpinRadius, p.SpinArc / 2, delay + turn * (delay + 0.3), p.SpinDamage * e.DmgScale, "Sector")
			end
		end
		local done = delay * 2 + 0.3
		e.Busy = done
		e.PendingExpose = { Reason = "Spin", At = run.Time + done }
		state(run, e, ES.Windup)
		return 0, 0, 0
	elseif e.Timers.Crow <= 0 then
		e.Timers.Crow = p.CrowEvery
		for i = 1, p.CrowCount + (if e.Enraged then 2 else 0) do
			local a = i * TAU / p.CrowCount
			EM.Spawn(run, "Crow", e.X + cos(a) * (e.Radius + 3), e.Z + sin(a) * (e.Radius + 3), { Force = true })
		end
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 0.8
end

-- SELF-CHECKOUT: scanner beams across the lot (an ERROR after: its screen is open), and an
-- UNEXPECTED ITEM: a mark under you that blows up and scatters items
function AI.SelfCheckout(run, e, dx, dz, d, dt, EM)
	local p = e.Def.Params
	if e.Busy > 0 then
		e.Busy -= dt
		if e.Busy <= 0 then
			state(run, e, ES.Normal)
		end
		return 0, 0, 0
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	e.Timers.Scan = timer(e, "Scan", p.ScanEvery * 0.35) - dt * e.Rate
	e.Timers.Mark = timer(e, "Mark", p.MarkEvery * 0.7) - dt * e.Rate * (if e.Enraged then 1.3 else 1)
	if e.Timers.Scan <= 0 then
		e.Timers.Scan = p.ScanEvery
		local delay = windup(run, p.ScanDelay)
		local last = 0
		for set = 0, (if e.Enraged then 1 else 0) do
			local a = run.Rng:NextNumber(0, math.pi) + set * math.pi / 2
			local ux, uz = cos(a), sin(a)
			local nx, nz = -uz, ux
			for i = 1, p.ScanCount do
				local off = (i - (p.ScanCount + 1) / 2) * p.ScanSpacing
				local cx, cz = run.PX + nx * off, run.PZ + nz * off
				local half = p.ScanLength / 2
				local at = delay + (i - 1) * p.ScanGap + set * 0.2
				last = max(last, at)
				telegraph(run, e, SHAPE.Laser, cx - ux * half, cz - uz * half, a, p.ScanLength, p.ScanWidth, at, p.ScanDamage * e.DmgScale, "Sweep")
			end
		end
		e.Busy = last
		e.PendingExpose = { Reason = "Error", At = run.Time + last + 0.1 }
		Bosses.After(run, e, last + 0.1, function()
			cue(run, e, "ERROR · SCREEN OPEN", 2)
		end)
		state(run, e, ES.Windup)
		return 0, 0, 0
	elseif e.Timers.Mark <= 0 then
		e.Timers.Mark = p.MarkEvery
		local x, z = run.PX, run.PZ
		local delay = windup(run, p.MarkDelay)
		telegraph(run, e, SHAPE.Circle, x, z, 0, p.MarkRadius, 0, delay, p.MarkDamage * e.DmgScale, "Slam")
		cue(run, e, "UNEXPECTED ITEM IN THE BAGGING AREA", delay)
		Bosses.After(run, e, delay, function(_, _, em)
			Bosses.GapRing(run, em, x, z, p.MarkShots, 0, run.Rng:NextNumber(0, TAU), p.MarkSpeed, p.MarkShotDamage * e.DmgScale, 1.2, 3)
		end)
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 0.6
end

-- THE MANNEQUIN: red light, green light. You move: it freezes. You stop: it lunges.
function AI.Mannequin(run, e, dx, dz, d, dt, EM)
	local p = e.Def.Params
	local now = run.Time
	if e.Dashing then
		e.DashLeft -= p.DashSpeed * dt
		if e.DashLeft <= 0 then
			e.Dashing = false
			e.DashesLeft -= 1
			if e.DashesLeft > 0 then
				aimDash(run, e, p.DashWindup, p.DashLength, p.DashDamage)
			else
				-- it topples over
				e.RestUntil = now + p.DashRest
				state(run, e, ES.Stunned)
				MiniBosses.Expose(run, e, "Topple")
			end
		end
		return e.DirX, e.DirZ, p.DashSpeed / e.Speed
	end
	if e.DashAt then
		if now >= e.DashAt then
			e.DashAt = nil
			e.Dashing = true
			e.DashLeft = e.DashLen
			state(run, e, ES.Dash)
			return e.DirX, e.DirZ, p.DashSpeed / e.Speed
		end
		return 0, 0, 0
	end
	if e.RestUntil then
		if now < e.RestUntil then
			return 0, 0, 0
		end
		e.RestUntil = nil
		state(run, e, ES.Normal)
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	-- pose change: a ring of shots, whatever you do
	e.Timers.Pose = timer(e, "Pose", p.PoseEvery * 0.6) - dt * e.Rate
	if e.Timers.Pose <= 0 then
		e.Timers.Pose = p.PoseEvery
		Bosses.GapRing(run, EM, e.X, e.Z, p.PoseShots, 0, run.Rng:NextNumber(0, TAU), p.PoseSpeed, p.PoseDamage * e.DmgScale, 1.3, 4)
	end
	local still = run.StillFor >= p.Still
	if still ~= e.Watching then
		e.Watching = still
		cue(run, e, if still then "IT SEES YOU STOP: MOVE!" else "FROZEN · KEEP MOVING", 1.5)
	end
	if not still then
		return 0, 0, 0 -- you move: it is a mannequin
	end
	if d < p.DashLength - 4 then
		e.DashesLeft = if e.Enraged then 2 else 1
		aimDash(run, e, p.DashWindup, p.DashLength, p.DashDamage)
		return 0, 0, 0
	end
	return dx / d, dz / d, 1.3
end

-- DJ DROP: everything on the beat. A ring with a gap every RingBeats beats (its speakers flash
-- RingWindup beats before), and every DropEvery seconds THE DROP: rings with their gaps lined up
function AI.DJDrop(run, e, dx, dz, d, dt, EM)
	local p = e.Def.Params
	if not e.Engaged then
		return 0, 0, 0
	end
	local beat = p.Beat / e.Rate
	e.BeatT = (e.BeatT or 0) + dt
	e.DropT = (e.DropT or p.DropEvery * 0.6) - dt
	local scale = e.DmgScale
	if e.DropT <= 0 and not e.DropLeft then
		e.DropT = p.DropEvery
		e.DropLeft = p.DropRings
		e.DropIn = windup(run, p.DropBuild)
		e.DropGap = atan2(dz, dx) + run.Rng:NextNumber(-0.8, 0.8)
		cue(run, e, "THE DROP IN 3... 2... 1...", e.DropIn)
		telegraph(run, e, SHAPE.DashLine, e.X, e.Z, e.DropGap, 28, 7, e.DropIn, 0)
		state(run, e, ES.Windup)
	end
	if e.DropLeft then
		e.BeatT = 0 -- the beat waits for the drop
		e.DropIn -= dt
		if e.DropIn <= 0 then
			e.DropIn = beat
			e.DropLeft -= 1
			Bosses.GapRing(run, EM, e.X, e.Z, p.RingCount, p.RingGap, e.DropGap, p.RingSpeed, p.DropDamage * scale, 1.3, 4)
			if e.DropLeft <= 0 then
				e.DropLeft = nil
				state(run, e, ES.Normal)
				MiniBosses.Expose(run, e, "Drop")
			end
		end
		return 0, 0, 0
	end
	while e.BeatT >= beat do
		e.BeatT -= beat
		e.Beats = (e.Beats or 0) + 1
		local k = e.Beats % p.RingBeats
		if k == (p.RingBeats - p.RingWindup) % p.RingBeats then
			-- the speakers flash: a ring in RingWindup beats
			e.GapA = (e.GapA or atan2(dz, dx)) + p.GapStep
			telegraph(run, e, SHAPE.DashLine, e.X, e.Z, e.GapA, 24, 6, beat * p.RingWindup, 0)
			state(run, e, ES.Windup)
		elseif k == 0 and e.GapA then
			Bosses.GapRing(run, EM, e.X, e.Z, p.RingCount, p.RingGap, e.GapA, p.RingSpeed, p.RingDamage * scale, 1.3, 4)
			state(run, e, ES.Normal)
		end
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 0.6
end

-- ROULETTE ROLLER: calls the safe colour, then the other colour's sectors burn; ZERO stuns it
local COLOURS = { "RED", "BLACK" }
function AI.RouletteRoller(run, e, dx, dz, d, dt, EM)
	local p = e.Def.Params
	local now = run.Time
	if e.StunnedUntil and now < e.StunnedUntil then
		return 0, 0, 0
	end
	if e.SpinAt then
		if now >= e.SpinAt then
			e.SpinAt = nil
			local n = p.Sectors + (if e.Enraged then 4 else 0)
			local half = math.pi / n
			local delay = windup(run, p.SectorDelay)
			for k = 0, n - 1 do
				local a = e.WheelA + (k + 0.5) * TAU / n
				if k % 2 + 1 ~= e.Safe then
					telegraph(run, e, SHAPE.Sector, e.X, e.Z, a, p.SectorRadius, half, delay, p.SectorDamage * e.DmgScale, "Sector")
				else
					telegraph(run, e, SHAPE.SafeSector, e.X, e.Z, a, p.SectorRadius, half, delay, 0)
				end
			end
			e.Busy = delay
		end
		return 0, 0, 0
	end
	if e.Busy > 0 then
		e.Busy -= dt
		if e.Busy <= 0 then
			state(run, e, ES.Normal)
		end
		return 0, 0, 0
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	e.Timers.Spin = timer(e, "Spin", p.SpinEvery * 0.4) - dt * e.Rate
	e.Timers.Ball = timer(e, "Ball", p.BallEvery * 0.7) - dt * e.Rate
	if e.Timers.Spin <= 0 then
		e.Timers.Spin = p.SpinEvery
		-- ZERO now and then (never more than ZeroEvery spins apart: a sure opening)
		e.SinceZero = (e.SinceZero or 0) + 1
		if run.Rng:NextNumber() < p.ZeroChance or e.SinceZero >= p.ZeroEvery then
			e.SinceZero = 0
			-- ZERO: nobody wins, it is stunned (hit it now)
			e.StunnedUntil = now + p.StunTime
			run:Write("Fx", 0, e.X, e.Z, 0, 10, 0, GFX.Jackpot)
			cue(run, e, "ZERO! HIT IT!", p.StunTime)
			MiniBosses.Expose(run, e, "Zero")
			return 0, 0, 0
		end
		e.Safe = run.Rng:NextInteger(1, 2)
		e.WheelA = run.Rng:NextNumber(0, TAU)
		e.SpinAt = now + windup(run, p.SpinTime)
		cue(run, e, "SAFE: " .. COLOURS[e.Safe], p.SpinTime + p.SectorDelay)
		state(run, e, ES.Windup)
		return 0, 0, 0
	elseif e.Timers.Ball <= 0 then
		e.Timers.Ball = p.BallEvery
		local base = run.Rng:NextNumber(0, TAU)
		for i = 0, p.BallShots - 1 do
			Bosses.After(run, e, i * 0.09, function(_, _, em)
				local a = base + i * 0.7
				em.Shoot(run, e.X, e.Z, cos(a) * p.BallSpeed, sin(a) * p.BallSpeed, 1.3, p.BallDamage * e.DmgScale, 4)
			end)
		end
	end
	if d < e.Radius + PLAYER_R + 0.5 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 0.8
end

-- THE MIRROR: walks the path you walked, Behind seconds late; shards at you, echoes on your
-- path, a long dash at you (it cracks after it)
function AI.TheMirror(run, e, dx, dz, d, dt, EM)
	local p = e.Def.Params
	local now = run.Time
	if e.Dashing then
		e.DashLeft -= p.DashSpeed * dt
		if e.DashLeft <= 0 then
			e.Dashing = false
			state(run, e, ES.Normal)
			MiniBosses.Expose(run, e, "Crack")
		end
		return e.DirX, e.DirZ, p.DashSpeed / e.Speed
	end
	if e.DashAt then
		if now >= e.DashAt then
			e.DashAt = nil
			e.Dashing = true
			e.DashLeft = e.DashLen
			state(run, e, ES.Dash)
			return e.DirX, e.DirZ, p.DashSpeed / e.Speed
		end
		return 0, 0, 0
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	local rate = e.Rate
	e.Timers.Shot = timer(e, "Shot", p.ShotEvery * 0.5) - dt * rate
	e.Timers.Echo = timer(e, "Echo", p.EchoEvery * 0.6) - dt * rate
	e.Timers.Dash = timer(e, "Dash", p.DashEvery * 0.7) - dt * rate
	if e.Timers.Dash <= 0 then
		e.Timers.Dash = p.DashEvery
		aimDash(run, e, p.DashWindup, p.DashLength, p.DashDamage)
		return 0, 0, 0
	elseif e.Timers.Echo <= 0 then
		e.Timers.Echo = p.EchoEvery
		local pts = run:TrailPoints(2.6, 0.4)
		local n = min(p.EchoCount + (if e.Enraged then 3 else 0), #pts)
		local delay = windup(run, p.EchoDelay)
		for i = 1, n do
			local pt = pts[max(1, math.floor(i * #pts / n))]
			telegraph(run, e, SHAPE.Circle, pt.X, pt.Z, 0, p.EchoRadius, 0, delay + (i - 1) * 0.1, p.EchoDamage * e.DmgScale, "Slam")
		end
	elseif e.Timers.Shot <= 0 then
		e.Timers.Shot = p.ShotEvery
		local base = atan2(dz, dx)
		for i = 1, p.ShotCount do
			local a = base + (i - (p.ShotCount + 1) / 2) * p.ShotSpread
			EM.Shoot(run, e.X, e.Z, cos(a) * p.ShotSpeed, sin(a) * p.ShotSpeed, 1.2, p.ShotDamage * e.DmgScale, 3)
		end
	end
	-- the path you walked, a little late
	local tx, tz = run:PathAt(p.Behind)
	local ox, oz = tx - e.X, tz - e.Z
	local od = sqrt(ox * ox + oz * oz)
	if od < 1 then
		return 0, 0, 0
	end
	return ox / od, oz / od, math.clamp(od / 6, 0.6, 1.5)
end

-- THE EVENT HORIZON: a pulsing pull, ring waves coming in from the edge, and COLLAPSE:
-- everything burns but a few white safe circles
function AI.EventHorizon(run, e, dx, dz, d, dt, EM)
	local p = e.Def.Params
	local now = run.Time
	if e.Well then
		e.Well.X, e.Well.Z = e.X, e.Z
	end
	if e.Busy > 0 then
		e.Busy -= dt
		if e.Busy <= 0 then
			state(run, e, ES.Normal)
		end
		return 0, 0, 0
	end
	if not e.Engaged then
		return 0, 0, 0
	end
	local rate = e.Rate
	e.Timers.Pull = timer(e, "Pull", p.PullEvery * 0.3) - dt * rate
	e.Timers.Wave = timer(e, "Wave", p.WaveEvery * 0.6) - dt * rate
	e.Timers.Collapse = timer(e, "Collapse", p.CollapseEvery * 0.8) - dt * rate
	if e.Timers.Pull <= 0 then
		e.Timers.Pull = p.PullEvery
		local slow = if e.Enraged then p.PullSlow - 0.08 else p.PullSlow
		e.Well = run:AddWell(e.X, e.Z, p.PullRadius, slow, p.PullTime)
		run:Write("Fx", 0, e.X, e.Z, 0, p.PullRadius, p.PullTime, GFX.Gravity)
	end
	if e.Timers.Collapse <= 0 then
		e.Timers.Collapse = p.CollapseEvery
		local delay = windup(run, p.CollapseDelay)
		local safe = {}
		local n = p.SafeCount - (if e.Phase >= 3 then 1 else 0)
		for i = 1, n do
			local x, z
			if i == 1 then
				-- one is always within reach of you
				local a = run.Rng:NextNumber(0, TAU)
				local r = run.Rng:NextNumber(6, 11)
				x, z = run.PX + cos(a) * r, run.PZ + sin(a) * r
			else
				local a = run.Rng:NextNumber(0, TAU)
				local r = run.Rng:NextNumber(8, p.CollapseRadius * 0.75)
				x, z = e.X + cos(a) * r, e.Z + sin(a) * r
			end
			table.insert(safe, { X = x, Z = z, R = p.SafeRadius })
			telegraph(run, e, SHAPE.Safe, x, z, 0, p.SafeRadius, 0, delay, 0)
		end
		telegraph(run, e, SHAPE.Circle, e.X, e.Z, 0, p.CollapseRadius, 0, delay, p.CollapseDamage * e.DmgScale, "Slam", nil, { Safe = safe })
		cue(run, e, "COLLAPSE: STAND IN A WHITE CIRCLE", delay)
		e.Busy = delay
		e.PendingExpose = { Reason = "Collapse", At = now + delay }
		state(run, e, ES.Windup)
		return 0, 0, 0
	elseif e.Timers.Wave <= 0 then
		e.Timers.Wave = p.WaveEvery
		local gapA = atan2(-dz, -dx) + run.Rng:NextNumber(-0.9, 0.9) -- (seen from it: towards you)
		local delay = windup(run, 1.0)
		telegraph(run, e, SHAPE.DashLine, e.X, e.Z, gapA, p.WaveRadius, 6, delay, 0)
		local cx, cz = e.X, e.Z
		Bosses.After(run, e, delay, function(_, _, em)
			Bosses.InwardRing(run, em, cx, cz, p.WaveRadius, p.WaveCount, p.WaveGap, gapA, p.WaveSpeed, p.WaveDamage * e.DmgScale)
		end)
	end
	if d < e.Radius + PLAYER_R + 2 then
		return 0, 0, 0
	end
	return dx / d, dz / d, 0.5
end

-- THE 67 PRIME, phase 1: SIX and SEVEN fight like the twins of the Rift
AI.PrimeSix = AI.Six
AI.PrimeSeven = AI.Seven


MiniBosses.AI = AI

-- the lair / arena rules around a boss's own fight: movement intent (dirX, dirZ, speed mult)
function MiniBosses.Step(run, e, dx: number, dz: number, d: number, dt: number, EM): (number, number, number)
	local now = run.Time
	local enc = e.Encounter
	MiniBosses.StepPhase(run, e)
	Bosses.RunQueue(run, e, EM)
	if e.PendingExpose and now >= e.PendingExpose.At then
		MiniBosses.Expose(run, e, e.PendingExpose.Reason)
		e.PendingExpose = nil
	end
	local busy = e.Air or e.Dashing or e.DashAt or e.NextDashAt or e.FlopT or e.LeapToX
	local classic = AI[e.Key] == nil
	if enc and enc.Main then
		-- THE FINAL ONE: waits until you step into the arena, then the arena is sealed
		local pdx, pdz = run.PX - enc.X, run.PZ - enc.Z
		local inside = pdx * pdx + pdz * pdz <= (MAIN.ArenaR - 1) ^ 2
		if not run.Map.ArenaSealed then
			if not inside then
				e.Engaged = false
				return 0, 0, 0
			end
			run.Map.ArenaSealed = { X = enc.X, Z = enc.Z, R = MAIN.ArenaR }
			run:Write("Fx", 0, enc.X, enc.Z, 0, MAIN.ArenaR, 0, GFX.Seal)
			run:Event("Arena", { Sealed = true, X = enc.X, Z = enc.Z, R = MAIN.ArenaR })
			run:Banner("THE ARENA IS SEALED", "Only one of you walks out.", "Boss")
		end
		e.Engaged = true
		enc.Engaged = true
		enc.LastEngaged = now
	else
		-- lair bosses: you ran away -> walk home and heal (nothing mid-leap / mid-charge)
		local hx, hz = e.HomeX, e.HomeZ
		local pdx, pdz = run.PX - hx, run.PZ - hz
		if not busy and pdx * pdx + pdz * pdz > LAIR.Reset * LAIR.Reset then
			e.Engaged = false
			local ox, oz = hx - e.X, hz - e.Z
			local home = sqrt(ox * ox + oz * oz)
			e.GoingHome = true
			if home > 2 then
				return ox / home, oz / home, 1.2
			end
			e.HP = min(e.MaxHP, e.HP + e.MaxHP * LAIR.Regen * dt)
			return 0, 0, 0
		end
		e.GoingHome = false
		e.Engaged = d <= LAIR.Aggro
		if e.Engaged and enc then
			enc.LastEngaged = now
			if not enc.Engaged then
				enc.Engaged = true
				-- TICK TOCK: 67 seconds from the moment the fight starts
				if enc.Def.Timer then
					enc.AlarmAt = now + enc.Def.Timer
					run:Event("MiniBoss", { Phase = "Timer", Key = enc.Def.Key, Id = e.Id, Timer = enc.Def.Timer })
				end
			end
		end
	end
	local mx, mz, mult = 0, 0, 0
	if classic then
		-- a classic boss (Sim/Bosses): it only attacks once the fight is on
		if e.Engaged or busy then
			mx, mz, mult = Bosses.Step(run, e, dx, dz, d, dt, EM)
		end
	else
		mx, mz, mult = AI[e.Key](run, e, dx, dz, d, dt, EM)
	end
	-- the leash: never too far from the lair (charges and leaps may overshoot, then come back)
	if not (enc and enc.Main) and not busy and not e.Air and not e.Dashing then
		local hx, hz = e.HomeX, e.HomeZ
		local ox, oz = hx - e.X, hz - e.Z
		local home = sqrt(ox * ox + oz * oz)
		if home > LAIR.Leash then
			local k = math.clamp((home - LAIR.Leash) / 6, 0, 1)
			mx = mx * (1 - k) + ox / home * k
			mz = mz * (1 - k) + oz / home * k
			local len = sqrt(mx * mx + mz * mz)
			if len > 1e-3 then
				mx, mz = mx / len, mz / len
			end
			mult = max(mult, 0.8)
		end
	end
	return mx, mz, mult
end

return MiniBosses
