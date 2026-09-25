--[[
	SpectateController - SpectatorUI
	From the lobby you can watch players that are currently inside a level
	(the server marks them with the "InLevel" attribute). Camera only - nothing is sent to the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Format = require(ReplicatedStorage.Shared.Util.Format)

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)

local SpectateController = {}

local C = Theme.Colors
local player = Players.LocalPlayer

function SpectateController:Init(controllers)
	self.Controllers = controllers
	self.Target = nil
end

function SpectateController:Start()
	local gui = Kit.Screen("SpectatorUI", 25)
	gui.Enabled = false
	self.Gui = gui
	local bar = Kit.Panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(560, 70),
		Parent = gui,
	})
	Kit.Button({ Text = "<", Size = UDim2.fromOffset(56, 50), Position = UDim2.fromOffset(10, 10), TextSize = 24, Parent = bar }, function()
		self:Cycle(-1)
	end)
	Kit.Button({ Text = ">", Size = UDim2.fromOffset(56, 50), Position = UDim2.new(1, -196, 0, 10), TextSize = 24, Parent = bar }, function()
		self:Cycle(1)
	end)
	Kit.Button({
		Text = "EXIT",
		Size = UDim2.fromOffset(120, 50),
		Position = UDim2.new(1, -130, 0, 10),
		Color = Color3.fromRGB(120, 40, 50),
		Parent = bar,
	}, function()
		self:Stop()
	end)
	Kit.Text({
		Position = UDim2.fromOffset(76, 8),
		Size = UDim2.new(1, -282, 0, 18),
		TextSize = 13,
		TextColor3 = C.TextDim,
		Text = "SPECTATING",
		Parent = bar,
	})
	self.NameText = Kit.Text({
		Position = UDim2.fromOffset(76, 26),
		Size = UDim2.new(1, -282, 0, 36),
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Text = "",
		Parent = bar,
	})

	-- stop when our own run starts, or when the target leaves the level
	self.Controllers.ClientState.Changed:Connect(function(key)
		if key == "Run" and self.Controllers.ClientState.Run then
			self:Stop()
		end
	end)
	Players.PlayerRemoving:Connect(function(leaving)
		if leaving == self.Target then
			self:Cycle(1)
		end
	end)
end

function SpectateController:GetTargets(): { Player }
	local list = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("InLevel") ~= nil then
			table.insert(list, other)
		end
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

function SpectateController:IsActive(): boolean
	return self.Target ~= nil
end

function SpectateController:Begin(): boolean
	local targets = self:GetTargets()
	if #targets == 0 then
		self.Controllers.HudController:Toast("Nobody is playing a level right now.", "Info")
		return false
	end
	self:_watch(targets[1])
	return true
end

function SpectateController:Cycle(direction: number)
	local targets = self:GetTargets()
	if #targets == 0 then
		self:Stop()
		return
	end
	local index = table.find(targets, self.Target :: Player) or 0
	index = ((index - 1 + direction) % #targets) + 1
	self:_watch(targets[index])
end

function SpectateController:_watch(target: Player)
	self.Target = target
	if self.LevelConnection then
		self.LevelConnection:Disconnect()
	end
	self.LevelConnection = target:GetAttributeChangedSignal("InLevel"):Connect(function()
		if target:GetAttribute("InLevel") == nil then
			task.defer(function()
				self:Cycle(1)
			end)
		else
			self:_refreshName()
		end
	end)
	self:_refreshName()
	self.Gui.Enabled = true
	self.Controllers.MenuController:ClosePanel()
	self:_follow()
	if self.CharacterConnection then
		self.CharacterConnection:Disconnect()
	end
	self.CharacterConnection = target.CharacterAdded:Connect(function()
		task.wait(0.1)
		if self.Target == target then
			self:_follow()
		end
	end)
end

function SpectateController:_refreshName()
	local target = self.Target
	if not target then
		return
	end
	local levelId = target:GetAttribute("InLevel")
	local entry = levelId and self.Controllers.ClientState.CatalogById[levelId]
	self.NameText.Text = string.format(
		"%s  ·  LEVEL %s %s",
		target.DisplayName,
		if levelId then Format.LevelNumber(levelId) else "--",
		if entry then entry.Name else ""
	)
end

function SpectateController:_follow()
	local camera = Workspace.CurrentCamera
	local target = self.Target
	local character = target and target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera and humanoid then
		camera.CameraSubject = humanoid
	end
end

function SpectateController:Stop()
	self.Target = nil
	if self.LevelConnection then
		self.LevelConnection:Disconnect()
		self.LevelConnection = nil
	end
	if self.CharacterConnection then
		self.CharacterConnection:Disconnect()
		self.CharacterConnection = nil
	end
	if self.Gui then
		self.Gui.Enabled = false
	end
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera and humanoid then
		camera.CameraSubject = humanoid
	end
end

return SpectateController
