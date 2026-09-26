--[[
	PanelController - one modal window at a time (Pets, Shop, Rebirth, Boosts, Quests, Daily,
	Free Rewards, Leaderboard, Worlds, Settings).

	Each panel module in UI/Panels returns:
	  { Title, Icon, Color, Create(content: Frame, controllers) -> { Refresh = fn?, Tick = fn? } }
	Panels are built lazily on first open, refreshed when their data changes and ticked once a
	second while open (timers).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)

local LocalPlayer = Players.LocalPlayer

local PanelController = {}

local PANELS = { "Pets", "Shop", "Rebirth", "Boosts", "Quests", "Daily", "Free", "Leaderboard", "Worlds", "Settings" }

function PanelController:Init(controllers)
	self.Controllers = controllers
	self.Modules = {}
	for _, name in PANELS do
		self.Modules[name] = require(UI.Panels:WaitForChild(name .. "Panel"))
	end
	self.Built = {}
	self.Current = nil
	local gui, root = Kit.ScreenGui("ChilePanels", 10, LocalPlayer:WaitForChild("PlayerGui"))
	self.Gui = gui
	self.Root = root
	self.Dim = Kit.New("TextButton", {
		Name = "Dim",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = root,
	})
	self.Dim.Activated:Connect(function()
		self:Close()
	end)
end

function PanelController:Build(name: string)
	local module = self.Modules[name]
	local frame = Kit.Panel({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(700, 450),
		Visible = false,
		ZIndex = 2,
		Parent = self.Root,
	})
	Kit.Gradient(frame, Theme.Colors.PanelLight, Theme.Colors.Panel)
	local header = Kit.New("Frame", {
		BackgroundColor3 = module.Color or Theme.Colors.Blue,
		Size = UDim2.new(1, 0, 0, 56),
		Parent = frame,
	})
	Kit.Corner(header, 16)
	Kit.Gradient(header, (module.Color or Theme.Colors.Blue):Lerp(Color3.new(1, 1, 1), 0.2), module.Color or Theme.Colors.Blue)
	Kit.Label({
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.new(1, -90, 1, -14),
		Text = module.Icon .. "  " .. module.Title,
		Font = Theme.Fonts.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		StrokeThickness = 3,
		Parent = header,
	})
	Kit.Button({
		Text = "X",
		Color = Theme.Colors.Red,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(44, 44),
		Font = Theme.Fonts.Title,
		Radius = 12,
		Parent = header,
		OnClick = function()
			self:Close()
		end,
	})
	local content = Kit.New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 68),
		Size = UDim2.new(1, -36, 1, -82),
		Parent = frame,
	})
	local api = module.Create(content, self.Controllers) or {}
	api.Frame = frame
	self.Built[name] = api
	return api
end

function PanelController:Open(name: string)
	if not self.Modules[name] then
		return
	end
	if self.Current == name then
		return
	end
	self:Close(true)
	local api = self.Built[name] or self:Build(name)
	self.Current = name
	self.Dim.Visible = true
	api.Frame.Visible = true
	Kit.Pop(api.Frame, 0.1)
	if api.Refresh then
		api.Refresh()
	end
	if api.Tick then
		api.Tick()
	end
	self.Controllers.SoundController:Play("Click")
end

function PanelController:Close(silent: boolean?)
	local name = self.Current
	if not name then
		return
	end
	self.Current = nil
	local api = self.Built[name]
	if api then
		api.Frame.Visible = false
		if api.OnClose then
			api.OnClose()
		end
	end
	self.Dim.Visible = false
	if not silent then
		self.Controllers.SoundController:Play("Click")
	end
end

function PanelController:Toggle(name: string)
	if self.Current == name then
		self:Close()
	else
		self:Open(name)
	end
end

function PanelController:Start()
	local data = self.Controllers.ClientData
	-- refresh the open panel when data arrives (at most 5x per second)
	local pending = false
	data.Changed:Connect(function()
		if not self.Current or pending then
			return
		end
		pending = true
		task.delay(0.2, function()
			pending = false
			local api = self.Current and self.Built[self.Current]
			if api and api.Refresh then
				api.Refresh()
			end
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local api = self.Current and self.Built[self.Current]
			if api and api.Tick then
				api.Tick()
			end
		end
	end)
	-- Escape / B closes the panel
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			self:Close()
		end
	end)
end

return PanelController
