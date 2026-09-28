--[[
	EnemyRenderer - draws every enemy of the run from pooled models.

	One RenderStepped pass: interpolated position, facing, a goofy hop / waddle (flyers bob),
	state poses (windup shake, dash lean, frozen, phased ghost, dormant mimic, lit bomber,
	burning), and ONE workspace:BulkMoveTo call for all enemy roots.
	Killed enemies are launched into the air with a spin before going back to the pool.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Protocol = require(Shared.Protocol)

local Pool = require(script.Parent.Parent.Render.Pool)
local EnemyModels = require(script.Parent.Parent.Render.EnemyModels)
local EnemyData = require(Shared.EnemyData)

local EnemyRenderer = {}

local FLAGS = Protocol.Flags
local WHITE = Color3.new(1, 1, 1)
local FROZEN = Color3.fromRGB(150, 220, 255)
local LIT = Color3.fromRGB(255, 60, 40)
local BURN = Color3.fromRGB(255, 140, 50)
local ES = Protocol.EState
local MAX_DYING = 40
local atan2, sin, abs = math.atan2, math.sin, math.abs

local function poolKey(def, flags: number): string
	local v = ""
	if bit32.band(flags, FLAGS.Tiny) ~= 0 then
		v ..= "t"
	elseif bit32.band(flags, FLAGS.Giant) ~= 0 then
		v ..= "G"
	end
	if bit32.band(flags, FLAGS.Golden) ~= 0 then
		v ..= "g"
	end
	if bit32.band(flags, FLAGS.Elite) ~= 0 then
		v ..= "e"
	end
	return def.Key .. ":" .. v
end

-- parked models kept per pool key: plain kinds keep more than rare variants (tiny, giant,
-- golden, elite); mid-run the pool is trimmed harder once too many models sit parked
local PARKED_BUDGET = 96
local function keepBetweenRuns(key: string): number
	return if string.sub(key, -1) == ":" then 24 else 6
end
local function keepMidRun(key: string): number
	return if string.sub(key, -1) == ":" then 4 else 1
end

function EnemyRenderer:Init(controllers)
	self.C = controllers
	self.List = {}
	self.Dying = {}
	self.Parts = {}
	self.CFrames = {}
	local folder = Instance.new("Folder")
	folder.Name = "RunEnemies"
	folder.Parent = Workspace
	self.Folder = folder
	self.Pool = Pool.new(folder, function(key)
		local parts = string.split(key, ":")
		return EnemyModels.Build(EnemyData.ByKey[parts[1]], parts[2] or "")
	end)
end

function EnemyRenderer:Add(e)
	local item = self.Pool:Acquire(poolKey(e.Def, e.Flags))
	e.Item = item
	e.Phase = math.random() * 6.28
	e.Yaw = math.random() * 6.28
	e.RX, e.RZ = e.X1, e.Z1
	e.Sky = if bit32.band(e.Flags, FLAGS.FromSky) ~= 0 then 0.55 else 0
	table.insert(self.List, e)
	e.Index = #self.List
end

local function unlist(self, e)
	local list = self.List
	local i = e.Index
	if not i or list[i] ~= e then
		return
	end
	local last = list[#list]
	list[i] = last
	last.Index = i
	list[#list] = nil
	e.Index = nil
end

local function fade(item, amount: number)
	if item.Faded == amount then
		return
	end
	item.Faded = amount
	for _, p in item.Info.Parts do
		p.LocalTransparencyModifier = amount
	end
end

function EnemyRenderer:Remove(e, cause: number)
	unlist(self, e)
	local item = e.Item
	if not item then
		return
	end
	e.Item = nil
	if item.Root.Color ~= item.Info.BodyColor then
		item.Root.Color = item.Info.BodyColor
	end
	fade(item, 0)
	if cause == 0 and #self.Dying < MAX_DYING and self.C.EffectsController:Quality() then
		-- launched off screen, spinning: goofy death
		local away = Vector3.new(e.RX - (self.PX or e.RX), 0, e.RZ - (self.PZ or e.RZ))
		if away.Magnitude < 0.01 then
			away = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
		end
		away = away.Unit * math.random(10, 22)
		table.insert(self.Dying, {
			Item = item,
			CF = item.Root.CFrame,
			Vel = away + Vector3.new(0, math.random(22, 34), 0),
			Spin = Vector3.new(math.random() * 14 - 7, math.random() * 14 - 7, math.random() * 14 - 7),
			T = 0,
		})
	else
		self.Pool:Release(item)
	end
end

function EnemyRenderer:Flash(e)
	local item = e.Item
	if item and e.State ~= ES.Frozen then
		item.Root.Color = WHITE
		e.FlashUntil = os.clock() + 0.07
	end
end

function EnemyRenderer:SetState(e, state: number)
	local item = e.Item
	if not item then
		return
	end
	item.Root.Color = if state == ES.Frozen then FROZEN elseif state == ES.Lit then LIT else item.Info.BodyColor
	fade(item, if state == ES.Phased then 0.75 else 0)
end

-- the enemy burns for a few seconds (orange flicker)
function EnemyRenderer:Burn(e, seconds: number)
	e.BurnUntil = os.clock() + seconds
end

-- the enemy changed variant (67 shrink): swap its model
function EnemyRenderer:Reskin(e)
	local old = e.Item
	if not old then
		return
	end
	old.Root.Color = old.Info.BodyColor
	fade(old, 0)
	self.Pool:Release(old)
	e.Item = self.Pool:Acquire(poolKey(e.Def, e.Flags))
	self.C.EffectsController:Poof(e.RX, e.RZ, Color3.fromRGB(200, 120, 255), 6)
end

function EnemyRenderer:Clear()
	for _, e in self.List do
		if e.Item then
			self.Pool:Release(e.Item)
			e.Item = nil
		end
	end
	table.clear(self.List)
	for _, d in self.Dying do
		self.Pool:Release(d.Item)
	end
	table.clear(self.Dying)
	self.Pool:Trim(keepBetweenRuns)
end

function EnemyRenderer:Update(dt: number)
	local run = self.C.RunClient
	local parts, cframes = self.Parts, self.CFrames
	local n = 0
	local rt = run:RenderTime()
	local now = os.clock()
	local ground = run.GroundY
	local center = run.Center
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local px, pz = 0, 0
	if root then
		px, pz = root.Position.X - center.X, root.Position.Z - center.Z
	end
	self.PX, self.PZ = px, pz
	local paused = run.Paused
	local turn = math.min(1, 10 * dt)
	-- after a big wave (67 INVASION) hundreds of models can sit parked: free the extras
	self.TrimClock = (self.TrimClock or 0) + dt
	if self.TrimClock >= 2 then
		self.TrimClock = 0
		if self.Pool:Parked() > PARKED_BUDGET then
			self.Pool:Trim(keepMidRun)
		end
	end

	for _, e in self.List do
		local item = e.Item
		if item then
			local x, z = run:EnemyPos(e, rt)
			local dx, dz = x - e.RX, z - e.RZ
			e.RX, e.RZ = x, z
			local state = e.State
			-- facing: movement direction, or the player when standing still
			local target
			if dx * dx + dz * dz > 0.0004 then
				target = atan2(-dx, -dz)
			else
				target = atan2(-(px - x), -(pz - z))
			end
			local diff = (target - e.Yaw + math.pi) % (2 * math.pi) - math.pi
			e.Yaw += diff * turn

			local info = item.Info
			local scale = info.Scale
			local y = ground + info.Height
			local pitch, roll = 0, 0
			local ox, oz = 0, 0
			if state == ES.Frozen or state == ES.Dormant or paused then
				-- frozen / dormant / paused: no animation
			elseif state == ES.Lit then
				-- the fuse burns: shake + flash
				ox = (math.random() - 0.5) * 0.35 * scale
				oz = (math.random() - 0.5) * 0.35 * scale
				item.Root.Color = if (now * 10) % 2 < 1 then LIT else info.BodyColor
			elseif state == ES.Windup then
				ox = (math.random() - 0.5) * 0.5 * scale
				oz = (math.random() - 0.5) * 0.5 * scale
				y += 0.2 * scale
			elseif state == ES.Dash then
				pitch = -0.45
			elseif info.Float then
				local t = now * 3 + e.Phase
				y += sin(t) * 0.5 * scale
				roll = sin(t * 0.7) * 0.08
			else
				local t = now * 9 + e.Phase
				y += abs(sin(t)) * 0.45 * scale
				roll = sin(t) * 0.12
			end
			if e.BurnUntil then
				if now >= e.BurnUntil then
					e.BurnUntil = nil
					if state ~= ES.Frozen and state ~= ES.Lit then
						item.Root.Color = info.BodyColor
					end
				elseif not e.FlashUntil and state ~= ES.Frozen then
					item.Root.Color = info.BodyColor:Lerp(BURN, 0.45 + 0.35 * sin(now * 18 + e.Phase))
				end
			end
			if e.Sky > 0 then
				e.Sky = math.max(0, e.Sky - dt)
				y += e.Sky * e.Sky * 140
			end
			if e.FlashUntil and now >= e.FlashUntil then
				e.FlashUntil = nil
				if state ~= ES.Frozen and state ~= ES.Lit then
					item.Root.Color = info.BodyColor
				end
			end
			n += 1
			parts[n] = item.Root
			cframes[n] = CFrame.new(center.X + x + ox, y, center.Z + z + oz) * CFrame.Angles(0, e.Yaw, 0) * CFrame.Angles(pitch, 0, roll)
		end
	end

	-- dying enemies fly away spinning
	local dying = self.Dying
	local i = 1
	while i <= #dying do
		local d = dying[i]
		d.T += dt
		if d.T > 0.55 then
			self.Pool:Release(d.Item)
			dying[i] = dying[#dying]
			dying[#dying] = nil
		else
			d.Vel -= Vector3.new(0, 90 * dt, 0)
			local s = d.Spin * dt
			d.CF = (d.CF + d.Vel * dt) * CFrame.Angles(s.X, s.Y, s.Z)
			n += 1
			parts[n] = d.Item.Root
			cframes[n] = d.CF
			i += 1
		end
	end

	for k = n + 1, #parts do
		parts[k] = nil
		cframes[k] = nil
	end
	if n > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function EnemyRenderer:Count(): number
	return #self.List
end

function EnemyRenderer:Start()
	RunService.RenderStepped:Connect(function(dt)
		self:Update(dt)
	end)
end

return EnemyRenderer
