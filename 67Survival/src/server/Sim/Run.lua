--[[
	Run - one survivor run of one player. PURE simulation: no Instances, no services.

	GameManager feeds it the player's position every step (SetPlayer) and ships its output
	to the client:
	  run.Out     binary records for the next network frame (shared/Protocol.lua)
	  run.Events  list of { Name, Payload } reliable events (offers, banners, bosses, death...)

	The same object runs headless in tests/ with a bot at the controls.

	Step order: WaveManager (spawns, bosses, 67 events) -> EnemyManager (AI, movement,
	contact, burning) -> CombatManager (abilities, projectiles, zones, allies) -> Pickups
	(gems, items) -> level ups.

	Hero mechanics (shared/HeroData.lua Mechanic) live here and in the modules above.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local Stats = require(Shared.Stats)
local Protocol = require(Shared.Protocol)
local HeroData = require(Shared.HeroData)
local UpgradeData = require(Shared.UpgradeData)
local WeaponData = require(Shared.WeaponData)
local MetaData = require(Shared.MetaData)

local SpatialGrid = require(script.Parent.SpatialGrid)
local EnemyManager = require(script.Parent.EnemyManager)
local CombatManager = require(script.Parent.CombatManager)
local WaveManager = require(script.Parent.WaveManager)
local Pickups = require(script.Parent.Pickups)
local LevelUp = require(script.Parent.LevelUp)

local Run = {}
Run.__index = Run

export type Options = {
	Seed: number?,
	Hero: string?,
	Meta: { [string]: number }?, -- permanent upgrade levels
	Unlocked: { [string]: boolean }?, -- abilities that can be offered (weapons + secret passives)
	StartWeapon: string?,
	MaxEnemies: number?,
	Colliders: any?,
	StartX: number?,
	StartZ: number?,
	BossPicks: { string }?, -- forced boss of each timeline slot (tests)
	LiveEvent: { [string]: number }?, -- limited-time event modifiers (EventRate...)
	Follower: boolean?, -- party member: 67 events come from the party leader's run
}

-- buff key -> bonus stats while it is active
local BUFF_STATS = {
	P67 = { Might = 0.67 },
	Luck67 = { Luck = 3 },
	TurboMode = { AttackSpeed = 0.67, MoveSpeed = 0.5 },
	GlassMode = { Might = 1 },
}

function Run.new(opts: Options)
	local self = setmetatable({}, Run)
	self.Seed = opts.Seed or math.random(1, 2 ^ 30)
	self.Rng = Random.new(self.Seed)
	self.Hero = if opts.Hero and HeroData.ByKey[opts.Hero] then opts.Hero else HeroData.Default
	local hero = HeroData.ByKey[self.Hero]
	self.Mech = hero.Mechanic
	self.Meta = opts.Meta or {}
	self.Unlocked = opts.Unlocked or {}
	self.MaxEnemies = opts.MaxEnemies or GameConfig.Sim.MaxEnemiesPerRun
	self.BaseMaxEnemies = self.MaxEnemies
	self.Colliders = opts.Colliders
	self.LiveEvent = opts.LiveEvent or {}
	self.Follower = opts.Follower == true

	self.Time = 0
	self.Steps = 0
	self.Out = Protocol.NewWriter(2048)
	self.Events = {}
	self.FrameHits = 0

	-- player
	self.PX, self.PZ = opts.StartX or 0, opts.StartZ or 0
	self.FX, self.FZ = 0, -1 -- facing (unit)
	self.Moved = 0
	self.Level = 1
	self.XP = 0
	self.Kills = 0
	self.Coins = 0
	self.HurtTimer = 0
	self.LastHurtAt = -99
	self.DamageTaken = 0
	self.Invulnerable = 0
	self.RobuxRevived = false
	self.StillFor = 0
	self.Shield = 0 -- Barrier charges
	self.GlitchReadyAt = 0 -- THE GLITCH hero
	self.StreakStacks = 0 -- THE VOID hero
	self.LastKillAt = -99
	self.TeleportTo = nil -- set when the hero teleports (GameManager moves the character)

	-- build
	self.Weapons = {}
	self.Passives = {}
	self.PassiveOrder = {}
	self.Buffs = {}
	self.EvoAnnounced = {}
	self.CharStats = table.clone(hero.Stats)
	self.MetaStats = {}
	for key, level in self.Meta do
		local def = MetaData.ByKey[key]
		if def and type(level) == "number" then
			local l = math.clamp(math.floor(level), 0, def.MaxLevel)
			self.MetaStats[def.Stat] = (self.MetaStats[def.Stat] or 0) + def.PerLevel * l
		end
	end

	-- world
	self.Enemies = {} -- array (swap-remove)
	self.EnemyById = {}
	self.Grid = SpatialGrid.new(GameConfig.Sim.GridCell)
	self.Gems = {}
	self.Items = {}
	self.Projectiles = {}
	self.EnemyProjectiles = {}
	self.Telegraphs = {}
	self.Hazards = {}
	self.Zones = {}
	self.Allies = {}
	self.Drones = {}
	self.Pending = {} -- delayed weapon impacts
	self.Decoy = nil -- Clone ability
	self.Boss = nil
	self.NextUid = 0

	-- run state
	self.Offer = nil
	self.PendingLevels = 0
	self.PendingChests = 0
	self.PausedFor = 0
	self.UserPaused = false
	self.Dead = false
	self.DeadFor = 0
	self.Ended = false
	self.EndReason = nil
	self.Victory = false
	self.VictoryAt = nil

	-- results / achievements / collection
	self.Result = {
		Bosses = {},
		EnemyKills = {},
		Rares = 0,
		Crates = 0,
		Gems = 0,
		Events67 = 0,
		EventsSeen = {},
		Picked = {}, -- ability keys picked this run (collection)
		Evolutions = {},
		Flags = {},
		MaxWeapons = 0,
		Fragments = 0,
		LowestHP = math.huge,
	}

	self:RefreshStats()
	self.HP = self.Stats.MaxHP
	self.Rerolls = self.Stats.Rerolls + GameConfig.LevelUp.FreeRerolls
	self.Revives = self.Stats.Revives

	-- starting abilities
	local start = hero.StartWeapon
	if opts.StartWeapon and WeaponData.IsBase(opts.StartWeapon) and self.Unlocked[opts.StartWeapon] then
		start = opts.StartWeapon
	end
	self:AddWeapon(start)
	local extra = self.Stats.ExtraWeapons + (if self.Mech == "Unknown" then 2 else 0)
	for _ = 1, extra do
		local pool = {}
		for _, def in WeaponData.List do
			if self.Unlocked[def.Key] and WeaponData.IsBase(def.Key) and not self:GetWeapon(def.Key) and def.Rarity ~= "Secret" and def.Rarity ~= "Legendary" then
				table.insert(pool, def.Key)
			end
		end
		if #pool > 0 then
			self:AddWeapon(pool[self.Rng:NextInteger(1, #pool)])
		end
	end

	WaveManager.Init(self, opts.BossPicks)
	return self
end

---------------------------------------------------------------------------
-- output
---------------------------------------------------------------------------
function Run:Write(name: string, ...: number)
	Protocol.Write(self.Out, name, ...)
end

function Run:Event(name: string, payload: any?)
	table.insert(self.Events, { Name = name, Payload = payload or {} })
end

function Run:Banner(title: string, sub: string?, style: string?)
	self:Event("Banner", { Title = title, Sub = sub or "", Style = style or "Info" })
end

function Run:NewUid(): number
	self.NextUid += 1
	return self.NextUid
end

---------------------------------------------------------------------------
-- build & stats
---------------------------------------------------------------------------
function Run:GetWeapon(key: string)
	for _, w in self.Weapons do
		if w.Key == key then
			return w
		end
	end
	return nil
end

local function newWeapon(key: string, timer: number)
	local def = WeaponData.Get(key)
	return {
		Key = key,
		Id = def.Id,
		Def = def,
		Level = 1,
		Timer = timer, -- first shot comes quickly, weapons don't fire in sync
		HitAt = {},
		S = {},
		Count = 0,
	}
end

function Run:AddWeapon(key: string)
	if self:GetWeapon(key) then
		return
	end
	table.insert(self.Weapons, newWeapon(key, 0.4 + #self.Weapons * 0.15))
	self.Result.Picked[key] = true
	self.Result.MaxWeapons = math.max(self.Result.MaxWeapons, #self.Weapons)
	self:RefreshStats()
	self:SendLoadout()
end

-- replaces a max-level ability with its evolution (same slot)
function Run:Evolve(baseKey: string): boolean
	local evo = WeaponData.EvolutionOf[baseKey]
	for i, w in self.Weapons do
		if w.Key == baseKey and evo then
			self.Weapons[i] = newWeapon(evo.Key, 0.2)
			self.Result.Picked[evo.Key] = true
			table.insert(self.Result.Evolutions, evo.Key)
			if #self.Result.Evolutions >= 5 then
				self.Result.Flags.FiveEvolutions = true
			end
			self:RefreshStats()
			self:SendLoadout()
			self:Write("Fx", 0, self.PX, self.PZ, 0, 14, evo.Id, Protocol.Fx.Evolve)
			self:Banner(evo.Name, "EVOLVED", "Evolution")
			return true
		end
	end
	return false
end

-- base abilities whose evolution can be taken right now
function Run:EvolutionsReady(): { string }
	local out = {}
	for _, w in self.Weapons do
		local evo = WeaponData.EvolutionOf[w.Key]
		if evo and w.Level >= w.Def.MaxLevel and (self.Passives[evo.Evolution.With] or 0) > 0 then
			table.insert(out, w.Key)
		end
	end
	return out
end

-- tells the player once per ability: EVOLUTION AVAILABLE
function Run:CheckEvolutions()
	for _, key in self:EvolutionsReady() do
		if not self.EvoAnnounced[key] then
			self.EvoAnnounced[key] = true
			local evo = WeaponData.EvolutionOf[key]
			self:Event("EvolutionReady", { Key = key, Evolution = evo.Key, Title = evo.Name })
		end
	end
end

function Run:Sources()
	local passives = {}
	for key, stacks in self.Passives do
		local def = UpgradeData.PassiveByKey[key]
		if def then
			for stat, value in def.Stats do
				passives[stat] = (passives[stat] or 0) + value * stacks
			end
		end
	end
	local sources = { self.CharStats, self.MetaStats, passives }
	for key, bonus in BUFF_STATS do
		if self:Buff(key) then
			table.insert(sources, bonus)
		end
	end
	return sources
end

function Run:RefreshStats()
	local oldMax = self.Stats and self.Stats.MaxHP
	self.Stats = Stats.Compute(self:Sources())
	if oldMax and self.Stats.MaxHP > oldMax and self.HP then
		self.HP = math.min(self.Stats.MaxHP, self.HP + (self.Stats.MaxHP - oldMax))
	end
	if self.HP then
		self.HP = math.min(self.HP, self.Stats.MaxHP)
	end
	for _, w in self.Weapons do
		w.S = Stats.Weapon(w.Key, w.Level, self.Stats)
		-- hero mechanics that change one ability
		if self.Mech == "DroneBay" and w.Def.Kind == "Drone" then
			w.S.Amount += 1
			w.S.Damage *= 1.25
		elseif self.Mech == "ArcaneEcho" and (w.Def.Kind == "Missile" or w.Def.Kind == "Projectile") then
			w.S.Amount += 1
		end
	end
	self.StatsDirty = true
end

-- dynamic multipliers (change every step, applied at hit / fire time)
function Run:DamageMult(e): number
	local m = 1 + self.StreakStacks * 0.01
	if self.Mech == "Headhunter" and e and (e.IsBoss or e.Elite) then
		m *= 1.4
	end
	return m
end

function Run:FireRate(): number
	local missing = 1 - math.clamp(self.HP / math.max(1, self.Stats.MaxHP), 0, 1)
	local rate = 1 + self.Stats.Berserk * missing
	if self.Mech == "Redline" then
		rate += 0.6 * missing
	end
	return rate
end

-- Loadout for the HUD and client-side ability visuals (orbit radius, aura size...)
function Run:SendLoadout()
	local weapons = {}
	for _, w in self.Weapons do
		table.insert(weapons, {
			Key = w.Key,
			Level = w.Level,
			MaxLevel = w.Def.MaxLevel,
			Evolved = w.Def.Evolution ~= nil,
			Amount = w.S.Amount,
			Radius = w.S.Radius or 0,
			Orbit = w.S.Orbit or 0,
			Speed = w.S.Speed or 0,
		})
	end
	local passives = {}
	for _, key in self.PassiveOrder do
		table.insert(passives, { Key = key, Stacks = self.Passives[key] })
	end
	self:Event("Loadout", {
		Weapons = weapons,
		Passives = passives,
		Slots = self.Stats.WeaponSlots,
		WalkSpeed = self.Stats.WalkSpeed,
		PickupRange = self.Stats.PickupRange,
		Rerolls = self.Rerolls,
		Revives = self.Revives,
		EvoReady = self:EvolutionsReady(),
	})
end

---------------------------------------------------------------------------
-- buffs
---------------------------------------------------------------------------
function Run:Buff(key: string): boolean
	local untilTime = self.Buffs[key]
	return untilTime ~= nil and untilTime > self.Time
end

function Run:AddBuff(key: string, duration: number)
	local had = self:Buff(key)
	self.Buffs[key] = math.max(self.Buffs[key] or 0, self.Time + duration)
	if not had and BUFF_STATS[key] then
		self:RefreshStats()
		self:SendLoadout()
	end
	self:Event("Buff", { Key = key, Duration = self.Buffs[key] - self.Time })
end

function Run:UpdateBuffs()
	for key, untilTime in self.Buffs do
		if untilTime <= self.Time then
			self.Buffs[key] = nil
			if BUFF_STATS[key] then
				self:RefreshStats()
				self:SendLoadout()
			end
			self:Event("BuffEnd", { Key = key })
		end
	end
end

-- any 67 event running (a screen tint on the client)
function Run:EventActive(): boolean
	return self.Wave ~= nil and self.Wave.EventUntil > self.Time
end

---------------------------------------------------------------------------
-- player
---------------------------------------------------------------------------
function Run:SetPlayer(x: number, z: number, fx: number?, fz: number?)
	if x ~= x or z ~= z then
		return
	end
	local h = GameConfig.Arena.HalfSize + 10
	x, z = math.clamp(x, -h, h), math.clamp(z, -h, h)
	local dx, dz = x - self.PX, z - self.PZ
	local moved = math.sqrt(dx * dx + dz * dz)
	self.Moved = moved
	if moved > 0.05 then
		self.FX, self.FZ = dx / moved, dz / moved
	elseif fx and fz and fx == fx and fz == fz and (fx * fx + fz * fz) > 0.01 then
		local len = math.sqrt(fx * fx + fz * fz)
		self.FX, self.FZ = fx / len, fz / len
	end
	self.PX, self.PZ = x, z
end

function Run:AddXP(amount: number)
	local mult = self.Stats.Growth
	if self:Buff("P67") then
		mult *= 1.67
	end
	if self:Buff("XPStorm") then
		mult *= 2
	end
	if self:Buff("GiantMode") then
		mult *= 2
	end
	if self.Mech == "Hoarder" then
		mult *= 1.15
	end
	self.XP += amount * mult
	while self.XP >= GameConfig.XPNeeded(self.Level) do
		self.XP -= GameConfig.XPNeeded(self.Level)
		self.Level += 1
		self.PendingLevels += 1
		-- every level up patches you up a little (early levels come fast: a natural safety net)
		self:Heal(GameConfig.LevelUp.Heal + (if self.Mech == "QuickStudy" and self.Level <= 6 then 15 else 0))
	end
end

function Run:AddCoins(amount: number)
	local n = math.max(0, math.floor(amount * self.Stats.Greed + 0.5))
	if n > 0 then
		self.Coins += n
		self:Write("Coin", n)
	end
end

function Run:Heal(amount: number)
	if self.Dead or amount <= 0 then
		return
	end
	local before = self.HP
	self.HP = math.min(self.Stats.MaxHP, self.HP + amount)
	local healed = self.HP - before
	if healed >= 1 then
		self:Write("Heal", healed)
	end
end

-- THE GLITCH: blink away from the nearest crowd instead of taking the hit
function Run:GlitchStep(): boolean
	local ax, az = 0, 0
	for _, e in self.Enemies do
		local dx, dz = self.PX - e.X, self.PZ - e.Z
		local d2 = dx * dx + dz * dz
		if d2 < 144 and d2 > 0.01 then
			local d = math.sqrt(d2)
			ax += dx / d
			az += dz / d
		end
	end
	local len = math.sqrt(ax * ax + az * az)
	if len < 0.01 then
		local a = self.Rng:NextNumber(0, math.pi * 2)
		ax, az, len = math.cos(a), math.sin(a), 1
	end
	ax, az = ax / len, az / len
	local distance = 10
	local h = GameConfig.Arena.HalfSize - 4
	local tx = math.clamp(self.PX + ax * distance, -h, h)
	local tz = math.clamp(self.PZ + az * distance, -h, h)
	self:Write("Fx", 0, self.PX, self.PZ, math.atan2(az, ax), 1, distance, Protocol.Fx.GlitchStep)
	self.PX, self.PZ = tx, tz
	self.TeleportTo = { X = tx, Z = tz }
	self.Invulnerable = math.max(self.Invulnerable, 0.5)
	return true
end

-- Damage to the player. Returns the damage actually taken.
function Run:HurtPlayer(amount: number, ignoreCooldown: boolean?): number
	if self.Dead or self.Ended or self.Invulnerable > 0 then
		return 0
	end
	if not ignoreCooldown then
		if self.HurtTimer > 0 then
			return 0
		end
		self.HurtTimer = GameConfig.Player.HurtCooldown
	end
	-- Barrier: a charge absorbs the hit and explodes
	if self.Shield > 0 then
		self.Shield -= 1
		CombatManager.BarrierBurst(self)
		return 0
	end
	if self.Mech == "GlitchStep" and self.Time >= self.GlitchReadyAt then
		self.GlitchReadyAt = self.Time + 5
		self:GlitchStep()
		return 0
	end
	if self.Mech == "Slipstream" and self.Moved > 0.2 and self.Rng:NextNumber() < 0.2 then
		self:Write("Hurt", 0)
		return 0
	end
	local dmg = math.max(1, amount - self.Stats.Armor)
	if self:Buff("GlassMode") then
		dmg *= 2
	end
	self.HP -= dmg
	self.DamageTaken += dmg
	self.LastHurtAt = self.Time
	self:Write("Hurt", dmg)
	if self.HP <= 0 then
		self.HP = 0
		self:OnZeroHP()
	elseif self.HP < self.Result.LowestHP then
		self.Result.LowestHP = self.HP
		if self.HP <= math.max(1, self.Stats.MaxHP * 0.02) then
			self.OneHPAt = self.Time -- survive 5 more seconds for the 1 HP secret
		end
	end
	return dmg
end

function Run:OnZeroHP()
	if self.Revives > 0 then
		self.Revives -= 1
		self:Revive("Free")
		return
	end
	self.Dead = true
	self.DeadFor = 0
	self:Event("Died", { CanBuyRevive = not self.RobuxRevived, Window = GameConfig.Run.DeathReviveWindow })
end

function Run:Revive(source: string)
	self.Dead = false
	self.DeadFor = 0
	if source == "Robux" then
		self.RobuxRevived = true
	end
	self.HP = math.max(1, math.floor(self.Stats.MaxHP * GameConfig.Player.ReviveHeal))
	self.Invulnerable = GameConfig.Player.ReviveInvulnerable
	-- a shockwave pushes the horde back
	EnemyManager.Shockwave(self, self.PX, self.PZ, 22, 30, 0)
	self:Write("Fx", 0, self.PX, self.PZ, 0, 22, 0, Protocol.Fx.Revive)
	self:Event("Revived", { Source = source, Revives = self.Revives })
	self:SendLoadout()
end

-- called by EnemyManager for every kill (hero mechanics and kill passives)
function Run:OnKill(e)
	local now = self.Time
	if self.Mech == "VoidHunger" then
		if now - self.LastKillAt <= 2 then
			self.StreakStacks = math.min(40, self.StreakStacks + 1)
		else
			self.StreakStacks = 1
		end
	end
	self.LastKillAt = now
	if self.Stats.Lifesteal > 0 and self.Rng:NextNumber() < self.Stats.Lifesteal then
		self:Heal(3)
	end
	if self.Mech == "SixtySeven" and self.Kills % 67 == 0 then
		CombatManager.Free67Blast(self)
	end
end

---------------------------------------------------------------------------
-- level up offers (LevelUp.lua builds and applies cards)
---------------------------------------------------------------------------
function Run:IsPaused(): boolean
	return self.Offer ~= nil or self.Dead or self.UserPaused or self.Ended
end

function Run:Choose(index: number): boolean
	return LevelUp.Choose(self, index)
end

function Run:RerollOffer(): boolean
	return LevelUp.Reroll(self)
end

function Run:SkipOffer(): boolean
	return LevelUp.Skip(self)
end

-- a purchased extra reroll (developer product)
function Run:AddRerolls(n: number)
	self.Rerolls += n
	if self.Offer then
		self:Event("Offer", { Kind = self.Offer.Kind, Level = self.Level, Cards = self.Offer.Cards, Rerolls = self.Rerolls })
	end
end

---------------------------------------------------------------------------
-- step
---------------------------------------------------------------------------
function Run:Step(dt: number)
	if self.Ended then
		return
	end
	self.Steps += 1
	if self.Offer then
		self.PausedFor += dt
		if self.PausedFor >= GameConfig.Run.LevelUpAutoPick then
			LevelUp.Choose(self, 1)
		end
		return
	end
	if self.Dead then
		self.DeadFor += dt
		if self.DeadFor >= GameConfig.Run.DeathReviveWindow + 1 + (self.ReviveGrace or 0) then
			self:End("Death")
		end
		return
	end
	if self.UserPaused then
		return
	end

	self.Time += dt
	self.HurtTimer = math.max(0, self.HurtTimer - dt)
	self.Invulnerable = math.max(0, self.Invulnerable - dt)
	self:UpdateBuffs()

	if self.StreakStacks > 0 and self.Time - self.LastKillAt > 2 then
		self.StreakStacks = 0
	end

	local regen = self.Stats.Regen
	if self.Moved < 0.05 then
		self.StillFor += dt
	else
		self.StillFor = 0
	end
	if regen > 0 and self.HP < self.Stats.MaxHP then
		self.HP = math.min(self.Stats.MaxHP, self.HP + regen * dt)
	end

	-- XP Storm passive: every 45 s a few seconds of double XP
	local storm = self.Passives.XPStorm
	if storm then
		self.XPStormAt = self.XPStormAt or (self.Time + 10)
		if self.Time >= self.XPStormAt then
			self.XPStormAt = self.Time + 45
			self:AddBuff("XPStorm", 8 + (storm - 1) * 3)
			self:Banner("XP STORM", "Double XP", "Info")
		end
	end

	-- 1 HP secret: fell to 1-2% HP and survived 5 more seconds
	if self.OneHPAt and self.Time - self.OneHPAt >= 5 and not self.Result.Flags.OneHP then
		self.Result.Flags.OneHP = true
		self:Event("Secret", { Key = "OneHP", Title = "1 HP CLUB", Sub = "That was way too close." })
	end

	WaveManager.Step(self, dt)
	EnemyManager.Step(self, dt)
	CombatManager.Step(self, dt)
	Pickups.Step(self, dt)

	if self.VictoryAt and self.Time >= self.VictoryAt then
		self:End("Victory")
		return
	end
	if not self.Offer and not self.Dead then
		LevelUp.OpenNext(self)
	end
end

function Run:End(reason: string)
	if self.Ended then
		return
	end
	self.Ended = true
	self.EndReason = reason
	self.Victory = reason == "Victory"
	self.Offer = nil
end

---------------------------------------------------------------------------
-- network frame
---------------------------------------------------------------------------
--[[
	Finishes the current frame: State + boss + allies + moved enemy positions are appended
	to the records written during the steps. Returns the buffer (nil if nothing to send).
]]
function Run:Flush(): buffer
	-- the State record goes FIRST (the client needs the frame time before the records)
	local header = self.Header or Protocol.NewWriter(64)
	self.Header = header
	Protocol.Reset(header)
	local flags = 0
	if self:IsPaused() then
		flags += Protocol.Flags.Paused
	end
	if self.Dead then
		flags += Protocol.Flags.Dead
	end
	if self:EventActive() then
		flags += Protocol.Flags.Event67
	end
	if self:Buff("XPStorm") or self:Buff("P67") or self:Buff("GiantMode") then
		flags += Protocol.Flags.XPBoost
	end
	if self.Shield > 0 then
		flags += Protocol.Flags.Shield
	end
	local need = GameConfig.XPNeeded(self.Level)
	Protocol.Write(
		header,
		"State",
		self.Time,
		math.ceil(self.HP),
		self.Stats.MaxHP,
		self.Level,
		math.clamp(self.XP / need, 0, 1) * 65535,
		self.Kills,
		self.Coins,
		flags
	)
	local boss = self.Boss
	if boss and boss.Alive then
		self:Write("Boss", boss.Id, math.max(0, math.ceil(boss.HP)), math.ceil(boss.MaxHP))
	end
	for i, ally in self.Allies do
		self:Write("Ally", i, ally.X, ally.Z)
	end
	for _, e in self.Enemies do
		local dx, dz = e.X - e.SentX, e.Z - e.SentZ
		if dx * dx + dz * dz > 0.0004 then
			e.SentX, e.SentZ = e.X, e.Z
			self:Write("Pos", e.Id, e.X, e.Z)
		end
	end
	local body = self.Out
	local out = buffer.create(header.Pos + body.Pos)
	buffer.copy(out, 0, header.Buf, 0, header.Pos)
	buffer.copy(out, header.Pos, body.Buf, 0, body.Pos)
	Protocol.Reset(body)
	self.FrameHits = 0
	return out
end

-- Pops the reliable events produced since the last call
function Run:TakeEvents()
	local events = self.Events
	self.Events = {}
	return events
end

-- Summary for RewardManager when the run is over
function Run:Summary()
	local r = self.Result
	local picked = {}
	for key in r.Picked do
		table.insert(picked, key)
	end
	table.sort(picked)
	local events = {}
	for key in r.EventsSeen do
		table.insert(events, key)
	end
	table.sort(events)
	return {
		Hero = self.Hero,
		Reason = self.EndReason or "Quit",
		Victory = self.Victory,
		Time = math.floor(self.Time),
		Level = self.Level,
		Kills = self.Kills,
		Coins = self.Coins,
		Bosses = table.clone(r.Bosses),
		EnemyKills = table.clone(r.EnemyKills),
		Weapons = r.MaxWeapons,
		Evolutions = table.clone(r.Evolutions),
		Evolved = #r.Evolutions,
		Picked = picked,
		EventsSeen = events,
		Rares = r.Rares,
		Crates = r.Crates,
		Gems = r.Gems,
		Events67 = r.Events67,
		Fragments = r.Fragments,
		Flags = table.clone(r.Flags),
		DamageTaken = math.floor(self.DamageTaken),
		Build = self:BuildSummary(),
	}
end

function Run:BuildSummary()
	local weapons = {}
	for _, w in self.Weapons do
		table.insert(weapons, { Key = w.Key, Level = w.Level, Evolved = w.Def.Evolution ~= nil })
	end
	local passives = {}
	for _, key in self.PassiveOrder do
		table.insert(passives, { Key = key, Stacks = self.Passives[key] })
	end
	return { Weapons = weapons, Passives = passives }
end

return Run
