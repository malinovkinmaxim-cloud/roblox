--[[
	Run - one survivor run of one player. PURE simulation: no Instances, no services.

	GameManager feeds it the player's position every step (SetPlayer) and ships its output
	to the client:
	  run.Out     binary records for the next network frame (shared/Protocol.lua)
	  run.Events  list of { Name, Payload } reliable events (offers, banners, bosses, death...)

	The same object runs headless in tests/ with a bot at the controls.

	Step order: WaveManager (spawns, bosses, events) -> EnemyManager (AI, movement, contact)
	-> CombatManager (weapons, projectiles, allies) -> Pickups (gems, items) -> level ups.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Shared.GameConfig)
local Stats = require(Shared.Stats)
local Protocol = require(Shared.Protocol)
local CharacterData = require(Shared.CharacterData)
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
	Character: string?,
	Meta: { [string]: number }?, -- permanent upgrade levels
	Unlocked: { [string]: boolean }?, -- weapons that can be offered
	StartWeapon: string?,
	MaxEnemies: number?,
	Colliders: any?,
	StartX: number?,
	StartZ: number?,
	MidBoss: string?,
}

local RARE_STATS = {
	Mewing = { Crit = 0.1, CritMult = 1 },
	AuraFarming = { Growth = 0.25, Magnet = 0.6, Regen = 1 },
	Overdrive = { AttackSpeed = 0.25, ProjSpeed = 0.25 },
}

function Run.new(opts: Options)
	local self = setmetatable({}, Run)
	self.Seed = opts.Seed or math.random(1, 2 ^ 30)
	self.Rng = Random.new(self.Seed)
	self.Character = if opts.Character and CharacterData.ByKey[opts.Character] then opts.Character else CharacterData.Default
	self.Meta = opts.Meta or {}
	self.Unlocked = opts.Unlocked or {}
	self.MaxEnemies = opts.MaxEnemies or GameConfig.Sim.MaxEnemiesPerRun
	self.Colliders = opts.Colliders

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

	-- build
	self.Weapons = {}
	self.Passives = {}
	self.PassiveOrder = {}
	self.Rares = {}
	self.Buffs = {}
	self.CharStats = table.clone(CharacterData.ByKey[self.Character].Stats)
	if self.Character == "SixSeven" then
		for stat, range in CharacterData.RandomRolls do
			self.CharStats[stat] = (self.CharStats[stat] or 0) + self.Rng:NextNumber(range[1], range[2])
		end
	end
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
	self.Allies = {}
	self.Pending = {} -- delayed weapon impacts
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

	-- results / achievements
	self.Result = {
		Bosses = {},
		EnemyKills = {},
		Rares = 0,
		Crates = 0,
		Gems = 0,
		Events67 = 0,
		Flags = {},
		MaxWeapons = 0,
		Awakened = 0,
	}

	self:RefreshStats()
	self.HP = self.Stats.MaxHP
	self.Rerolls = self.Stats.Rerolls + GameConfig.LevelUp.FreeRerolls
	self.Revives = self.Stats.Revives

	-- starting weapons
	local start = CharacterData.ByKey[self.Character].StartWeapon
	if opts.StartWeapon and WeaponData.ByKey[opts.StartWeapon] and self.Unlocked[opts.StartWeapon] then
		start = opts.StartWeapon
	end
	self:AddWeapon(start)
	for _ = 1, self.Stats.ExtraWeapons do
		local pool = {}
		for _, def in WeaponData.List do
			if self.Unlocked[def.Key] and not self:GetWeapon(def.Key) and def.Rarity == "Common" then
				table.insert(pool, def.Key)
			end
		end
		if #pool > 0 then
			self:AddWeapon(pool[self.Rng:NextInteger(1, #pool)])
		end
	end

	WaveManager.Init(self, opts.MidBoss)
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

function Run:AddWeapon(key: string)
	if self:GetWeapon(key) then
		return
	end
	local def = WeaponData.Get(key)
	local w = {
		Key = key,
		Id = def.Id,
		Def = def,
		Level = 1,
		Awakened = false,
		Timer = 0.4 + #self.Weapons * 0.15, -- first shot comes quickly, weapons don't fire in sync
		HitAt = {},
		S = {},
	}
	table.insert(self.Weapons, w)
	self.Result.MaxWeapons = math.max(self.Result.MaxWeapons, #self.Weapons)
	self:RefreshStats()
	self:SendLoadout()
end

function Run:Sources()
	local passives = {}
	for key, stacks in self.Passives do
		local def = UpgradeData.PassiveByKey[key]
		if def then
			passives[def.Stat] = (passives[def.Stat] or 0) + def.Value * stacks
		end
	end
	local sources = { self.CharStats, self.MetaStats, passives }
	for key in self.Rares do
		local extra = RARE_STATS[key]
		if extra then
			table.insert(sources, extra)
		end
	end
	if self:Buff("Sigma") then
		table.insert(sources, { Might = 0.5, MoveSpeed = 0.35 })
	end
	if self:Buff("Damage67") then
		table.insert(sources, { Might = 0.67 })
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
		w.S = Stats.Weapon(w.Key, w.Level, w.Awakened, self.Stats)
	end
	self.StatsDirty = true
end

-- Loadout for the HUD and client-side weapon visuals (orbit radius, aura size...)
function Run:SendLoadout()
	local weapons = {}
	for _, w in self.Weapons do
		table.insert(weapons, {
			Key = w.Key,
			Level = w.Level,
			Awakened = w.Awakened,
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
	local rares = {}
	for key, stacks in self.Rares do
		table.insert(rares, { Key = key, Stacks = stacks })
	end
	table.sort(rares, function(a, b)
		return a.Key < b.Key
	end)
	self:Event("Loadout", {
		Weapons = weapons,
		Passives = passives,
		Rares = rares,
		Slots = self.Stats.WeaponSlots,
		WalkSpeed = self.Stats.WalkSpeed,
		PickupRange = self.Stats.PickupRange,
		Rerolls = self.Rerolls,
		Revives = self.Revives,
		Mog = self.Character == "Sigma",
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
	if not had then
		self:RefreshStats()
		self:SendLoadout()
	end
	self:Event("Buff", { Key = key, Duration = self.Buffs[key] - self.Time })
end

function Run:UpdateBuffs()
	for key, untilTime in self.Buffs do
		if untilTime <= self.Time then
			self.Buffs[key] = nil
			self:RefreshStats()
			self:SendLoadout()
			self:Event("BuffEnd", { Key = key })
		end
	end
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
	if self:Buff("XP67") then
		mult *= 1.67
	end
	if self:Buff("Storm") then
		mult *= 2
	end
	self.XP += amount * mult
	while self.XP >= GameConfig.XPNeeded(self.Level) do
		self.XP -= GameConfig.XPNeeded(self.Level)
		self.Level += 1
		self.PendingLevels += 1
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
	local dmg = math.max(1, amount - self.Stats.Armor)
	self.HP -= dmg
	self.DamageTaken += dmg
	self.LastHurtAt = self.Time
	self:Write("Hurt", dmg)
	if self.HP <= 0 then
		self.HP = 0
		self:OnZeroHP()
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
	self:Write("Fx", 0, self.PX, self.PZ, 0, 22, 0, 9)
	self:Event("Revived", { Source = source, Revives = self.Revives })
	self:SendLoadout()
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

	-- regeneration (+ THE NPC stands still and heals)
	local regen = self.Stats.Regen
	if self.Moved < 0.05 then
		self.StillFor += dt
		if self.Character == "TheNPC" then
			regen += 3
		end
	else
		self.StillFor = 0
	end
	if regen > 0 and self.HP < self.Stats.MaxHP then
		self.HP = math.min(self.Stats.MaxHP, self.HP + regen * dt)
	end

	if self.SigmaModeAt and self.Time >= self.SigmaModeAt then
		self.SigmaModeAt = self.Time + 40
		self:AddBuff("Sigma", 10)
		self:Banner("SIGMA MODE", "+50% damage, +35% speed", "Sigma")
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
	if self:Buff("Sigma") then
		flags += Protocol.Flags.Sigma
	end
	if self:Buff("Storm") then
		flags += Protocol.Flags.Storm
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
	local awakened = 0
	for _, w in self.Weapons do
		if w.Awakened then
			awakened += 1
		end
	end
	local r = self.Result
	return {
		Character = self.Character,
		Reason = self.EndReason or "Quit",
		Victory = self.Victory,
		Time = math.floor(self.Time),
		Level = self.Level,
		Kills = self.Kills,
		Coins = self.Coins,
		Bosses = table.clone(r.Bosses),
		EnemyKills = table.clone(r.EnemyKills),
		Weapons = r.MaxWeapons,
		Awakened = math.max(r.Awakened, awakened),
		Rares = r.Rares,
		Crates = r.Crates,
		Gems = r.Gems,
		Events67 = r.Events67,
		Flags = table.clone(r.Flags),
		DamageTaken = math.floor(self.DamageTaken),
		Build = self:BuildSummary(),
	}
end

function Run:BuildSummary()
	local weapons = {}
	for _, w in self.Weapons do
		table.insert(weapons, { Key = w.Key, Level = w.Level, Awakened = w.Awakened })
	end
	return { Weapons = weapons }
end

return Run
