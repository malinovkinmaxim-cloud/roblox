--[[
	DebugController - a DEBUG button (Studio / admins only) with one-click test commands:
	jump the timeline, spawn bosses, start events, level up, god mode, coins, unlocks...
	The server checks admin rights again for every command (AdminManager).
]]

local Players = game:GetService("Players")

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)

local DebugController = {}

local C = Theme.Colors

local COMMANDS = {
	{ "+1 MIN", "time", "+60" },
	{ "2:45 BOSS 1", "time", "165" },
	{ "5:45 BOSS 2", "time", "345" },
	{ "8:45 BOSS 3", "time", "525" },
	{ "11:45 BOSS 4", "time", "705" },
	{ "14:45 FINAL", "time", "885" },
	{ "4:25 RIFT", "time", "265" },
	{ "NEXT BOSS NOW", "boss", "" },
	{ "FINAL ONE NOW", "main", "" },
	{ "ELITE", "elite", "" },
	{ "ITEM", "item", "" },
	{ "67 VAULT", "vault", "" },
	{ "67 RUSH", "rush", "" },
	{ "67%", "event", "Percent67" },
	{ "67 CHEST", "event", "Chest67" },
	{ "67 INVASION", "event", "Invasion67" },
	{ "67 LUCK", "event", "Luck67" },
	{ "67 CHAOS", "event", "Chaos67" },
	{ "67 MODE", "event", "Mode67" },
	{ "67 BOSS", "event", "Boss67" },
	{ "THE 67", "event", "The67" },
	{ "+5 LEVELS", "level", "5" },
	{ "EVOLVE", "evolve", "" },
	{ "GOD MODE", "god", "" },
	{ "KILL ALL", "killall", "" },
	{ "DIE", "die", "" },
	{ "+5000 COINS", "coins", "5000" },
	{ "+100 FRAG", "fragments", "100" },
	{ "+1000 CHIPS", "chips", "1000" },
	{ "UNLOCK ITEMS", "unlockitems", "" },
	{ "AFK +2H", "afk", "120" },
	{ "UNLOCK ALL", "unlockall", "" },
	{ "MAX META", "maxmeta", "" },
	{ "NET STATS", "stats", "" },
}

function DebugController:Init(controllers)
	self.C = controllers
	self.Built = false
end

function DebugController:Build()
	if self.Built then
		return
	end
	self.Built = true
	local gui, root = Kit.ScreenGui("S67Debug", 60, Players.LocalPlayer:WaitForChild("PlayerGui"))
	self.Gui = gui
	local panel = Kit.Panel({
		Size = UDim2.fromOffset(612, math.ceil(#COMMANDS / 4) * 50 + 16),
		Position = UDim2.new(1, -8, 1, -46),
		AnchorPoint = Vector2.new(1, 1),
		Visible = false,
		Parent = root,
	})
	local grid = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -16, 1, -16), Position = UDim2.fromOffset(8, 8), Parent = panel })
	Kit.New("UIGridLayout", { CellSize = UDim2.fromOffset(143, 44), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i, cmd in COMMANDS do
		Kit.Button({
			Text = cmd[1],
			Size = UDim2.fromOffset(146, 44),
			Color = C.Neutral,
			TextSize = 14,
			LayoutOrder = i,
			OnClick = function()
				local arg = cmd[3]
				if cmd[2] == "time" and string.sub(arg, 1, 1) == "+" then
					arg = tostring(math.floor(self.C.RunClient.Time + tonumber(string.sub(arg, 2)) :: number))
				end
				self.C.ClientData:Fire("Admin", cmd[2], arg)
			end,
			Parent = grid,
		})
	end
	Kit.Button({
		Text = "DEBUG",
		Size = UDim2.fromOffset(78, 30),
		Position = UDim2.new(1, -8, 1, -8),
		AnchorPoint = Vector2.new(1, 1),
		Color = C.Neutral,
		TextSize = 12,
		OnClick = function()
			panel.Visible = not panel.Visible
		end,
		Parent = root,
	})
end

function DebugController:Start()
	self.C.ClientData.Changed:Connect(function(data)
		if data.Admin then
			self:Build()
		end
	end)
end

return DebugController
