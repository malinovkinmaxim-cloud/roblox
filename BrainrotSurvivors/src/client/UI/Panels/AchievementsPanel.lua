--[[
	AchievementsPanel - statistics (best time, highest level, totals) and every achievement.
	Secret achievements show "???" until found.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local AchievementData = require(Shared.AchievementData)
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors

local Panel = {}
Panel.Title = "ACHIEVEMENTS"
Panel.Size = Vector2.new(900, 520)

function Panel.Build(body: Frame, _controllers)
	local stats = Kit.Label({
		Text = "",
		Size = UDim2.new(1, 0, 0, 56),
		TextWrapped = true,
		Font = Theme.Fonts.Bold,
		TextColor3 = C.Gold,
		Parent = body,
	})
	local holder = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -64), Position = UDim2.fromOffset(0, 64), Parent = body })
	local scroll = Widgets.Scroll(holder, Vector2.new(410, 64), 8)
	local rows = {}
	for i, def in AchievementData.List do
		local row = Kit.Panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.PanelLight, LayoutOrder = i, Radius = 12, Parent = scroll })
		local icon = Kit.Label({ Text = def.Icon, Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(8, 9), StrokeThickness = 0, Parent = row })
		local name = Kit.Label({ Text = def.Name, Size = UDim2.new(1, -140, 0, 26), Position = UDim2.fromOffset(60, 6), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		local desc = Kit.Label({ Text = def.Desc, Size = UDim2.new(1, -140, 0, 22), Position = UDim2.fromOffset(60, 34), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.Fonts.Body, TextColor3 = C.TextDim, StrokeThickness = 0, Parent = row })
		local reward = Kit.Label({ Text = "🪙 " .. def.Coins, Size = UDim2.fromOffset(80, 26), Position = UDim2.new(1, -86, 0.5, -13), TextColor3 = C.Coin, Parent = row })
		rows[def.Key] = { Row = row, Icon = icon, Name = name, Desc = desc, Reward = reward }
	end
	return { Stats = stats, Rows = rows }
end

function Panel.Refresh(state, data)
	local s = data.Stats
	state.Stats.Text = string.format(
		"⏱ Best %s   ⭐ Best Lv %d   💀 %s defeated   🐉 %d bosses   🔁 %d runs   🏆 %d wins",
		Format.Time(s.BestTime),
		s.BestLevel,
		Format.Commas(s.Kills),
		s.Bosses,
		s.Runs,
		s.Wins
	)
	for _, def in AchievementData.List do
		local ui = state.Rows[def.Key]
		local done = data.Achievements[def.Key] ~= nil
		local hidden = def.Secret and not done
		ui.Icon.Text = if hidden then "❓" else def.Icon
		ui.Name.Text = if hidden then "Secret achievement" else def.Name
		ui.Desc.Text = if hidden then "Keep playing. Look around." else def.Desc
		ui.Row.BackgroundColor3 = if done then C.LimeDark else C.PanelLight
		ui.Reward.Text = if done then "✔" else "🪙 " .. def.Coins
		local progress = ""
		if not done and def.Stat and def.Goal and not hidden then
			progress = string.format("  (%s / %s)", Format.Number(math.min(s[def.Stat] or 0, def.Goal)), Format.Number(def.Goal))
		end
		if not hidden then
			ui.Desc.Text = def.Desc .. progress
		end
	end
end

return Panel
