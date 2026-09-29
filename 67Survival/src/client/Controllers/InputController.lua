--[[
	InputController - the few keys the game needs. Movement is Roblox's own (WASD / arrows /
	gamepad stick / the touch thumbstick); attacking is automatic.

	  1-4 / gamepad A,X,Y,B   pick a level-up card        R / gamepad RB   reroll
	  Esc / P                 pause menu                  Enter            PLAY (lobby)
	  G                       play your emote (lobby)
	  Space / Shift / RT      DASH in a run (with the Rocket Skates relic; jumping is off in runs)
]]

local UserInputService = game:GetService("UserInputService")

local InputController = {}

local CARD_KEYS = {
	One = 1,
	Two = 2,
	Three = 3,
	Four = 4,
	KeypadOne = 1,
	KeypadTwo = 2,
	KeypadThree = 3,
	KeypadFour = 4,
	ButtonA = 1,
	ButtonX = 2,
	ButtonY = 3,
	ButtonB = 4,
}

local DASH_KEYS = { [Enum.KeyCode.Space] = true, [Enum.KeyCode.LeftShift] = true, [Enum.KeyCode.ButtonR2] = true }

function InputController:Init(controllers)
	self.C = controllers
end

function InputController:OnKey(key: Enum.KeyCode)
	local C = self.C
	local levelUp = C.LevelUpController
	if levelUp:IsOpen() then
		local index = CARD_KEYS[key.Name]
		if index then
			levelUp:Pick(index)
		elseif key == Enum.KeyCode.R or key == Enum.KeyCode.ButtonR1 then
			levelUp:Reroll()
		end
		return
	end
	local run = C.RunClient
	if run.Active and DASH_KEYS[key] then
		run:RequestDash()
		return
	end
	if run.Active and not run.Dead and (key == Enum.KeyCode.Escape or key == Enum.KeyCode.P or key == Enum.KeyCode.ButtonStart) then
		C.HudController:TogglePause()
	elseif not run.Active and not C.ResultsController:IsOpen() and key == Enum.KeyCode.Return then
		C.LobbyController:Play()
	elseif not run.Active and key == Enum.KeyCode.G then
		local data = C.ClientData.Data
		local equipped = data and data.Cosmetics and data.Cosmetics.Equipped
		local id = equipped and equipped.Emote
		if id then
			C.ClientData:Fire("Emote", (string.gsub(id, "^Emote%.", "")))
		end
	end
end

function InputController:Start()
	UserInputService.InputBegan:Connect(function(input, processed)
		-- (Space counts as "processed" by the jump binding: the dash still gets it)
		if processed and input.KeyCode ~= Enum.KeyCode.Escape and not DASH_KEYS[input.KeyCode] then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end
		self:OnKey(input.KeyCode)
	end)
end

return InputController
