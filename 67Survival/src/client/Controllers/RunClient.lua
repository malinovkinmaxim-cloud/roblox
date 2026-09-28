--[[
	RunClient - the client side of a run. Decodes the binary Frames (shared/Protocol.lua) and the
	reliable RunEvents, keeps the interpolation state of every enemy, and hands work to the
	renderers / UI. It never decides anything about the game: all numbers come from the server.

	Interpolation: every enemy keeps two samples (T0, X0, Z0) -> (T1, X1, Z1) in server run time.
	The renderers draw at RenderTime() = estimated server time - DELAY, so movement stays smooth
	between 10 Hz frames.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Protocol = require(Shared.Protocol)
local GameConfig = require(Shared.GameConfig)
local EnemyData = require(Shared.EnemyData)
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
	self.Center = GameConfig.Arena.Center
	self.GroundY = GameConfig.Arena.GroundY
	self.Changed = Signal.new()
	self.Started = Signal.new()
	self.Ended = Signal.new()
	self.Stats = { Frames = 0, Bytes = 0, Records = 0 }
	self.Handlers = self:BuildHandlers()
	self.EventHandlers = self:BuildEventHandlers()
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
	return e
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
	C.WeaponFx:Clear()
	self.Boss = nil
end

function RunClient:Begin(p)
	local C = self.C
	self:ClearWorld()
	self.Active = true
	self.Offset = nil
	self.Time = 0
	self.FrameT = 0
	self.Level = 1
	self.Kills, self.Coins = 0, 0
	self.Paused, self.Dead = false, false
	self.Hero = p.Hero
	self.Party = p.Party or {}
	C.ResultsController:Hide()
	C.LevelUpController:Hide()
	C.LobbyController:Hide()
	C.HudController:Show()
	C.CameraController:SetMode("Run")
	C.SoundController:Play("Banner")
	C.EffectsController:SpawnEffect(p.SpawnEffect or "Beam")
	setReset(false)
	self.Started:Fire(p)
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
