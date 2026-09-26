--[[
	TapController - TAP -> GROW, and making every single tap FEEL good.

	Input: the big TAP TO GROW button (touch / mouse), left mouse click on the world (PC),
	Space / Enter (PC), R2 / A (gamepad).

	Each tap, instantly and locally:
	  squash & stretch of your body, "+12 cm" popup, particle burst, click sound with random
	  pitch, a small FOV kick - bigger taps get bigger everything.
	Then the tap is counted and sent in a batch every 0.1 s ("I tapped 3 times"). The server
	decides the real growth; the client mirrors the server's rate limit so it never shows a
	"+12 cm" for a tap the server will throw away.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Signal = require(Shared.Util.Signal)

local LocalPlayer = Players.LocalPlayer

local TapController = {}
TapController.Tapped = Signal.new() -- (gain, tier)

function TapController:Init(controllers)
	self.Controllers = controllers
	self.Pending = 0
	self.FlushAcc = 0
	self.Tokens = Config.Tap.Burst
	self.LastRefill = os.clock()
	self.Combo = 0
	self.LastTap = 0
	self.TotalLocal = 0
end

-- mirror of the server token bucket (Logic/Growth)
function TapController:TakeToken(): boolean
	local now = os.clock()
	self.Tokens = math.min(Config.Tap.Burst, self.Tokens + (now - self.LastRefill) * Config.Tap.MaxPerSecond)
	self.LastRefill = now
	if self.Tokens >= 1 then
		self.Tokens -= 1
		return true
	end
	return false
end

-- 0 (1 cm) .. 6 (absurd). Drives how big the feedback is.
function TapController.Tier(gain: number): number
	if gain <= 0 then
		return 0
	end
	return math.clamp(math.floor(math.log10(gain) / 2.5), 0, 6)
end

function TapController:Tap(screenPosition: Vector2?)
	local data = self.Controllers.ClientData
	if not data.Loaded then
		return
	end
	local accepted = self:TakeToken()
	local rates = data:Get("Rates")
	local gain = if accepted and rates then rates.TapGain or 1 else 0
	local tier = TapController.Tier(gain)

	local now = os.clock()
	self.Combo = if now - self.LastTap < 0.45 then self.Combo + 1 else 1
	self.LastTap = now

	-- body jiggle (always, even if throttled - it's our finger)
	local strength = 0.75 + tier * 0.18 + math.min(self.Combo, 20) * 0.01
	self.Controllers.BodyController:Kick(LocalPlayer, if accepted then strength else 0.35)

	if not accepted then
		return
	end
	self.Pending += 1
	self.TotalLocal += 1
	self.Controllers.BodyController.LocalPending += gain

	local effects = self.Controllers.EffectsController
	if data:Setting("Numbers") then
		effects:FloatText(Format.Gain(gain), tier, screenPosition)
	end
	effects:TapBurst(tier)
	local sound = if tier >= 4 then "TapHuge" elseif tier >= 2 then "TapBig" else "Tap"
	self.Controllers.SoundController:Play(sound, 0.92 + math.random() * 0.2 + math.min(self.Combo, 30) * 0.004)
	self.Controllers.CameraController:Kick(0.6 + tier * 0.25)
	self.Tapped:Fire(gain, tier)
end

function TapController:Flush()
	if self.Pending <= 0 then
		return
	end
	local count = math.min(self.Pending, Config.Tap.MaxBatch)
	self.Pending -= count
	self.Controllers.ClientData:Fire("Tap", count)
end

function TapController:Start()
	-- keyboard + gamepad (sinks the input so Space never makes the character jump)
	ContextActionService:BindActionAtPriority("ChileTap", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			if UserInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end
			self:Tap(nil)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonA)

	-- left click on the world (PC). Touches on the world move the camera, so they don't count.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:Tap(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		self.FlushAcc += dt
		if self.FlushAcc >= Config.Tap.ClientFlushInterval then
			self.FlushAcc = 0
			self:Flush()
		end
	end)
end

return TapController
