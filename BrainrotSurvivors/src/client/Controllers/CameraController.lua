--[[
	CameraController - lobby: the normal Roblox camera. Run: a top-down follow camera at a fixed
	angle (W = up the screen, the thumbstick works the same way), zoom (wheel, pinch, I/O),
	screen shake, "absurd zoom" punches for meme moments and short boss intro pans.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CameraController = {}

local PITCH = math.rad(56)
local ZOOM_MIN, ZOOM_MAX = 38, 96

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

function CameraController:Update(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera or self.Mode ~= "Run" then
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
		camera.FieldOfView = 55
		self.Focus = nil
	else
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

function CameraController:AdjustZoom(delta: number)
	self.Zoom = math.clamp(self.Zoom + delta, ZOOM_MIN, ZOOM_MAX)
end

function CameraController:Start()
	RunService:BindToRenderStep("BrainrotCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
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
