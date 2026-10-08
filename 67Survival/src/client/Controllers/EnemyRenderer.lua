--[[
	EnemyRenderer - draws every enemy of the run from pooled models.

	One RenderStepped pass: interpolated position, facing, a goofy hop / waddle (flyers bob),
	state poses (windup shake, dash lean, frozen, phased ghost, dormant mimic, lit bomber,
	burning), and ONE workspace:BulkMoveTo call for all enemy roots.
	Killed enemies are launched into the air with a spin before going back to the pool.
	Mini-bosses of 67 TOWN wear a name plate: name, HP bar and what they are up to (reels
	spinning, SHIELDED, JACKPOT!, reviving, TICK TOCK's countdown, a boss's cue: SAFE: RED,
	KEEP MOVING...).
	Elites wear their AFFIXES (spikes, a shield bubble, red eyes, gold...: dressAffixes), a
	broken shield or a raging twin show through EState, a main boss changes its look with
	every phase (parts tagged Phase / PhaseHide in Render/EnemyModels).
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local Protocol = require(Shared.Protocol)

local Pool = require(script.Parent.Parent.Render.Pool)
local EnemyModels = require(script.Parent.Parent.Render.EnemyModels)
local EnemyAnimator = require(script.Parent.Parent.Render.EnemyAnimator)
local Theme = require(script.Parent.Parent.UI.Theme)
local EnemyData = require(Shared.EnemyData)

local EnemyRenderer = {}

local FLAGS = Protocol.Flags
local WHITE = Color3.new(1, 1, 1)
local FROZEN = Color3.fromRGB(150, 220, 255)
local LIT = Color3.fromRGB(255, 60, 40)
local STUNNED = Color3.fromRGB(255, 230, 120)
local BURN = Color3.fromRGB(255, 140, 50)
local RAGE = Color3.fromRGB(255, 236, 140)
local ES = Protocol.EState
local ELITE: Color3 -- set below (elite plates)
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
	if bit32.band(flags, FLAGS.Sketch) ~= 0 then
		v ..= "s"
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
	if e.Def.Champion or e.Def.MiniBoss then
		self:AttachPlate(e, item)
	end
	local elite = self.PendingElites and self.PendingElites[e.Id]
	if elite then
		self.PendingElites[e.Id] = nil
		self:MarkElite(e.Id, elite.Name, elite.Affixes, elite.Keys)
	end
end

-- an elite: a purple name plate with its affixes (the Elite event may come before or after
-- the enemy itself), and the affixes on its body
function EnemyRenderer:MarkElite(id: number, name: string, affixes: { string }, keys: { string }?)
	local e = self.C.RunClient.Enemies[id]
	if not e or not e.Item then
		self.PendingElites = self.PendingElites or {}
		self.PendingElites[id] = { Name = name, Affixes = affixes, Keys = keys }
		return
	end
	e.EliteName = name
	e.EliteAffixes = table.concat(affixes, " · ")
	if not e.Plate then
		self:AttachPlate(e, e.Item)
	end
	e.Plate.Name.Text = name
	e.Plate.Name.TextColor3 = ELITE
	e.Plate.Fill.BackgroundColor3 = ELITE
	if keys and #keys > 0 then
		EnemyModels.DressAffixes(e.Item, keys)
	end
end

-- a main boss enters a phase: its look changes (Render/EnemyModels Phase / PhaseHide tags)
function EnemyRenderer:SetPhase(id: number, index: number)
	local e = self.C.RunClient.Enemies[id]
	if e and e.Item then
		EnemyModels.SetPhase(e.Item, index)
	end
end

---------------------------------------------------------------------------
-- mini-boss name plates
---------------------------------------------------------------------------
local PLATE_W, PLATE_H = 190, 56
local MF = Protocol.MiniFlags
ELITE = Color3.fromRGB(190, 110, 255)
local REEL_SYMBOL = { Ring = "O", Cross = "X", Bombs = "!", Jackpot = "7" }
local REEL_SPIN = { "O", "X", "!", "7" }

function EnemyRenderer:AttachPlate(e, item)
	local C = Theme.Colors
	local gui = Instance.new("BillboardGui")
	gui.Name = "MiniPlate"
	gui.Size = UDim2.fromOffset(PLATE_W, PLATE_H)
	gui.StudsOffset = Vector3.new(0, (item.Info.Top or item.Info.Height) + 2.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	gui.Adornee = item.Root
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 20)
	name.Font = Theme.Fonts.Title
	name.TextScaled = true
	name.Text = e.Def.Name
	name.TextColor3 = Color3.fromRGB(255, 170, 120)
	name.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = C.SurfaceDark
	stroke.Parent = name
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.new(1, -20, 0, 10)
	back.Position = UDim2.new(0.5, 0, 0, 23)
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.BackgroundColor3 = C.SurfaceDark
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = back
	local backStroke = Instance.new("UIStroke")
	backStroke.Thickness = 1.5
	backStroke.Color = C.SurfaceDark
	backStroke.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = C.Danger
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, 0, 0, 18)
	status.Position = UDim2.fromOffset(0, 36)
	status.Font = Theme.Fonts.Bold
	status.TextScaled = true
	status.Text = ""
	status.TextColor3 = C.Text
	status.Parent = gui
	local statusStroke = Instance.new("UIStroke")
	statusStroke.Thickness = 1.5
	statusStroke.Color = C.SurfaceDark
	statusStroke.Parent = status
	gui.Parent = item.Root
	e.Plate = { Gui = gui, Fill = fill, Status = status, Name = name }
	self.Champions = self.Champions or {}
	table.insert(self.Champions, e)
end

local function detachPlate(self, e)
	if e.Plate then
		e.Plate.Gui:Destroy()
		e.Plate = nil
		local list = self.Champions
		local i = list and table.find(list, e)
		if i then
			table.remove(list, i)
		end
	end
end

-- what a mini-boss is doing, in a few words (and its colour)
function EnemyRenderer:PlateStatus(e, m, now: number): (string, Color3)
	local C = Theme.Colors
	local run = self.C.RunClient
	local flags = if m then m.Flags or 0 else 0
	if m and m.ReviveUntil and now < m.ReviveUntil then
		return string.format("REVIVING %s  %.1f", tostring(m.ReviveBody or ""), m.ReviveUntil - now), C.Gold
	end
	if m and m.Cue and m.CueUntil and now < m.CueUntil then
		return tostring(m.Cue), C.Gold
	end
	if bit32.band(flags, MF.Shielded) ~= 0 then
		return "SHIELDED · BREAK THE COIN STACKS", C.Gold
	end
	if (m and m.JackpotUntil and now < m.JackpotUntil) or bit32.band(flags, MF.Stunned) ~= 0 then
		return "JACKPOT! HIT IT!", C.Gold
	end
	if m and m.Reels then
		local reels = m.Reels
		if now < reels.Until then
			local k = math.floor(now * 12)
			return string.format("[ %s  %s  %s ]", REEL_SPIN[k % 4 + 1], REEL_SPIN[(k + 1) % 4 + 1], REEL_SPIN[(k + 2) % 4 + 1]), C.Text
		elseif now < reels.Until + 1.2 then
			local sym = REEL_SYMBOL[reels.Result] or "?"
			return string.format("[ %s  %s  %s ]", sym, sym, sym), if reels.Result == "Jackpot" then C.Gold else C.Danger
		end
	end
	if (m and m.ExposedUntil and now < m.ExposedUntil) or bit32.band(flags, MF.Exposed) ~= 0 then
		return "WEAK POINT! " .. tostring(m and m.ExposedText or "HIT IT NOW"), Color3.fromRGB(255, 170, 40)
	end
	local enc = m and m.Encounter and run.Encounters[m.Encounter]
	if enc and enc.TimerEnd then
		local left = math.max(0, enc.TimerEnd - now)
		return string.format("ALARM IN %d:%02d", math.floor(left / 60), math.floor(left % 60)), if left < 15 then C.Danger else C.Text
	end
	local marked = if bit32.band(flags, MF.Marked) ~= 0 then "  ✖" else ""
	if e.EliteName then
		return (e.EliteAffixes or "ELITE") .. marked, ELITE
	end
	if bit32.band(flags, MF.Home) ~= 0 then
		return "GOING HOME TO HEAL", C.TextDim
	end
	local tag = if enc and enc.Slot then "BOSS " .. enc.Slot else "BOSS"
	if enc and enc.Crowned then
		tag = "👑 CROWNED " .. tag
	end
	if m and m.Phase and m.Phase > 1 then
		return tag .. " · PHASE " .. m.Phase .. marked, C.Danger
	end
	if bit32.band(flags, MF.Enraged) ~= 0 then
		return tag .. " · ANGRY" .. marked, C.Danger
	end
	return tag .. marked, C.TextDim
end

function EnemyRenderer:UpdatePlates()
	local list = self.Champions
	if not list or #list == 0 then
		return
	end
	local run = self.C.RunClient
	local now = os.clock()
	local C = Theme.Colors
	for _, e in list do
		local plate = e.Plate
		local m = run.Minis[e.Id]
		local hp = if m and m.HP then m.HP else 1
		plate.Fill.Size = UDim2.fromScale(math.clamp(hp, 0, 1), 1)
		local flags = if m then m.Flags or 0 else 0
		local exposed = (m and m.ExposedUntil and now < m.ExposedUntil) or bit32.band(flags, MF.Exposed) ~= 0
		plate.Fill.BackgroundColor3 = if bit32.band(flags, MF.Shielded) ~= 0 then C.Gold
			elseif exposed then Color3.fromRGB(255, 170, 40)
			elseif e.EliteName then ELITE
			else C.Danger
		if m and m.Encounter and not e.Titled then
			local enc = run.Encounters[m.Encounter]
			if enc then
				e.Titled = true
				plate.Name.Text = enc.Title
				plate.Name.TextColor3 = if enc.Crowned then C.Gold else Color3.fromRGB(255, 170, 120)
			end
		end
		local text, color = self:PlateStatus(e, m, now)
		if plate.Status.Text ~= text then
			plate.Status.Text = text
		end
		plate.Status.TextColor3 = color
	end
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
	detachPlate(self, e)
	local item = e.Item
	if not item then
		return
	end
	e.Item = nil
	if item.Root.Color ~= item.Info.BodyColor then
		item.Root.Color = item.Info.BodyColor
	end
	fade(item, 0)
	EnemyModels.Reset(item) -- affixes, toggled parts, phase looks: back to the pooled model
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
	item.Root.Color = if state == ES.Frozen then FROZEN
		elseif state == ES.Lit then LIT
		elseif state == ES.Stunned then item.Info.BodyColor:Lerp(STUNNED, 0.45)
		elseif state == ES.Enraged then item.Info.BodyColor:Lerp(RAGE, 0.55)
		else item.Info.BodyColor
	fade(item, if state == ES.Phased then 0.75 else 0)
	-- parts that only show in some states (a Snoozer's eyelids, a Shielder's shield)
	EnemyModels.Toggle(item, state)
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
	EnemyModels.Reset(old)
	self.Pool:Release(old)
	e.Item = self.Pool:Acquire(poolKey(e.Def, e.Flags))
	self.C.EffectsController:Poof(e.RX, e.RZ, Color3.fromRGB(200, 120, 255), 6)
end

function EnemyRenderer:Clear()
	for _, e in table.clone(self.List) do
		detachPlate(self, e)
	end
	for _, e in self.List do
		if e.Item then
			EnemyModels.Reset(e.Item)
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
	-- procedural animation (Render/EnemyAnimator): a plain bob in a big crowd, parts only near you
	local crowd = #self.List > EnemyAnimator.CROWD
	local lodSq = EnemyAnimator.LOD_DIST * EnemyAnimator.LOD_DIST
	local partBudget = EnemyAnimator.PART_BUDGET
	self.LightClock = (self.LightClock or 0) + dt
	if self.LightClock >= 0.25 then
		self.LightClock = 0
		EnemyAnimator.Lights(self.List, px, pz)
	end
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
			local pitch, roll, spin = 0, 0, 0
			local ox, oz = 0, 0
			if state == ES.Stunned and not paused then
				-- stunned: a dizzy wobble in place
				roll = sin(now * 14 + e.Phase) * 0.18
			elseif state == ES.Frozen or state == ES.Dormant or paused then
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
			elseif info.AnimType then
				-- the bestiary: its own procedural animation, its parts move when it is near
				local near = (x - px) ^ 2 + (z - pz) ^ 2 < lodSq
				local ay
				ay, pitch, roll, spin = EnemyAnimator.Pose(e, item, now, dt, math.sqrt(dx * dx + dz * dz), crowd or not near)
				y += ay
				if info.Anims and (e.Def.Boss or (near and not crowd and partBudget > 0)) then
					partBudget -= 1
					EnemyAnimator.Parts(item, now)
				end
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
			cframes[n] = CFrame.new(center.X + x + ox, y, center.Z + z + oz) * CFrame.Angles(0, e.Yaw + spin, 0) * CFrame.Angles(pitch, 0, roll)
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
	self:UpdatePlates()
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
