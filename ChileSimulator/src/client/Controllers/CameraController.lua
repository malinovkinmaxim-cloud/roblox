--[[
	CameraController - the default Roblox camera, tuned for a body that goes from 1 stud to
	600 studs tall:

	  * zoom range follows your body: the camera pulls back as you grow, so the whole
	    stretched body (and later the "head in the clouds") stays in frame
	  * the camera looks at the upper body instead of the invisible physical rig
	  * FOV kick on taps, screen shake on big moments (can be turned off in Settings)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local CameraController = {}

local BASE_FOV = 70

function CameraController:Init(controllers)
	self.Controllers = controllers
	self.FovKick = 0
	self.ShakeTime = 0
	self.ShakeDuration = 0
	self.ShakeStrength = 0
	self.MinZoom = 0
	self.MaxZoom = 0
	self.Offset = Vector3.zero
end

function CameraController:Kick(amount: number)
	self.FovKick = math.min(self.FovKick + amount, 10)
end

function CameraController:Shake(strength: number, duration: number)
	if not self.Controllers.ClientData:Setting("Shake") then
		return
	end
	self.ShakeStrength = math.max(self.ShakeStrength, strength)
	self.ShakeDuration = math.max(duration, 0.05)
	self.ShakeTime = self.ShakeDuration
end

function CameraController:Step(dt: number)
	local camera = Workspace.CurrentCamera
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local body = self.Controllers.BodyController:GetBody(LocalPlayer)
	if not camera or not humanoid or not body or not body.Shape then
		return
	end
	local total = body.Shape.Total

	-- zoom range scales with the body
	local ideal = math.clamp(total * 1.35 + 7, 9, 1800)
	local minZoom = ideal * 0.45
	local maxZoom = ideal * 2.4 + 20
	if math.abs(minZoom - self.MinZoom) > self.MinZoom * 0.02 + 0.05 then
		self.MinZoom = minZoom
		LocalPlayer.CameraMinZoomDistance = minZoom
	end
	if math.abs(maxZoom - self.MaxZoom) > self.MaxZoom * 0.02 + 0.05 then
		self.MaxZoom = maxZoom
		LocalPlayer.CameraMaxZoomDistance = maxZoom
	end

	-- look at the upper body (root is ~3 studs above the feet)
	local root = body.Root
	local feetY = body.FeetCF and body.FeetCF.Position.Y or root.Position.Y - 3
	local focusY = feetY + total * 0.6
	local offsetY = focusY - root.Position.Y

	-- shake
	local shake = Vector3.zero
	if self.ShakeTime > 0 then
		self.ShakeTime -= dt
		local k = math.max(0, self.ShakeTime / self.ShakeDuration)
		local s = self.ShakeStrength * k * math.max(1, total * 0.02)
		shake = Vector3.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, (math.random() - 0.5) * s)
		if self.ShakeTime <= 0 then
			self.ShakeStrength = 0
		end
	end
	humanoid.CameraOffset = Vector3.new(0, offsetY, 0) + shake

	-- FOV kick decays back
	self.FovKick *= math.exp(-dt * 9)
	camera.FieldOfView = BASE_FOV + self.FovKick
end

function CameraController:Start()
	RunService:BindToRenderStep("ChileCamera", Enum.RenderPriority.Camera.Value - 1, function(dt)
		self:Step(math.min(dt, 0.1))
	end)
end

return CameraController
