--[[
	InputController
	ABILITY / INTERACT for every platform:
	  PC       : Q = ability, E = interact
	  Gamepad  : Y = ability, X = interact
	  Touch    : on-screen buttons (created by HudController, call :Ability() / :Interact())
	Also applies launch-pad impulses the server sends (the client owns its character physics).
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local InputController = {}
InputController.Used = Signal.new() -- ("Ability" | "Interact")

local player = Players.LocalPlayer
local lastUse = { Ability = 0, Interact = 0 }

function InputController:Init(controllers)
	self.Controllers = controllers
end

function InputController:Start()
	local function bind(name: string, key: Enum.KeyCode, pad: Enum.KeyCode, fn: () -> ())
		ContextActionService:BindAction(name, function(_, state)
			if state == Enum.UserInputState.Begin then
				fn()
			end
			return Enum.ContextActionResult.Pass
		end, false, key, pad)
	end
	bind("DoppelAbility", Enum.KeyCode.Q, Enum.KeyCode.ButtonY, function()
		self:Ability()
	end)
	bind("DoppelInteract", Enum.KeyCode.E, Enum.KeyCode.ButtonX, function()
		self:Interact()
	end)

	Net.Event("Launch").OnClientEvent:Connect(function(velocity: Vector3)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and typeof(velocity) == "Vector3" then
			root.AssemblyLinearVelocity = velocity
			self.Controllers.SoundController:Play("Launch")
		end
	end)
end

local function canUse(kind: string): boolean
	local now = os.clock()
	if now - lastUse[kind] < 0.2 then
		return false
	end
	lastUse[kind] = now
	return true
end

function InputController:IsTyping(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

function InputController:Ability()
	local state = self.Controllers.ClientState
	if not state.Run or self:IsTyping() or not canUse("Ability") then
		return
	end
	if not (state.RoleState and state.RoleState.Ability) then
		return
	end
	Net.Event("UseAbility"):FireServer()
	self.Used:Fire("Ability")
end

function InputController:Interact()
	local state = self.Controllers.ClientState
	if not state.Run or self:IsTyping() or not canUse("Interact") then
		return
	end
	if not (state.RoleState and state.RoleState.Interact) then
		return
	end
	Net.Event("UseInteract"):FireServer()
	self.Used:Fire("Interact")
end

function InputController:GetInputMode(): string
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	local last = UserInputService:GetLastInputType()
	if last.Name:find("Gamepad") then
		return "Gamepad"
	end
	if last == Enum.UserInputType.Touch then
		return "Touch"
	end
	return "Keyboard"
end

return InputController
