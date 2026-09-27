--[[
	EffectsController - game feel: damage numbers, particle bursts, shockwave rings, screen
	flashes, the low-HP vignette, level-up bursts, boss arrival / defeat moments.

	Everything is pooled and animated from ONE RenderStepped loop:
	  * damage numbers: BillboardGuis on attachments of one invisible anchored part
	  * particles: a few emitters that are moved and :Emit()-ed (particles stay in world space)
	  * rings: flat neon cylinders that grow and fade
	Budgets keep the screen readable: a horde never produces more than ~40 numbers at once.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)

local EffectsController = {}

local rgb = Color3.fromRGB
local PARK = CFrame.new(0, -400, 0)
local MAX_NUMBERS = 40
local MAX_RINGS = 24
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function short(n: number): string
	n = math.floor(n + 0.5)
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.0fK", n / 1e3)
	elseif n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(n)
end

function EffectsController:Init(controllers)
	self.C = controllers
	local anchor = Instance.new("Part")
	anchor.Name = "FxAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new()
	anchor.Parent = Workspace
	self.Anchor = anchor

	-- damage numbers
	self.Numbers = {}
	self.NumberFree = {}
	for _ = 1, MAX_NUMBERS do
		local att = Instance.new("Attachment")
		att.Parent = anchor
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(90, 36)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Adornee = att
		gui.Enabled = false
		gui.Parent = anchor
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Theme.Fonts.Title
		label.TextScaled = true
		label.TextColor3 = rgb(255, 255, 255)
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = rgb(20, 15, 35)
		stroke.Parent = label
		table.insert(self.NumberFree, { Att = att, Gui = gui, Label = label, Stroke = stroke })
	end

	-- particle emitters
	local function emitter(name: string, texture: string, props: { [string]: any }): ParticleEmitter
		local att = Instance.new("Attachment")
		att.Name = name
		att.Parent = anchor
		local e = Instance.new("ParticleEmitter")
		e.Texture = texture
		e.Enabled = false
		e.LightEmission = 0.5
		e.Lifetime = NumberRange.new(0.3, 0.6)
		e.Speed = NumberRange.new(12, 24)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		e.Drag = 4
		for k, v in props do
			(e :: any)[k] = v
		end
		e.Parent = att
		return e
	end
	self.Emitters = {
		Poof = emitter("Poof", SPARKLE, {}),
		Smoke = emitter("Smoke", SMOKE, {
			Speed = NumberRange.new(4, 10),
			Lifetime = NumberRange.new(0.5, 0.9),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 4) }),
			LightEmission = 0,
		}),
		Big = emitter("Big", SPARKLE, {
			Speed = NumberRange.new(30, 60),
			Lifetime = NumberRange.new(0.6, 1.2),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0) }),
		}),
	}

	-- rings
	self.Rings = {}
	self.RingFree = {}
	for _ = 1, MAX_RINGS do
		local ring = Instance.new("Part")
		ring.Name = "Ring"
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.CFrame = PARK
		ring.Size = Vector3.new(0.3, 1, 1)
		ring.Parent = anchor
		table.insert(self.RingFree, ring)
	end

	-- screen overlays
	local gui, root = Kit.ScreenGui("BrainrotFx", 5, Players.LocalPlayer:WaitForChild("PlayerGui"))
	gui.IgnoreGuiInset = true
	self.Gui = gui
	self.FlashFrame = Kit.New("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = rgb(255, 255, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = root,
	})
	self.Vignette = {}
	for i, spec in { { UDim2.new(1, 0, 0.18, 0), UDim2.new(0, 0, 0, 0), 90 }, { UDim2.new(1, 0, 0.18, 0), UDim2.new(0, 0, 0.82, 0), -90 }, { UDim2.new(0.12, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0 }, { UDim2.new(0.12, 0, 1, 0), UDim2.new(0.88, 0, 0, 0), 180 } } do
		local f = Kit.New("Frame", {
			Name = "Vignette" .. i,
			Size = spec[1],
			Position = spec[2],
			BackgroundColor3 = rgb(255, 20, 40),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = root,
		})
		Kit.New("UIGradient", {
			Rotation = spec[3],
			Transparency = NumberSequence.new(0, 1),
			Parent = f,
		})
		table.insert(self.Vignette, f)
	end
	self.VignetteLevel = 0
end

---------------------------------------------------------------------------
-- primitives
---------------------------------------------------------------------------
function EffectsController:Quality(): boolean
	return not self.C.ClientData:Setting("LowQuality")
end

function EffectsController:Emit(kind: string, pos: Vector3, color: Color3, count: number)
	local e = self.Emitters[kind]
	if not e then
		return
	end
	local att = e.Parent :: Attachment
	att.Position = pos
	e.Color = ColorSequence.new(color)
	e:Emit(if self:Quality() then count else math.ceil(count / 3))
end

function EffectsController:Poof(x: number, z: number, color: Color3, count: number?)
	self:Emit("Poof", self.C.RunClient:World(x, z, 1.5), color, count or 6)
end

function EffectsController:Ring(pos: Vector3, radius: number, color: Color3, duration: number, startRadius: number?)
	local ring = table.remove(self.RingFree)
	if not ring then
		local oldest = table.remove(self.Rings, 1)
		if not oldest then
			return
		end
		ring = oldest.Part
	end
	ring.Color = color
	ring.Transparency = 0.2
	table.insert(self.Rings, {
		Part = ring,
		Pos = pos + Vector3.new(0, 0.4, 0),
		From = startRadius or 0.5,
		To = radius,
		T = 0,
		Duration = duration,
	})
end

function EffectsController:Flash(color: Color3, strength: number?)
	local f = self.FlashFrame
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - (strength or 0.35)
	Kit.Tween(f, 0.35, { BackgroundTransparency = 1 })
end

-- floating text in the world (damage numbers use the same pool)
function EffectsController:WorldText(pos: Vector3, text: string, color: Color3, size: number, life: number?)
	local entry = table.remove(self.NumberFree)
	if not entry then
		local oldest = table.remove(self.Numbers, 1)
		if not oldest then
			return
		end
		entry = oldest
	end
	entry.Att.Position = pos + Vector3.new((math.random() - 0.5) * 1.6, 0, (math.random() - 0.5) * 1.6)
	entry.Label.Text = text
	entry.Label.TextColor3 = color
	entry.Label.TextTransparency = 0
	entry.Stroke.Transparency = 0
	entry.BaseW = 60 * size
	entry.Gui.Size = UDim2.fromOffset(entry.BaseW, 26 * size)
	entry.Gui.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
	entry.Gui.Enabled = true
	entry.T = 0
	entry.Life = life or 0.75
	table.insert(self.Numbers, entry)
end

---------------------------------------------------------------------------
-- game events
---------------------------------------------------------------------------
function EffectsController:DamageNumber(e, damage: number, flags: number)
	self.C.SoundController:Play("Hit", 0.9 + math.random() * 0.3)
	if not self.C.ClientData:Setting("DamageNumbers") then
		return
	end
	local crit = bit32.band(flags, 1) ~= 0
	local six7 = bit32.band(flags, 2) ~= 0
	-- when the screen is full, small hits are skipped (big ones still show)
	if #self.NumberFree == 0 and damage < 50 and not crit then
		return
	end
	local run = self.C.RunClient
	local pos = run:World(e.RX or e.X1, e.RZ or e.Z1, (e.Item and e.Item.Info.Height or 2) * 2 + 0.5)
	local color = rgb(255, 255, 255)
	local size = 1
	if crit and six7 then
		color, size = rgb(255, 215, 40), 1.6
	elseif crit then
		color, size = rgb(255, 240, 80), 1.4
	elseif six7 then
		color = rgb(255, 150, 230)
	end
	if damage >= 1000 then
		size *= 1.3
	end
	self:WorldText(pos, short(damage) .. (if crit then "!" else ""), color, size)
end

function EffectsController:EnemyDied(e)
	local run = self.C.RunClient
	local x, z = e.RX or e.X1, e.RZ or e.Z1
	local def = e.Def
	self.C.SoundController:Play("Kill", 0.85 + math.random() * 0.4)
	local size = if e.Item then e.Item.Info.Scale else 1
	self:Poof(x, z, def.Color, math.clamp(math.floor(5 * size), 4, 20))
	if def.Key == "Goblin67" or def.Key == "GoldenGoober" then
		self:Emit("Big", run:World(x, z, 2), rgb(255, 215, 50), 40)
		self:WorldText(run:World(x, z, 4), "67!", rgb(255, 215, 50), 2.2, 1.2)
		self.C.SoundController:Play("SixSeven")
		self.C.CameraController:ZoomPunch(0.6, 0.8)
	elseif def.Key == "TheNPC" or def.Key == "Runner" then
		self:Emit("Big", run:World(x, z, 2), rgb(255, 255, 255), 30)
		self.C.SoundController:Play("Goofy")
	elseif def.Key == "Crate" then
		self:Emit("Smoke", run:World(x, z, 1), rgb(170, 120, 70), 6)
	end
end

function EffectsController:Glitch(fx: number, fz: number, tx: number, tz: number)
	local color = rgb(255, 0, 220)
	self:Poof(fx, fz, color, 8)
	self:Poof(tx, tz, rgb(0, 255, 255), 8)
end

function EffectsController:Bite(x: number, z: number)
	self:Poof(x, z, rgb(120, 220, 255), 3)
end

local function playerPos(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

function EffectsController:PlayerHurt(damage: number)
	self:Flash(rgb(255, 30, 50), math.clamp(damage / 60, 0.12, 0.35))
	self.C.CameraController:Shake(math.clamp(damage / 25, 0.3, 1.2))
	self.C.SoundController:Play("Hurt")
	self.C.HudController:HurtShake()
	local pos = playerPos()
	if pos then
		self:WorldText(pos + Vector3.new(0, 2, 0), "-" .. short(damage), rgb(255, 70, 90), 1.2)
	end
end

function EffectsController:PlayerHealed(amount: number)
	local pos = playerPos()
	if pos then
		self:WorldText(pos + Vector3.new(0, 3, 0), "+" .. short(amount), rgb(90, 255, 130), 1.3)
		self:Emit("Poof", pos, rgb(90, 255, 130), 10)
	end
	self.C.SoundController:Play("Heal")
end

function EffectsController:LevelUpBurst()
	local pos = playerPos()
	if pos then
		self:Ring(pos - Vector3.new(0, 2.5, 0), 16, rgb(120, 220, 255), 0.5)
		self:Emit("Big", pos, rgb(120, 220, 255), 25)
	end
	self.C.SoundController:Play("LevelUp")
end

function EffectsController:ItemCollected(kind: string, x: number, z: number)
	local run = self.C.RunClient
	if kind == "Magnet" then
		local pos = playerPos()
		if pos then
			self:Ring(pos - Vector3.new(0, 2.5, 0), 60, rgb(90, 180, 255), 0.6)
		end
		self.C.SoundController:Play("Reroll")
	elseif kind == "Chest" then
		self:Emit("Big", run:World(x, z, 2), rgb(255, 215, 60), 40)
		self.C.SoundController:Play("Chest")
	elseif kind == "Pizza" then
		self:Poof(x, z, rgb(255, 190, 70), 8)
	end
end

function EffectsController:BossArrive(e)
	local run = self.C.RunClient
	local pos = run:World(e.X1, e.Z1, 3)
	self.C.CameraController:LookAt(pos, 1.4)
	self.C.CameraController:Shake(2)
	self.C.SoundController:Play("BossSpawn")
	self:Ring(pos - Vector3.new(0, 2.5, 0), 40, rgb(255, 40, 60), 0.9)
	self:Emit("Smoke", pos, rgb(60, 50, 70), 30)
end

function EffectsController:BossDefeated(p)
	local pos = playerPos()
	self.C.SoundController:Play("BossDeath")
	self.C.CameraController:Shake(2.5)
	self.C.CameraController:ZoomPunch(0.55, 1.4)
	self:Flash(rgb(255, 230, 120), 0.6)
	if pos then
		self:Ring(pos - Vector3.new(0, 2.5, 0), 70, rgb(255, 215, 60), 1)
		self:Emit("Big", pos, rgb(255, 215, 60), 60)
	end
	if p and p.Final then
		self.C.SoundController:Play("Victory")
	end
end

function EffectsController:Revived(_p)
	local pos = playerPos()
	self:Flash(rgb(255, 150, 220), 0.6)
	self.C.SoundController:Play("Revive")
	if pos then
		self:Ring(pos - Vector3.new(0, 2.5, 0), 25, rgb(255, 120, 220), 0.6)
	end
end

---------------------------------------------------------------------------
-- loop
---------------------------------------------------------------------------
function EffectsController:Update(dt: number)
	-- damage numbers
	local numbers = self.Numbers
	local i = 1
	while i <= #numbers do
		local n = numbers[i]
		n.T += dt
		local t = n.T / n.Life
		if t >= 1 then
			n.Gui.Enabled = false
			table.insert(self.NumberFree, n)
			numbers[i] = numbers[#numbers]
			numbers[#numbers] = nil
		else
			local pop = if t < 0.15 then 1 + (1 - t / 0.15) * 0.6 else 1
			n.Gui.StudsOffsetWorldSpace = Vector3.new(0, 2 + t * 3.5, 0)
			n.Gui.Size = UDim2.fromOffset(n.BaseW * pop, n.BaseW * 0.43 * pop)
			if t > 0.6 then
				local fade = (t - 0.6) / 0.4
				n.Label.TextTransparency = fade
				n.Stroke.Transparency = fade
			end
			i += 1
		end
	end

	-- rings
	local rings = self.Rings
	i = 1
	while i <= #rings do
		local r = rings[i]
		r.T += dt
		local t = r.T / r.Duration
		if t >= 1 then
			r.Part.CFrame = PARK
			table.insert(self.RingFree, r.Part)
			rings[i] = rings[#rings]
			rings[#rings] = nil
		else
			local ease = 1 - (1 - t) ^ 3
			local radius = r.From + (r.To - r.From) * ease
			r.Part.Size = Vector3.new(0.3, radius * 2, radius * 2)
			r.Part.CFrame = CFrame.new(r.Pos) * CFrame.Angles(0, 0, math.rad(90))
			r.Part.Transparency = 0.2 + 0.8 * t
			i += 1
		end
	end

	-- low HP vignette
	local run = self.C.RunClient
	local target = 0
	if run.Active and run.MaxHP > 0 then
		local frac = run.HP / run.MaxHP
		if frac < 0.35 then
			target = (0.35 - frac) / 0.35 * (0.55 + 0.25 * math.sin(os.clock() * 6))
		end
	end
	self.VignetteLevel += (target - self.VignetteLevel) * math.min(1, dt * 6)
	for _, f in self.Vignette do
		f.BackgroundTransparency = 1 - self.VignetteLevel
	end
end

function EffectsController:Start()
	RunService.RenderStepped:Connect(function(dt)
		self:Update(dt)
	end)
end

return EffectsController
