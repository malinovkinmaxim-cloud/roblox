--[[
	ChallengesPanel - window: this week's 3 challenges (coins + FRAGMENTS, reset every
	Monday), the limited-time events running now, and the server goal everyone on the
	server works on together.
]]

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Window"
Panel.Title = "CHALLENGES"
Panel.Size = Vector2.new(640, 520)

local function duration(seconds: number): string
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	if d > 0 then
		return string.format("%dd %dh", d, h)
	end
	return string.format("%dh %dm", h, (seconds % 3600) // 60)
end

function Panel.Build(body: Frame, controllers)
	local state = { C = controllers, Rows = {} }
	Widgets.Caption(body, "WEEKLY CHALLENGES", UDim2.fromOffset(0, 0))
	state.Reset = Kit.Label({
		Text = "",
		Size = UDim2.fromOffset(220, 16),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Font = F.Bold,
		MaxTextSize = 13,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = body,
	})
	for i = 1, 3 do
		local row = Kit.Panel({
			Name = "Challenge" .. i,
			Size = UDim2.new(1, 0, 0, 66),
			Position = UDim2.fromOffset(0, 24 + (i - 1) * 74),
			BackgroundColor3 = C.SurfaceLight,
			BackgroundTransparency = 0.45,
			Radius = 12,
			Parent = body,
		})
		local text = Kit.Label({
			Text = "",
			Size = UDim2.new(1, -200, 0, 20),
			Position = UDim2.fromOffset(14, 10),
			Font = F.Bold,
			MaxTextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local bar = Widgets.Bar(row, UDim2.new(1, -270, 0, 8), UDim2.fromOffset(14, 42), C.Mythic)
		bar.Label.Visible = false
		local count = Kit.Label({
			Text = "",
			Size = UDim2.fromOffset(80, 16),
			Position = UDim2.new(1, -176, 0, 38),
			AnchorPoint = Vector2.new(1, 0),
			Font = F.Bold,
			MaxTextSize = 13,
			TextColor3 = C.TextDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
		local button, label = Kit.Button({
			Text = "",
			Size = UDim2.fromOffset(150, 42),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Color = C.Neutral,
			TextSize = 14,
			OnClick = function()
				controllers.ClientData:Fire("ClaimWeekly", i)
			end,
			Parent = row,
		})
		state.Rows[i] = { Row = row, Text = text, Bar = bar, Count = count, Button = button, Label = label }
	end

	Widgets.Caption(body, "LIMITED-TIME EVENTS", UDim2.fromOffset(0, 256))
	state.Events = Kit.Label({
		Name = "Events",
		Text = "",
		Size = UDim2.new(1, 0, 0, 58),
		Position = UDim2.fromOffset(0, 278),
		Font = F.Medium,
		MaxTextSize = 15,
		TextWrapped = true,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = body,
	})

	Widgets.Caption(body, "SERVER GOAL", UDim2.fromOffset(0, 350))
	state.GoalText = Kit.Label({
		Name = "GoalText",
		Text = "",
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 372),
		Font = F.Bold,
		MaxTextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	state.GoalBar = Widgets.Bar(body, UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 398), C.Gold)
	return state
end

function Panel.Refresh(state, data)
	local weekly = data.Weekly or { List = {}, Left = 0 }
	state.Reset.Text = "NEW CHALLENGES IN " .. duration(weekly.Left or 0)
	for i, ui in state.Rows do
		local q = weekly.List[i]
		ui.Row.Visible = q ~= nil
		if q then
			local done = q.Progress >= q.Goal
			ui.Text.Text = q.Text
			ui.Bar:Set(q.Progress / math.max(1, q.Goal))
			ui.Count.Text = string.format("%s/%s", Widgets.Commas(math.min(q.Progress, q.Goal)), Widgets.Commas(q.Goal))
			local reward = string.format("+%s  +%dF", Widgets.Commas(q.Coins), q.Fragments or 0)
			ui.Label.Text = if q.Claimed then "DONE" elseif done then "CLAIM " .. reward else reward
			Kit.SetButtonColor(ui.Button, if q.Claimed then C.SuccessDark elseif done then C.Success else C.Neutral)
		end
	end
	local lines = {}
	for _, e in data.LiveEvents or {} do
		table.insert(lines, string.format("%s  -  %s  (ends in %s)", e.Title, e.Sub, duration(math.max(0, e.EndsAt - os.time()))))
	end
	state.Events.Text = if #lines > 0 then table.concat(lines, "\n") else "No event right now. 67 WEEKEND starts every Saturday."
	local goal = data.ServerGoal
	if goal then
		state.GoalText.Text = string.format("Defeat %s enemies together on this server: +%d coins for everyone", Widgets.Commas(goal.Goal), goal.Coins)
		state.GoalBar:Set(goal.Kills / math.max(1, goal.Goal), string.format("%s / %s", Widgets.Commas(goal.Kills), Widgets.Commas(goal.Goal)))
	end
end

return Panel
