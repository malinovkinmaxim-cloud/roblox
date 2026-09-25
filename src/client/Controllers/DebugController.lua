--[[
	DebugController (Studio / admins only - the server re-checks every command)
	  Admin Debug UI: DEBUG button (top left) -> panel with every tool.
	  Chat commands: /level 5  /role Shadow  /cp 2  /restart  /finish  /kill  /killdoppel
	                 /ai on|off  /coins 1000  /xp 500  /unlockall  /resetdata  /lobby
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")

local Net = require(ReplicatedStorage.Shared.Net)

local UI = script.Parent.Parent.UI
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)

local DebugController = {}

local C = Theme.Colors
local COMMANDS = { "level", "role", "cp", "restart", "finish", "kill", "killdoppel", "ai", "coins", "xp", "unlockall", "resetdata", "lobby" }

function DebugController:Init(controllers)
	self.Controllers = controllers
end

function DebugController:Start()
	self.Controllers.ClientState:WhenReady(function()
		if not self.Controllers.ClientState.IsDebug then
			return
		end
		self:_buildUI()
		self:_bindChat()
	end)
end

local function send(command: string, argument: string?)
	Net.Event("DebugCommand"):FireServer(command, argument)
end

function DebugController:_bindChat()
	-- TextChatService commands (client-side), fallback to legacy chat
	local ok = pcall(function()
		for _, command in COMMANDS do
			local chatCommand = Instance.new("TextChatCommand")
			chatCommand.Name = "Doppel_" .. command
			chatCommand.PrimaryAlias = "/" .. command
			chatCommand.Triggered:Connect(function(_, text)
				local argument = string.match(text, "^%S+%s+(%S+)")
				send(command, argument)
			end)
			chatCommand.Parent = TextChatService
		end
	end)
	if not ok then
		Players.LocalPlayer.Chatted:Connect(function(message)
			local command, argument = string.match(message, "^/(%S+)%s*(%S*)")
			if command and table.find(COMMANDS, string.lower(command)) then
				send(string.lower(command), if argument ~= "" then argument else nil)
			end
		end)
	end
end

function DebugController:_buildUI()
	local gui = Kit.Screen("DebugUI", 100)
	local panel = Kit.Panel({
		Name = "DebugPanel",
		Position = UDim2.fromOffset(12, 100),
		Size = UDim2.fromOffset(330, 470),
		Visible = false,
		Parent = gui,
	})
	Kit.Button({
		Text = "DEBUG",
		Position = UDim2.new(0, 12, 1, -56),
		Size = UDim2.fromOffset(90, 40),
		TextSize = 16,
		Color = C.Purple,
		TextColor = C.Background,
		Parent = gui,
	}, function()
		panel.Visible = not panel.Visible
	end)
	local body = Kit.New("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 1, -20),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}, { Kit.List(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left) })

	local order = 0
	local function header(text: string)
		order += 1
		Kit.Text({ Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Purple, TextSize = 15, Text = text, LayoutOrder = order, Parent = body })
	end
	local function row()
		order += 1
		local frame = Kit.New("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = body,
		})
		Kit.New("UIGridLayout", {
			CellSize = UDim2.fromOffset(72, 32),
			CellPadding = UDim2.fromOffset(4, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = frame,
		})
		return frame
	end
	local function button(parent: Instance, text: string, fn: () -> (), color: Color3?)
		Kit.Button({ Text = text, Size = UDim2.fromOffset(72, 32), TextSize = 13, Color = color or C.PanelLight, Parent = parent }, fn)
	end

	header("START LEVEL")
	local levels = row()
	for _, entry in self.Controllers.ClientState.Catalog do
		button(levels, tostring(entry.Id), function()
			send("level", tostring(entry.Id))
		end, C.Panel)
	end

	header("SET ROLE (now + next run)")
	local roles = row()
	for _, roleName in { "Follower", "Rival", "Shadow", "Ally", "Troll" } do
		button(roles, roleName, function()
			send("role", roleName)
		end, C.Panel)
	end

	header("CHECKPOINT")
	local cps = row()
	for index = 0, 5 do
		button(cps, "CP " .. index, function()
			send("cp", tostring(index))
		end, C.Panel)
	end

	header("RUN")
	local run = row()
	button(run, "Finish", function()
		send("finish")
	end, C.Green)
	button(run, "Restart", function()
		send("restart")
	end)
	button(run, "Kill me", function()
		send("kill")
	end, C.Red)
	button(run, "Kill dbl", function()
		send("killdoppel")
	end, C.Red)
	button(run, "AI on/off", function()
		send("ai")
	end)
	button(run, "Lobby", function()
		send("lobby")
	end)

	header("PROFILE")
	local profile = row()
	button(profile, "+1000 $", function()
		send("coins", "1000")
	end, C.Yellow)
	button(profile, "+500 XP", function()
		send("xp", "500")
	end, C.Cyan)
	button(profile, "Unlock", function()
		send("unlockall")
	end)
	button(profile, "Reset", function()
		send("resetdata")
	end, C.Red)

	order += 1
	Kit.Text({
		Size = UDim2.new(1, 0, 0, 60),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.Body,
		TextSize = 12,
		TextColor3 = C.TextDim,
		LayoutOrder = order,
		Text = "Chat: /level 5  /role Shadow  /cp 2  /restart  /finish  /kill  /killdoppel  /ai off  /coins 1000  /unlockall  /resetdata  /lobby",
		Parent = body,
	})
end

return DebugController
