--[[
	EffectsController - juice. Everything local, pooled, cheap.

	  * FloatText   "+12 cm" rising from your head (bigger + more colourful for bigger taps)
	  * TapBurst    particle burst at your body, shockwave ring for huge taps
	  * Rebirth     giant -> tiny -> flat -> BOOM (light sphere, flash, particles) -> "REBIRTH!"
	                (other players' rebirths get the same boom at their body)
	  * Confetti / Boom / ScreenFlash helpers used by notifications, hatching, zones, chests
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local BodyShape = require(Shared.BodyShape)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)

local LocalPlayer = Players.LocalPlayer

local EffectsController = {}

local TIER_COLORS = {
	[0] = Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(140, 255, 150),
	Color3.fromRGB(110, 220, 255),
	Color3.fromRGB(255, 220, 80),
	Color3.fromRGB(255, 140, 60),
	Color3.fromRGB(255, 90, 200),
	Color3.fromRGB(190, 120, 255),
}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local GLOW = "rbxasset://textures/particles/forcefield_glow_main.dds"

function EffectsController:Init(controllers)
	self.Controllers = controllers
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")

	-- floating numbers live in their own unscaled ScreenGui (pixel positions)
	self.FloatGui = Kit.New("ScreenGui", {
		Name = "ChileFloat",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		Parent = playerGui,
	})
	self.FloatPool = {}
	self.FloatIndex = 1
	for i = 1, 18 do
		local label = Kit.Label({
			Name = "Float" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(200, 40),
			Font = Theme.Fonts.Title,
			Visible = false,
			StrokeThickness = 3,
			Parent = self.FloatGui,
		})
		self.FloatPool[i] = label
	end

	-- overlay for flashes and big texts (scaled like the HUD)
	local gui, root = Kit.ScreenGui("ChileFxOverlay", 20, playerGui)
	self.OverlayGui = gui
	self.Overlay = root
	self.Flash = Kit.New("Frame", {
		Name = "Flash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(2, 2),
		Position = UDim2.fromScale(-0.5, -0.5),
		ZIndex = 1,
		Parent = gui,
	})

	-- one invisible anchor part with pre-made emitters for bursts
	local folder = Workspace:FindFirstChild("ChileBodies") or Workspace
	local anchor = Instance.new("Part")
	anchor.Name = "FxAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Parent = folder
	self.Anchor = anchor
	local function emitter(name: string, texture: string, lightEmission: number): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.Name = name
		e.Texture = texture
		e.Rate = 0
		e.LightEmission = lightEmission
		e.SpreadAngle = Vector2.new(180, 180)
		e.Lifetime = NumberRange.new(0.5, 0.9)
		e.Speed = NumberRange.new(6, 14)
		e.Drag = 3
		e.Transparency = NumberSequence.new(0, 1)
		e.Parent = anchor
		return e
	end
	self.Sparkles = emitter("Sparkles", SPARKLE, 1)
	self.Confetti = emitter("Confetti", SPARKLE, 0.3)
	self.Confetti.Acceleration = Vector3.new(0, -20, 0)
	self.Confetti.Lifetime = NumberRange.new(1.2, 2)
	self.Confetti.RotSpeed = NumberRange.new(-200, 200)
	self.Glow = emitter("Glow", GLOW, 1)
end

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function tween(instance: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

function EffectsController:BodyCenter(player: Player): (Vector3?, number)
	local body = self.Controllers.BodyController:GetBody(player)
	if not body or not body.FeetCF or not body.Shape then
		return nil, 4
	end
	return body.FeetCF.Position + Vector3.new(0, body.Shape.Total * 0.5, 0), body.Shape.Total
end

function EffectsController:BurstAt(position: Vector3, scale: number, colors: { Color3 }, count: number, kind: string?)
	local e = if kind == "Confetti" then self.Confetti elseif kind == "Glow" then self.Glow else self.Sparkles
	self.Anchor.CFrame = CFrame.new(position)
	local s = math.clamp(scale, 0.3, 40)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s * 0.6), NumberSequenceKeypoint.new(1, 0) })
	e.Speed = NumberRange.new(6 * s, 14 * s)
	e.Acceleration = if kind == "Confetti" then Vector3.new(0, -20 * s, 0) else Vector3.zero
	if #colors > 1 then
		local keys = {}
		for i, c in colors do
			table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
		end
		e.Color = ColorSequence.new(keys)
	else
		e.Color = ColorSequence.new(colors[1])
	end
	local low = self.Controllers.ClientData:Setting("LowGraphics")
	e:Emit(math.max(1, math.floor(count * (if low then 0.35 else 1))))
end

-- expanding neon sphere + light
function EffectsController:Boom(position: Vector3, radius: number, color: Color3)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Size = Vector3.one * math.max(1, radius * 0.1)
	ball.CFrame = CFrame.new(position)
	ball.Transparency = 0.1
	ball.Parent = self.Anchor.Parent
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 6
	light.Range = math.clamp(radius * 1.5, 12, 60)
	light.Parent = ball
	tween(ball, 0.45, { Size = Vector3.one * radius * 2, Transparency = 1 }, Enum.EasingStyle.Quart)
	tween(light, 0.6, { Brightness = 0 })
	task.delay(0.7, function()
		ball:Destroy()
	end)
end

function EffectsController:Shockwave(position: Vector3, radius: number, color: Color3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = self.Anchor.Parent
	tween(ring, 0.45, { Size = Vector3.new(0.2, radius * 2, radius * 2), Transparency = 1 }, Enum.EasingStyle.Quart)
	task.delay(0.5, function()
		ring:Destroy()
	end)
end

function EffectsController:ScreenFlash(color: Color3, strength: number?, duration: number?)
	self.Flash.BackgroundColor3 = color
	self.Flash.BackgroundTransparency = 1 - (strength or 0.7)
	tween(self.Flash, duration or 0.5, { BackgroundTransparency = 1 })
end

---------------------------------------------------------------------------
-- tap feedback
---------------------------------------------------------------------------
function EffectsController:FloatText(text: string, tier: number, screenPosition: Vector2?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local label = self.FloatPool[self.FloatIndex]
	self.FloatIndex = self.FloatIndex % #self.FloatPool + 1

	-- start at the head if it is on screen, otherwise near the click / centre
	local body = self.Controllers.BodyController:GetBody(LocalPlayer)
	local start: Vector2
	if body and body.TopPosition then
		local point, onScreen = camera:WorldToViewportPoint(body.TopPosition)
		if onScreen then
			start = Vector2.new(point.X, point.Y)
		end
	end
	if not start then
		local viewport = camera.ViewportSize
		start = screenPosition or Vector2.new(viewport.X / 2, viewport.Y * 0.45)
	end
	start += Vector2.new(math.random(-60, 60), math.random(-20, 10))

	local scale = Kit.ScaleFor(camera.ViewportSize)
	local size = (26 + tier * 5) * scale
	label.Text = text
	label.TextColor3 = TIER_COLORS[math.clamp(tier, 0, 6)]
	label.Size = UDim2.fromOffset(size * 7, size)
	label.Position = UDim2.fromOffset(start.X, start.Y)
	label.TextTransparency = 0
	label.Rotation = math.random(-8, 8)
	label.Visible = true
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
		tween(stroke, 0.8, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	local rise = (70 + tier * 12) * scale
	tween(label, 0.8, { Position = UDim2.fromOffset(start.X + math.random(-25, 25), start.Y - rise), TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.8, function()
		if label.TextTransparency >= 0.99 then
			label.Visible = false
		end
	end)
end

function EffectsController:TapBurst(tier: number)
	local center, total = self:BodyCenter(LocalPlayer)
	if not center then
		return
	end
	local scale = math.clamp(total / 12, 0.4, 25)
	local color = TIER_COLORS[math.clamp(tier, 0, 6)]
	self:BurstAt(center, scale, { color, Color3.new(1, 1, 1) }, 4 + tier * 3)
	if tier >= 3 then
		local body = self.Controllers.BodyController:GetBody(LocalPlayer)
		if body and body.FeetCF then
			self:Shockwave(body.FeetCF.Position, math.max(6, total * 0.25), color)
		end
	end
end

---------------------------------------------------------------------------
-- rebirth: giant -> tiny -> flat -> BOOM -> REBIRTH!
---------------------------------------------------------------------------
function EffectsController:BigText(title: string, subtitle: string, color: Color3)
	local holder = Kit.New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(760, 190),
		Parent = self.Overlay,
	})
	local titleLabel = Kit.Label({
		Size = UDim2.new(1, 0, 0, 120),
		Text = title,
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.new(1, 1, 1),
		StrokeThickness = 5,
		Parent = holder,
	})
	Kit.Gradient(titleLabel, color:Lerp(Color3.new(1, 1, 1), 0.5), color)
	local sub = Kit.Label({
		Position = UDim2.fromOffset(0, 124),
		Size = UDim2.new(1, 0, 0, 52),
		Text = subtitle,
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Yellow,
		StrokeThickness = 4,
		Parent = holder,
	})
	local scale = Kit.New("UIScale", { Scale = 0.2, Parent = holder })
	tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.2, function()
		tween(scale, 0.3, { Scale = 1.3 })
		tween(titleLabel, 0.3, { TextTransparency = 1 })
		tween(sub, 0.3, { TextTransparency = 1 })
		task.delay(0.35, function()
			holder:Destroy()
		end)
	end)
end

function EffectsController:Rebirth(payload)
	local player = Players:GetPlayerByUserId(payload.UserId)
	if not player then
		return
	end
	local isLocal = player == LocalPlayer
	local bodies = self.Controllers.BodyController
	local sounds = self.Controllers.SoundController
	local oldTotal = BodyShape.FromHeight(tonumber(payload.OldHeight) or 1).Total

	if isLocal then
		sounds:Play("Shrink")
		self.Controllers.CameraController:Shake(0.4, 0.6)
	end
	task.delay(0.6, function()
		-- flatten like a pancake...
		bodies:Kick(player, -2)
		local center = self:BodyCenter(player)
		local body = bodies:GetBody(player)
		local feet = body and body.FeetCF and body.FeetCF.Position or center
		if not feet then
			return
		end
		local radius = math.clamp(oldTotal * 0.35, 8, 160)
		-- ...then BOOM
		self:Boom(feet + Vector3.new(0, 1, 0), radius, Color3.fromRGB(255, 240, 150))
		self:Shockwave(feet, radius * 1.4, Color3.fromRGB(120, 255, 170))
		self:BurstAt(feet + Vector3.new(0, 2, 0), math.clamp(radius / 10, 1, 16), { Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 220, 60), Color3.fromRGB(80, 220, 255), Color3.fromRGB(200, 90, 255) }, 60, "Confetti")
		self:BurstAt(feet + Vector3.new(0, 2, 0), math.clamp(radius / 10, 1, 16), { Color3.new(1, 1, 1), Color3.fromRGB(255, 240, 150) }, 30, "Glow")
		if isLocal then
			sounds:Play("Boom")
			sounds:Play("Rebirth")
			self:ScreenFlash(Color3.new(1, 1, 1), 0.85, 0.7)
			self.Controllers.CameraController:Shake(1.6, 0.8)
			self.Controllers.CameraController:Kick(10)
			self:BigText(
				"REBIRTH!",
				string.format("%s GROWTH   •   +%s 💎", Format.Mult(payload.NewMult or 1), Format.Number(payload.Gems or 0)),
				Theme.Colors.Green
			)
		end
		task.delay(0.25, function()
			bodies:Kick(player, 2.5) -- and pop back up, ready to grow again
		end)
	end)
end

---------------------------------------------------------------------------
-- other one-shot effects
---------------------------------------------------------------------------
function EffectsController:Celebrate(scale: number?)
	local center, total = self:BodyCenter(LocalPlayer)
	if not center then
		return
	end
	local s = math.clamp((scale or 1) * total / 10, 0.6, 20)
	self:BurstAt(center + Vector3.new(0, total * 0.3, 0), s, { Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 220, 60), Color3.fromRGB(80, 220, 255), Color3.fromRGB(120, 255, 120) }, 50, "Confetti")
end

function EffectsController:OnEffect(payload)
	if type(payload) ~= "table" then
		return
	end
	local name = payload.Name
	local sounds = self.Controllers.SoundController
	if name == "Rebirth" then
		self:Rebirth(payload)
	elseif name == "Hatch" then
		self.Controllers.HatchController:PlayHatch(payload)
	elseif name == "PetReward" then
		self.Controllers.HatchController:ShowReward(payload.Id)
	elseif name == "ZoneUnlocked" then
		self:Celebrate(1.5)
		self.Controllers.CameraController:Shake(0.8, 0.6)
	elseif name == "Upgrade" then
		sounds:Play("Upgrade")
		local center, total = self:BodyCenter(LocalPlayer)
		if center then
			self:BurstAt(center, math.clamp(total / 10, 0.5, 15), { Theme.Colors.Blue, Color3.new(1, 1, 1) }, 18, "Glow")
		end
	elseif name == "Boost" then
		sounds:Play("Reward")
		self:ScreenFlash(Theme.Colors.Green, 0.35, 0.5)
		self:Celebrate(0.8)
	elseif name == "Chest" then
		sounds:Play("Chest")
		if typeof(payload.Position) == "Vector3" then
			self:BurstAt(payload.Position + Vector3.new(0, 3, 0), 1.5, { Theme.Colors.Yellow, Color3.new(1, 1, 1) }, 40, "Confetti")
		end
	elseif name == "Teleported" then
		sounds:Play("Teleport")
		self:ScreenFlash(Color3.new(1, 1, 1), 0.6, 0.4)
	end
end

function EffectsController:Start()
	Net.Event("Effect").OnClientEvent:Connect(function(payload)
		self:OnEffect(payload)
	end)
end

return EffectsController
