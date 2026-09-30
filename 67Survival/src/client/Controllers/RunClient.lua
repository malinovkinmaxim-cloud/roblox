--[[
	RunClient - the client side of a run. Decodes the binary Frames (shared/Protocol.lua) and the
	reliable RunEvents, keeps the interpolation state of every enemy, and hands work to the
	renderers / UI. It never decides anything about the game: all numbers come from the server.

	Interpolation: every enemy keeps two samples (T0, X0, Z0) -> (T1, X1, Z1) in server run time.
	The renderers draw at RenderTime() = estimated server time - DELAY, so movement stays smooth
	between 10 Hz frames.

	67 TOWN state for the map / HUD / minimap / pointers:
	  Encounters  the bosses out right now (by BossData key): slot, where, stage, bodies, timer
	  Minis       per boss / elite body (enemy id): HP fraction, flags, reels, revive countdown
	  Elites      the elites alive (enemy id): name, affixes, where they appeared
	  Arena       THE FINAL ONE's sealed ring ({ X, Z, R }) while it is sealed
	  Map         the rift, the 67 RUSH zone, vaults, what the Compass scouted, visited zones
	  Items       the items you carry ({ Key, Level }), Synergies, Souls, Dash, Plating, Shadow
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Protocol = require(Shared.Protocol)
local GameConfig = require(Shared.GameConfig)
local EnemyData = require(Shared.EnemyData)
local ArenaData = require(Shared.ArenaData)
local Signal = require(Shared.Util.Signal)

local RunClient = {}

local DELAY = 0.12
local FLAGS = Protocol.Flags
local SNAP = GameConfig.Sim.SnapshotEvery / GameConfig.Sim.Rate

function RunClient:Init(controllers)
	self.C = controllers
	self.Active = false
	self.Enemies = {}
	self.Offset = nil :: number?
	self.Time = 0
	self.FrameT = 0
	self.HP, self.MaxHP, self.Level, self.XPFrac, self.Kills, self.Coins = 100, 100, 1, 0, 0, 0
	self.Paused, self.Dead, self.Event67, self.XPBoost, self.Shield = false, false, false, false, false
	self.Loadout = nil
	self.Boss = nil
	self:ResetTown()
	self.Center = GameConfig.Arena.Center
	self.GroundY = GameConfig.Arena.GroundY
	self.Changed = Signal.new()
	self.Started = Signal.new()
	self.Ended = Signal.new()
	self.Stats = { Frames = 0, Bytes = 0, Records = 0 }
	self.Handlers = self:BuildHandlers()
	self.EventHandlers = self:BuildEventHandlers()
end

-- 67 TOWN state of a fresh run
function RunClient:ResetTown()
	self.Encounters = {} :: { [string]: any }
	self.Minis = {} :: { [number]: any }
	self.Elites = {} :: { [number]: any }
	self.Arena = nil :: any
	self.Map = { Rift = false, Hot = nil, HotUntil = 0, HotSoon = nil, VaultSoon = nil, Vaults = {}, Visited = {}, Zone = nil }
	self.Items = {}
	self.Synergies = {}
	self.Souls = nil :: any
	self.Dash = nil :: any
	self.Plating = nil :: any
	self.Shadow = nil :: any
end

-- the zone the local character stands in (arena coordinates of the character)
function RunClient:LocalXZ(): (number?, number?)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil, nil
	end
	local c = self.Center
	return root.Position.X - c.X, root.Position.Z - c.Z
end

-- asks for a DASH (Rocket Skates) in the direction you are walking
function RunClient:RequestDash(): boolean
	local dash = self.Dash
	if not self.Active or self.Paused or self.Dead or not dash or dash.Charges < 1 then
		return false
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local ok, moving = pcall(function()
		return (humanoid :: Humanoid).MoveDirection
	end)
	local dir = if ok and typeof(moving) == "Vector3" then moving else Vector3.zero
	if dir.Magnitude < 0.1 then
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		dir = if root then root.CFrame.LookVector else Vector3.new(0, 0, -1)
	end
	self.C.ClientData:Fire("Dash", dir.X, dir.Z)
	return true
end

function RunClient:World(x: number, z: number, y: number?): Vector3
	local c = self.Center
	return Vector3.new(c.X + x, self.GroundY + (y or 0), c.Z + z)
end

-- server run time the renderers draw at
function RunClient:RenderTime(): number
	if not self.Offset then
		return self.Time
	end
	return os.clock() - self.Offset - DELAY
end

-- best estimate of the current server run time (orbits, cooldown visuals)
function RunClient:Now(): number
	if not self.Offset or self.Paused then
		return self.Time
	end
	return math.min(os.clock() - self.Offset, self.Time + 0.25)
end

-- interpolated arena position of an enemy
function RunClient:EnemyPos(e, rt: number): (number, number)
	local t0, t1 = e.T0, e.T1
	if t1 <= t0 then
		return e.X1, e.Z1
	end
	local a = (rt - t0) / (t1 - t0)
	if a <= 0 then
		return e.X0, e.Z0
	elseif a >= 1.25 then
		a = 1.25
	end
	return e.X0 + (e.X1 - e.X0) * a, e.Z0 + (e.Z1 - e.Z0) * a
end

---------------------------------------------------------------------------
-- frame records
---------------------------------------------------------------------------
function RunClient:BuildHandlers()
	local C = self.C
	local enemies = self.Enemies
	local h = {}

	function h.State(time, hp, maxHp, level, xpFrac, kills, coins, flags)
		local o = os.clock() - time
		local offset = self.Offset
		if not offset or o < offset or o - offset > 0.3 then
			self.Offset = o
		else
			self.Offset = offset + (o - offset) * 0.05
		end
		if level > self.Level and self.Level > 0 then
			C.EffectsController:LevelUpBurst()
		end
		self.Time = time
		self.FrameT = time
		self.HP, self.MaxHP, self.Level, self.XPFrac, self.Kills, self.Coins = hp, maxHp, level, xpFrac / 65535, kills, coins
		self.Paused = bit32.band(flags, FLAGS.Paused) ~= 0
		self.Dead = bit32.band(flags, FLAGS.Dead) ~= 0
		self.Event67 = bit32.band(flags, FLAGS.Event67) ~= 0
		self.XPBoost = bit32.band(flags, FLAGS.XPBoost) ~= 0
		self.Shield = bit32.band(flags, FLAGS.Shield) ~= 0
	end

	function h.Spawn(id, kind, x, z, flags)
		local def = EnemyData.ById[kind]
		if not def then
			return
		end
		local old = enemies[id]
		if old then
			C.EnemyRenderer:Remove(old, 1)
		end
		local t = self.FrameT
		local e = {
			Id = id,
			Def = def,
			Flags = flags,
			X0 = x,
			Z0 = z,
			T0 = t,
			X1 = x,
			Z1 = z,
			T1 = t,
			State = 0,
			SpawnedAt = os.clock(),
		}
		enemies[id] = e
		C.EnemyRenderer:Add(e)
		if e.Def.Boss or e.Def.MiniBoss then
			C.EffectsController:BossArrive(e)
		end
	end

	function h.Death(id, cause)
		local e = enemies[id]
		if not e then
			return
		end
		enemies[id] = nil
		if cause == 0 then
			C.EffectsController:EnemyDied(e)
		end
		C.EnemyRenderer:Remove(e, cause)
	end

	function h.Hit(id, damage, flags)
		local e = enemies[id]
		if not e then
			return
		end
		C.EnemyRenderer:Flash(e)
		C.EffectsController:DamageNumber(e, damage, flags)
	end

	function h.Pos(id, x, z)
		local e = enemies[id]
		if not e then
			return
		end
		local t = self.FrameT
		e.X0, e.Z0 = e.X1, e.Z1
		e.T0 = math.max(e.T1, t - SNAP)
		e.X1, e.Z1, e.T1 = x, z, t
	end

	function h.Blink(id, x, z)
		local e = enemies[id]
		if not e then
			return
		end
		local t = self.FrameT
		local fromX, fromZ = e.X1, e.Z1
		e.X0, e.Z0, e.T0 = x, z, t
		e.X1, e.Z1, e.T1 = x, z, t
		if e.Def.Behavior == "Blink" or e.Def.Behavior == "Boss" then
			C.EffectsController:Glitch(fromX, fromZ, x, z)
		end
	end

	function h.EState(id, state)
		local e = enemies[id]
		if e then
			e.State = state
			C.EnemyRenderer:SetState(e, state)
		end
	end

	function h.Shrink(id)
		local e = enemies[id]
		if e and bit32.band(e.Flags, FLAGS.Tiny) == 0 then
			e.Flags += FLAGS.Tiny
			C.EnemyRenderer:Reskin(e)
		end
	end

	function h.Boss(id, hp, maxHp)
		local boss = self.Boss
		if boss and boss.Id == id then
			boss.HP, boss.MaxHP = hp, maxHp
		end
	end

	function h.GemSpawn(id, x, z, tier)
		C.PickupRenderer:AddGem(id, x, z, tier)
	end
	function h.GemTake(id)
		C.PickupRenderer:TakeGem(id)
	end
	function h.GemTier(id, tier)
		C.PickupRenderer:GemTier(id, tier)
	end
	function h.ItemSpawn(id, kind, x, z)
		C.PickupRenderer:AddItem(id, Protocol.Items[kind] or "Coin", x, z)
	end
	function h.ItemTake(id)
		C.PickupRenderer:TakeItem(id, true)
	end
	function h.ItemGone(id)
		C.PickupRenderer:TakeItem(id, false)
	end
	function h.Ally(i, x, z)
		C.PickupRenderer:Ally(i, x, z, self.FrameT)
	end
	function h.Coin(n)
		C.HudController:CoinPop(n)
		C.SoundController:Play("Coin")
	end
	function h.Fx(weaponId, x, z, angle, p1, p2, variant)
		C.WeaponFx:Fx(weaponId, x, z, angle, p1, p2, variant)
	end
	function h.Proj(id, weaponId, x, z, angle, speed, life, target)
		C.WeaponFx:Projectile(id, weaponId, x, z, angle, speed, life, target)
	end
	function h.ProjEnd(id, x, z, flags)
		C.WeaponFx:ProjectileEnd(id, x, z, flags)
	end
	function h.EProj(id, x, z, vx, vz, radius, life)
		C.WeaponFx:EnemyProjectile(id, x, z, vx, vz, radius, life)
	end
	function h.EProjEnd(id)
		C.WeaponFx:EnemyProjectileEnd(id)
	end
	function h.Telegraph(shape, x, z, angle, size, width, delay)
		C.WeaponFx:Telegraph(shape, x, z, angle, size, width, delay)
	end
	function h.Hurt(damage)
		C.EffectsController:PlayerHurt(damage)
	end
	function h.Heal(amount)
		C.EffectsController:PlayerHealed(amount)
	end
	function h.Slash(_kind, x, z)
		C.EffectsController:Bite(x, z)
	end
	function h.Zone(id, weaponId, x, z, radius, duration)
		C.WeaponFx:Zone(id, weaponId, x, z, radius, duration)
	end
	function h.ZoneEnd(id)
		C.WeaponFx:ZoneEnd(id)
	end
	function h.Clone(x, z, duration)
		C.WeaponFx:Clone(x, z, duration)
	end
	function h.Burn(id, seconds)
		local e = enemies[id]
		if e then
			C.EnemyRenderer:Burn(e, seconds)
		end
	end
	-- 67 TOWN
	function h.MiniHP(id, frac, flags)
		local m = self.Minis[id]
		if not m then
			m = { Id = id }
			self.Minis[id] = m
		end
		m.HP = frac / 65535
		m.Flags = flags
	end
	function h.LootSpawn(id, relicId, x, z)
		C.LootRenderer:Add(id, relicId, x, z)
	end
	function h.LootTake(id)
		C.LootRenderer:Take(id, true)
	end
	function h.LootGone(id)
		C.LootRenderer:Take(id, false)
	end
	function h.Plating(current, max)
		self.Plating = if max > 0 then { HP = current, Max = max } else nil
		C.HudController:SetPlating(self.Plating)
	end
	function h.Shadow(x, z, shown)
		self.Shadow = if shown > 0 then { X = x, Z = z } else nil
		C.WeaponFx:Shadow(self.Shadow)
	end
	function h.Vault(index, state, pct)
		local v = self.Map.Vaults[index] or {}
		v.State, v.Pct = state, pct
		self.Map.Vaults[index] = v
		C.ArenaController:Refresh()
	end
	function h.Dash(charges, max, left)
		self.Dash = { Charges = charges, Max = max, ReadyAt = os.clock() + left, Recharge = if left > 0 then left else (self.Dash and self.Dash.Recharge or 3) }
		C.HudController:SetDash(self.Dash)
	end
	return h
end

function RunClient:OnFrame(buf: any)
	if not self.Active or typeof(buf) ~= "buffer" then
		return
	end
	self.Stats.Frames += 1
	self.Stats.Bytes += buffer.len(buf)
	Protocol.Decode(buf, self.Handlers)
	self.Changed:Fire()
end

---------------------------------------------------------------------------
-- reliable events
---------------------------------------------------------------------------
function RunClient:BuildEventHandlers()
	local C = self.C
	local e = {}

	function e.RunStart(p)
		self:Begin(p)
	end
	function e.Loadout(p)
		self.Loadout = p
		self.Items = p.Items or {}
		self.Synergies = p.Synergies or {}
		C.HudController:SetLoadout(p)
		C.WeaponFx:SetLoadout(p)
	end
	function e.Offer(p)
		C.LevelUpController:Show(p)
	end
	function e.OfferClosed(_p)
		C.LevelUpController:Hide()
	end
	function e.Picked(p)
		C.SoundController:Play(if p.Rarity == "Common" then "Pick" else "Rare")
		if p.Key == "Percent67" then
			C.BannerController:Show("67%", "Something is coming...", "Secret")
		end
	end
	function e.Banner(p)
		C.BannerController:Show(p.Title, p.Sub, p.Style)
	end
	function e.BossWarning(p)
		C.BannerController:BossWarning(p.Title, p.Delay, p.Final)
	end
	function e.BossSpawn(p)
		self.Boss = { Id = p.Id, Key = p.Key, Title = p.Title, HP = p.MaxHP, MaxHP = p.MaxHP, Final = p.Final }
		C.HudController:ShowBoss(self.Boss)
	end
	function e.BossDefeated(p)
		if self.Boss and self.Boss.Id == p.Id then
			self.Boss = nil
		end
		C.HudController:HideBoss()
		C.EffectsController:BossDefeated(p)
	end
	function e.Event67(p)
		C.BannerController:Event67(p)
		C.EffectsController:Event67(p)
	end
	function e.EvolutionReady(p)
		C.HudController:EvolutionReady(p)
		C.SoundController:Play("Rare")
	end
	function e.Fragment(p)
		C.HudController:FragmentPop(p.Total)
		C.SoundController:Play("Fragment")
	end
	function e.Secret(p)
		C.BannerController:Secret(p)
	end
	function e.Buff(p)
		C.HudController:SetBuff(p.Key, p.Duration)
	end
	function e.BuffEnd(p)
		C.HudController:SetBuff(p.Key, 0)
	end
	function e.Died(p)
		C.ResultsController:ShowDeath(p)
	end
	function e.Revived(p)
		C.ResultsController:HideDeath()
		C.EffectsController:Revived(p)
	end
	function e.Nuke(_p)
		C.EffectsController:Flash(Color3.new(1, 1, 1), 0.5)
		C.SoundController:Play("Nuke")
		C.CameraController:Shake(2.5)
	end
	function e.Results(p)
		self:Finish(p)
	end
	-- 67 TOWN
	function e.MiniBoss(p)
		self:OnMiniBoss(p)
	end
	function e.Reels(p)
		local m = self.Minis[p.Id] or { Id = p.Id }
		self.Minis[p.Id] = m
		m.Reels = { Result = p.Result, Until = os.clock() + (p.Time or 1) }
	end
	function e.Item(p)
		C.HudController:ItemGained(p)
		C.SoundController:Play(if p.Maxed then "Coin" else "Relic")
	end
	function e.LockedRelic(p)
		C.BannerController:Toast(
			string.format("%s would have dropped %s", tostring(p.Boss), string.upper(p.Name)),
			"Info",
			string.format("Unlock it for %d CHIPS in ITEMS", p.Price or 0)
		)
	end
	function e.Synergy(p)
		table.insert(self.Synergies, p.Key)
		C.BannerController:Synergy(p)
		C.HudController:SynergyOn(p)
		C.SoundController:Play("Rare")
	end
	function e.Perk(p)
		C.HudController:PerkPop(p)
	end
	function e.Souls(p)
		self.Souls = { Count = p.Count, Max = p.Max }
		C.HudController:SetSouls(self.Souls, p.Lost)
	end
	function e.Elite(p)
		if p.Phase == "Spawn" then
			self.Elites[p.Id] = { Id = p.Id, Key = p.Key, Name = p.Name, Affixes = p.Affixes or {}, X = p.X, Z = p.Z, Zone = p.Zone, Since = os.clock() }
			self.Minis[p.Id] = self.Minis[p.Id] or { Id = p.Id, HP = 1, Flags = 0 }
			self.Minis[p.Id].Elite = true
			C.BannerController:Elite(p)
			C.EnemyRenderer:MarkElite(p.Id, p.Name, p.Affixes or {})
		elseif p.Phase == "Defeated" then
			self.Elites[p.Id] = nil
			self.Minis[p.Id] = nil
			C.SoundController:Play("Rare")
		end
	end
	function e.Arena(p)
		self.Arena = if p.Sealed then { X = p.X, Z = p.Z, R = p.R } else nil
		C.ArenaController:SetSeal(self.Arena)
		if p.Sealed then
			C.CameraController:Shake(1.2)
			C.SoundController:Play("BossSpawn", 0.8, 0.8)
		end
	end
	function e.Map(p)
		local m = self.Map
		if p.Rift then
			m.Rift = true
		end
		if p.Hot ~= nil then
			m.Hot = if p.Hot == false then nil else p.Hot
			m.HotUntil = os.clock() + (p.Time or 0)
		end
		if p.HotSoon then
			m.HotSoon = { Zone = p.HotSoon, At = os.clock() + (p.Time or 0) }
			local zone = ArenaData.ByKey[p.HotSoon]
			if zone then
				C.BannerController:Toast("COMPASS: a 67 RUSH is coming to " .. zone.Name, "Info")
			end
		end
		if p.Hot then
			m.HotSoon = nil
		end
		if p.VaultSoon then
			m.VaultSoon = { Index = p.VaultSoon, At = os.clock() + (p.Time or 0) }
			C.BannerController:Toast("COMPASS: a 67 VAULT will wake up soon", "Info")
		end
		if p.Vault then
			if p.State == "Awake" then
				m.VaultSoon = nil
			end
			local v = m.Vaults[p.Vault] or {}
			v.Event = p.State
			if p.State == "Awake" then
				v.Until = os.clock() + (p.Time or 60)
				v.Seen = true
			end
			m.Vaults[p.Vault] = v
		end
		C.ArenaController:Refresh()
	end
	function e.Zone(p)
		local zone = ArenaData.ByKey[p.Key]
		if zone then
			local first = not self.Map.Visited[zone.Key]
			self.Map.Visited[zone.Key] = true
			self.Map.Zone = zone
			C.HudController:ZoneEntered(zone, first)
		end
	end
	return e
end

-- the life of a boss encounter (Sim/MiniBosses): Warn -> Spawn -> Defeated / Left / Escaped
function RunClient:OnMiniBoss(p)
	local C = self.C
	local phase = p.Phase
	local enc = self.Encounters[p.Key]
	if phase == "Warn" then
		self.Encounters[p.Key] = {
			Key = p.Key,
			Title = p.Title,
			Slot = p.Slot,
			Main = p.Main == true,
			X = p.X,
			Z = p.Z,
			Zone = p.Zone,
			ZoneName = p.ZoneName,
			Stage = "Warn",
			Ids = {},
			Hint = p.Hint,
			Tests = p.Tests,
			Crowned = p.Crowned == true,
			SpawnAt = os.clock() + (p.Delay or 0),
			Since = os.clock(),
		}
		C.BannerController:MiniBoss(p)
	elseif phase == "Spawn" and enc then
		enc.Stage = "Fight"
		enc.Ids = p.Ids or {}
		for _, id in enc.Ids do
			self.Minis[id] = self.Minis[id] or { Id = id, HP = 1, Flags = 0 }
			self.Minis[id].Encounter = p.Key
		end
		if p.Hint and p.Hint ~= "" then
			C.BannerController:Toast(p.Title, "Info", p.Hint)
		end
	elseif phase == "Timer" and enc then
		-- TICK TOCK: the clock starts when the fight does
		enc.TimerEnd = os.clock() + (p.Timer or 67)
		C.BannerController:Toast(p.Key == "TickTock" and "TICK TOCK started its clock: 67 seconds!" or "The clock is ticking!", "Error")
	elseif phase == "Exposed" then
		local m = self.Minis[p.Id]
		if m then
			m.ExposedUntil = os.clock() + (p.Time or 2)
			m.ExposedText = p.Text
		end
		C.EffectsController:Exposed(p)
	elseif phase == "Phase" then
		local m = self.Minis[p.Id]
		if m then
			m.Phase = p.Index
		end
		C.CameraController:Shake(1.5)
	elseif phase == "Crowned" and enc then
		enc.Crowned = true
	elseif phase == "Bond" then
		local m = self.Minis[p.Id]
		if m then
			m.ReviveUntil = os.clock() + (p.Delay or 6.7)
			m.ReviveBody = p.Body
		end
	elseif phase == "Revived" and enc then
		enc.Ids = p.Ids or enc.Ids
		for _, id in enc.Ids do
			local m = self.Minis[id] or { Id = id, HP = 0.5, Flags = 0 }
			m.Encounter = p.Key
			m.ReviveUntil = nil
			self.Minis[id] = m
		end
		C.BannerController:Toast(tostring(p.Body or "IT") .. " IS BACK. Together, remember?", "Error")
	elseif phase == "Shield" then
		local m = self.Minis[p.Id]
		if m then
			m.Pylons = p.Pylons
		end
	elseif phase == "ShieldDown" then
		C.BannerController:Toast("SHIELD DOWN! Hit it!", "Success")
	elseif phase == "Jackpot" then
		local m = self.Minis[p.Id]
		if m then
			m.JackpotUntil = os.clock() + (p.Time or 3)
		end
	elseif phase == "Defeated" or phase == "Left" or phase == "Escaped" then
		if enc then
			for _, id in enc.Ids do
				self.Minis[id] = nil
			end
		end
		self.Encounters[p.Key] = nil
		if phase == "Defeated" then
			C.SoundController:Play("BossDeath", 1.15, 0.7)
		end
		if p.Main then
			self.Arena = nil
			C.ArenaController:SetSeal(nil)
		end
	end
	C.ArenaController:Refresh()
end

function RunClient:OnEvents(list: any)
	if type(list) ~= "table" then
		return
	end
	for _, ev in list do
		if type(ev) == "table" and type(ev.Name) == "string" then
			local fn = self.EventHandlers[ev.Name]
			if fn and (self.Active or ev.Name == "RunStart") then
				local ok, err = pcall(fn, ev.Payload or {})
				if not ok then
					warn("[RunClient] " .. ev.Name .. ": " .. tostring(err))
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- lifecycle
---------------------------------------------------------------------------
local function setReset(enabled: boolean)
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", enabled)
			end)
			if ok then
				return
			end
			task.wait(0.5)
		end
	end)
end

function RunClient:ClearWorld()
	local C = self.C
	table.clear(self.Enemies)
	C.EnemyRenderer:Clear()
	C.PickupRenderer:Clear()
	C.LootRenderer:Clear()
	C.WeaponFx:Clear()
	self.Boss = nil
	self:ResetTown()
	C.ArenaController:Refresh()
end

function RunClient:Begin(p)
	local C = self.C
	self:ClearWorld()
	local startZone = ArenaData.ZoneAt(p.StartX or 0, p.StartZ or 0)
	self.Map.Visited[startZone.Key] = true
	self.Map.Zone = startZone
	self.Active = true
	self.Offset = nil
	self.Time = 0
	self.FrameT = 0
	self.Level = 1
	self.Kills, self.Coins = 0, 0
	self.Paused, self.Dead = false, false
	self.Hero = p.Hero
	self.Party = p.Party or {}
	self.Difficulty = p.Difficulty or 2
	C.ResultsController:Hide()
	C.LevelUpController:Hide()
	C.LobbyController:Hide()
	C.HudController:Show()
	C.HudController:SetDifficulty(self.Difficulty)
	C.CameraController:SetMode("Run")
	C.CameraController:SetMood("Run", self.Difficulty)
	C.SoundController:Play("Banner")
	C.EffectsController:SpawnEffect(p.SpawnEffect or "Beam")
	setReset(false)
	self:ApplyOutline()
	self.Started:Fire(p)
end

--[[
	Your hero stands out from the horde: an outline (drawn on top of everything, so it shows
	through enemies) and a faint glow, only in a run and only if the "Hero outline" setting
	is on. Colours in GameConfig.Visuals.
]]
function RunClient:ApplyOutline()
	local character = Players.LocalPlayer.Character
	if not character then
		return
	end
	local old = character:FindFirstChild("HeroOutline")
	local want = self.Active and self.C.ClientData:Setting("HeroOutline") ~= false
	if not want then
		if old then
			old:Destroy()
		end
		return
	end
	if old then
		return
	end
	local v = GameConfig.Visuals
	local outline = Instance.new("Highlight")
	outline.Name = "HeroOutline"
	outline.Adornee = character
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.OutlineColor = v.OutlineColor
	outline.OutlineTransparency = v.OutlineTransparency
	outline.FillColor = v.FillColor
	outline.FillTransparency = v.FillTransparency
	outline.Parent = character
end

function RunClient:Finish(p)
	local C = self.C
	self.Active = false
	self.Paused = true
	C.LevelUpController:Hide()
	C.ResultsController:HideDeath()
	C.HudController:HideBoss()
	C.ResultsController:ShowResults(p)
	self.Ended:Fire(p)
end

-- back to the lobby (after the results screen)
function RunClient:Leave()
	local C = self.C
	self:ClearWorld()
	C.HudController:Hide()
	C.CameraController:SetMode("Lobby")
	C.LobbyController:Show()
	C.BannerController:PlaceToasts()
	self:ApplyOutline()
	setReset(true)
end

function RunClient:Start()
	local data = self.C.ClientData
	data:Remote("Frame").OnClientEvent:Connect(function(buf)
		self:OnFrame(buf)
	end)
	data:Remote("RunEvent").OnClientEvent:Connect(function(list)
		self:OnEvents(list)
	end)
end

return RunClient
