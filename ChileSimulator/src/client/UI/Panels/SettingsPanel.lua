--[[
	SettingsPanel - sound, camera shake, numbers, others' effects, low graphics, auto tap,
	save status. Studio / admins also get test buttons.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ShopConfig = require(Shared.ShopConfig)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Widgets = require(UI.Widgets)

local Panel = { Title = "SETTINGS", Icon = "⚙️", Color = Theme.Colors.GrayDark }

local TOGGLES = {
	{ "OneButton", "🔘 One-button mode (auto upgrades, pets, rewards)" },
	{ "Sfx", "🔊 Sound effects" },
	{ "Shake", "📳 Camera shake" },
	{ "Numbers", "🔢 Floating +numbers" },
	{ "OthersFx", "✨ Show other players' pets & effects" },
	{ "LowGraphics", "🔋 Low graphics (fewer particles)" },
	{ "AutoTap", "🤖 Auto Tap (game pass)" },
}

function Panel.Create(content: Frame, controllers)
	local data = controllers.ClientData
	local list = Widgets.Scroll(content)
	local local_ = {} -- optimistic values until the server confirms
	local refreshers = {}

	for i, entry in TOGGLES do
		local key = entry[1]
		local _, refresh = Widgets.Toggle(list, entry[2], i, function()
			if local_[key] ~= nil then
				return local_[key]
			end
			local settings = data:Get("Settings")
			return settings ~= nil and settings[key] == true
		end, function(value)
			local_[key] = value
			data:Fire("SetSetting", key, value)
		end)
		table.insert(refreshers, refresh)
	end

	local status = Kit.Label({
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 50,
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		Parent = list,
	})
	Kit.Label({
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 51,
		Text = Config.GAME_NAME .. "  •  PC: click / SPACE / ENTER to tap  •  E: open eggs",
		TextColor3 = Theme.Colors.TextDim,
		Font = Theme.Fonts.Body,
		StrokeThickness = 0,
		Parent = list,
	})

	-- admin / Studio test tools
	local adminBuilt = false
	local function buildAdmin()
		if adminBuilt then
			return
		end
		adminBuilt = true
		Kit.Label({ Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 60, Text = "🛠️ TEST TOOLS (Studio / admin only)", TextColor3 = Theme.Colors.Yellow, Parent = list })
		local grid = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 250), LayoutOrder = 61, Parent = list })
		Kit.New("UIGridLayout", { CellSize = UDim2.fromOffset(150, 44), CellPadding = UDim2.fromOffset(8, 8), Parent = grid })
		local commands = {
			{ "+ Coins", "coins" },
			{ "+ 1000 Gems", "gems" },
			{ "x10 Height", "height" },
			{ "Free Rebirth", "rebirth" },
			{ "All Boosts", "boosts" },
			{ "Start Event", "event" },
			{ "Spawn Chest", "chest" },
			{ "Secret Pet", "pet" },
			{ "Reset Data", "reset" },
		}
		for _, command in commands do
			Kit.Button({
				Text = command[1],
				Color = if command[2] == "reset" then Theme.Colors.Red else Theme.Colors.Blue,
				Parent = grid,
				OnClick = function()
					data:Fire("Admin", command[2])
				end,
			})
		end
		for _, key in ShopConfig.PassOrder do
			Kit.Button({
				Text = "Pass: " .. ShopConfig.Passes[key].Name,
				Color = Theme.Colors.Yellow,
				Parent = grid,
				OnClick = function()
					data:Fire("Admin", "pass", key)
				end,
			})
		end
		grid.Size = UDim2.new(1, -6, 0, math.ceil((#commands + #ShopConfig.PassOrder) / 4) * 52)
	end

	local api = {}
	function api.Refresh()
		table.clear(local_)
		for _, refresh in refreshers do
			refresh()
		end
		local meta = data:Get("Meta")
		if meta then
			status.Text = (if meta.Persistent then "💾 " else "⚠️ ") .. tostring(meta.SaveStatus)
			if meta.IsAdmin then
				buildAdmin()
			end
		end
	end
	return api
end

return Panel
