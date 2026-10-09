--[[
	CameraController - the camera and the mood of the picture.

	Lobby (hub): a calm showcase camera. It faces your hero on the hub stage from the front,
	keeps the hero a little right of centre (the UI sits in the middle and on the left, on
	every screen shape), follows softly when you walk, drifts very slowly, and a shallow
	depth of field blurs the backdrop. An idle hero on the stage turns back to face the camera.
	Walk away from the stage into 67 LAND (the event map) and it eases into an EXPLORE view:
	higher, wider, looking a little down at the map, with almost no blur. It always looks
	north (+Z), which is why every sign of the map faces south.
	Run: a top-down follow camera at a fixed angle (W = up the screen, the thumbstick works the
	same way), zoom (wheel, pinch, I/O), screen shake, "absurd zoom" punches for meme moments
	and short boss intro pans. Each difficulty tier tints the arena a little (SetMood).
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DifficultyData = require(ReplicatedStorage:WaitForChild("Modules").DifficultyData)

local CameraController = {}

local PITCH = math.rad(56)
local ZOOM_MIN, ZOOM_MAX = 38, 96

-- hub showcase framing (relative to the hero's root)
local HUB_FOV = 40
local RUN_FOV = 55 -- (a run; GameConfig.Feel FovPulse breathes out from it)
local HUB_DIST = 15.5
local HUB_EYE_Y, HUB_LOOK_Y = 1.2, -0.3 -- a low, slightly upward-feeling angle; the hero sits above the plate
local HUB_SCREEN_X = 0.5 -- the hero sits this far right of the screen centre (fraction of half width): the right third
local HUB_FACE_YAW = -0.15 -- idle heroes face the camera, turned a touch towards it
-- the explore view of 67 LAND (blended in as you walk away from the stage)
local EXPLORE_FOV = 55
local EXPLORE_DIST = 21
local EXPLORE_EYE_Y, EXPLORE_LOOK_Y = 7, 2.5 -- about 12 degrees down: the route and the landmarks
local EXPLORE_SCREEN_X = 0.3
local EXPLORE_FROM, EXPLORE_OVER = 8, 14 -- studs from the stage where it starts / is complete
local HUB_BLUR, EXPLORE_BLUR = 0.32, 0.06

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- a light colour grade per difficulty tier (calm -> tense), subtle on purpose
local MOODS = {
	{ Tint = Color3.fromRGB(255, 255, 255), Contrast = 0, Saturation = 0.04, Haze = 0 },
	{ Tint = Color3.fromRGB(255, 255, 255), Contrast = 0, Saturation = 0, Haze = 0 },
	{ Tint = Color3.fromRGB(255, 250, 238), Contrast = 0.04, Saturation = 0.02, Haze = 0.03 },
	{ Tint = Color3.fromRGB(255, 240, 226), Contrast = 0.08, Saturation = 0.04, Haze = 0.06 },
	{ Tint = Color3.fromRGB(255, 228, 216), Contrast = 0.1, Saturation = 0.08, Haze = 0.1 },
	{ Tint = Color3.fromRGB(236, 226, 255), Contrast = 0.12, Saturation = -0.04, Haze = 0.14 },
	{ Tint = Color3.fromRGB(255, 238, 206), Contrast = 0.12, Saturation = 0.1, Haze = 0.16 },
}

function CameraController:Init(controllers)
	self.Controllers = controllers
	self.Mode = "Lobby"
	self.Zoom = 64
	self.Focus = nil :: Vector3?
	self.ShakeAmp = 0
	self.Punch = nil :: { Until: number, Start: number, Factor: number }?
	self.Override = nil :: { Target: Vector3, Until: number }?
	self.Bound = false
end

function CameraController:Shake(amplitude: number)
	if not self.Controllers.ClientData:Setting("Shake") then
		return
	end
	self.ShakeAmp = math.min(3, math.max(self.ShakeAmp, amplitude))
end

-- the field of view breathes out for a moment (getting hurt, a revive): `amount` degrees
function CameraController:FovPulse(amount: number, duration: number)
	local now = os.clock()
	local old = self.Fov
	if old and now < old.Until and old.Amount >= amount then
		return
	end
	self.Fov = { Start = now, Until = now + duration, Amount = amount }
end

-- quick dramatic zoom towards the player (factor < 1 = closer)
function CameraController:ZoomPunch(factor: number, duration: number)
	local now = os.clock()
	self.Punch = { Start = now, Until = now + duration, Factor = factor }
end

function CameraController:LookAt(target: Vector3, duration: number)
	self.Override = { Target = target, Until = os.clock() + duration }
end

local function characterRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

---------------------------------------------------------------------------
-- hub
---------------------------------------------------------------------------
-- where the hub stage is (the lobby spawn point, replicated by the server)
function CameraController:StagePosition(): Vector3?
	if self.Stage then
		return self.Stage
	end
	local spawns = Workspace:FindFirstChild("SpawnPoints")
	local spot = spawns and spawns:FindFirstChild("Lobby")
	if spot and spot:IsA("BasePart") then
		self.Stage = spot.Position
	end
	return self.Stage
end

function CameraController:UpdateHub(camera: Camera, dt: number)
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local root = characterRoot()
	if not root then
		camera.FieldOfView = HUB_FOV
		return
	end
	local now = os.clock()
	local target = root.Position
	local focus = self.HubFocus or target
	focus = focus:Lerp(target, 1 - math.exp(-6 * dt))
	self.HubFocus = focus
	-- showcase on the stage, explore view out in 67 LAND (eased, never a cut)
	local stage = self:StagePosition()
	local away = if stage then Vector3.new(target.X - stage.X, 0, target.Z - stage.Z).Magnitude else 0
	local goal = math.clamp((away - EXPLORE_FROM) / EXPLORE_OVER, 0, 1)
	self.Explore = (self.Explore or 0) + (goal - (self.Explore or 0)) * (1 - math.exp(-2.5 * dt))
	local k = self.Explore * self.Explore * (3 - 2 * self.Explore)
	local fov = lerp(HUB_FOV, EXPLORE_FOV, k)
	camera.FieldOfView = fov
	-- keep the hero at the same spot on any screen shape
	local viewport = camera.ViewportSize
	local aspect = if viewport.Y > 1 then viewport.X / viewport.Y else 16 / 9
	local dist = lerp(HUB_DIST, EXPLORE_DIST, k)
	local side = dist * math.tan(math.rad(fov / 2)) * aspect * lerp(HUB_SCREEN_X, EXPLORE_SCREEN_X, k)
	local drift = Vector3.new(math.sin(now * 0.31) * 0.22, math.sin(now * 0.23) * 0.1, 0) * (1 - k)
	local eye = focus + Vector3.new(side, lerp(HUB_EYE_Y, EXPLORE_EYE_Y, k), -dist) + drift
	camera.CFrame = CFrame.lookAt(eye, focus + Vector3.new(side, lerp(HUB_LOOK_Y, EXPLORE_LOOK_Y, k), 0) + drift * 0.5)
	-- depth of field: the hero is sharp, the backdrop soft (almost none while exploring)
	local dof = self.Dof
	if dof then
		dof.FocusDistance = (eye - target).Magnitude
		dof.FarIntensity = lerp(HUB_BLUR, EXPLORE_BLUR, k)
	end
	-- an idle hero turns back to face the camera
	local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
	if speed < 0.5 then
		self.IdleFor = (self.IdleFor or 0) + dt
	else
		self.IdleFor = 0
	end
	if self.IdleFor > 1.2 and k < 0.2 then
		local look = root.CFrame.LookVector
		local yaw = math.atan2(-look.X, -look.Z)
		local diff = (HUB_FACE_YAW - yaw + math.pi) % (2 * math.pi) - math.pi
		if math.abs(diff) > 0.02 then
			local step = diff * (1 - math.exp(-3 * dt))
			root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw + step, 0)
		end
	end
end

-- the colour mood of the picture: hub (depth of field) or a run on difficulty `tier`
function CameraController:SetMood(mode: string, tier: number?)
	local dof = self.Dof
	if not dof then
		dof = Instance.new("DepthOfFieldEffect")
		dof.Name = "S67HubFocus"
		dof.InFocusRadius = 8
		dof.NearIntensity = 0
		dof.FarIntensity = HUB_BLUR
		dof.FocusDistance = HUB_DIST
		dof.Parent = Lighting
		self.Dof = dof
	end
	dof.Enabled = mode == "Hub"
	local grade = self.Grade
	if not grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "S67Mood"
		grade.Parent = Lighting
		self.Grade = grade
	end
	local mood = if mode == "Run" then MOODS[DifficultyData.Get(tier or 2).Index] else MOODS[2]
	grade.TintColor = mood.Tint
	grade.Contrast = mood.Contrast
	grade.Saturation = mood.Saturation
	local atmosphere = Lighting:FindFirstChild("S67Atmosphere") :: Atmosphere?
	if atmosphere then
		self.BaseHaze = self.BaseHaze or atmosphere.Density
		atmosphere.Density = self.BaseHaze + (if mode == "Run" then mood.Haze else 0)
	end
end

function CameraController:Update(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if self.Mode == "Lobby" then
		self:UpdateHub(camera, dt)
		return
	end
	if self.Mode ~= "Run" then
		return
	end
	local root = characterRoot()
	local target = if root then root.Position else (self.Focus or Vector3.zero)
	local now = os.clock()
	local override = self.Override
	if override then
		if now < override.Until then
			target = override.Target
		else
			self.Override = nil
		end
	end
	local focus = self.Focus or target
	local k = 1 - math.exp(-(if override then 5 else 14) * dt)
	focus = focus:Lerp(target, k)
	self.Focus = focus

	local zoom = self.Zoom
	local punch = self.Punch
	if punch then
		if now >= punch.Until then
			self.Punch = nil
		else
			local t = (now - punch.Start) / (punch.Until - punch.Start)
			-- in fast, hold, out slow
			local w = if t < 0.15 then t / 0.15 elseif t < 0.7 then 1 else 1 - (t - 0.7) / 0.3
			zoom *= 1 + (punch.Factor - 1) * w
		end
	end

	-- FOV pulse: out fast, back slowly
	local fov = RUN_FOV
	local pulse = self.Fov
	if pulse then
		if now >= pulse.Until then
			self.Fov = nil
		else
			local t = (now - pulse.Start) / (pulse.Until - pulse.Start)
			fov += pulse.Amount * (if t < 0.2 then t / 0.2 else 1 - (t - 0.2) / 0.8)
		end
	end
	if camera.FieldOfView ~= fov then
		camera.FieldOfView = fov
	end

	local offset = Vector3.new(0, math.sin(PITCH), math.cos(PITCH)) * zoom
	local cf = CFrame.lookAt(focus + offset, focus + Vector3.new(0, 1.5, 0))
	if self.ShakeAmp > 0.01 then
		local a = self.ShakeAmp
		cf *= CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
		self.ShakeAmp *= math.exp(-9 * dt)
	else
		self.ShakeAmp = 0
	end
	camera.CFrame = cf
end

function CameraController:SetMode(mode: string)
	local camera = Workspace.CurrentCamera
	self.Mode = mode
	if not camera then
		return
	end
	if mode == "Run" then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = RUN_FOV
		self.Focus = nil
		self.Fov = nil
	else
		-- the hub showcase camera (UpdateHub)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = HUB_FOV
		self.HubFocus = nil
		self.Explore = 0
		self.IdleFor = 0
		self:SetMood("Hub")
	end
end

function CameraController:AdjustZoom(delta: number)
	self.Zoom = math.clamp(self.Zoom + delta, ZOOM_MIN, ZOOM_MAX)
end

function CameraController:Start()
	self:SetMode(self.Mode)
	RunService:BindToRenderStep("S67Camera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		self:Update(dt)
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if self.Mode ~= "Run" or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			self:AdjustZoom(-input.Position.Z * 5)
		end
	end)
	UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, state)
		if self.Mode ~= "Run" then
			return
		end
		if state == Enum.UserInputState.Change then
			self:AdjustZoom((1 - scale) * 6)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if self.Mode ~= "Run" or processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.I then
			self:AdjustZoom(-8)
		elseif input.KeyCode == Enum.KeyCode.O then
			self:AdjustZoom(8)
		end
	end)
end

return CameraController
