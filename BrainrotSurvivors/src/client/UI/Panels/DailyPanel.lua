--[[
	DailyPanel - the daily login reward (7-day streak) and today's 3 quests.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local MetaData = require(Shared.MetaData)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Window"
Panel.Title = "DAILY"
Panel.Size = Vector2.new(620, 510)

function Panel.Build(body: Frame, controllers)
	local state = { C = controllers, Days = {}, Quests = {} }
	Widgets.Caption(body, "DAILY REWARD", UDim2.fromOffset(0, 0))
	state.Streak = Kit.Label({
		Text = "",
		Size = UDim2.fromOffset(200, 16),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Font = F.Bold,
		MaxTextSize = 13,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = body,
	})
	local days = Kit.New("Frame", { Name = "Days", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 80), Position = UDim2.fromOffset(0, 24), Parent = body })
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = days,
	})
	for i, coins in MetaData.DailyRewards do
		local day = Kit.Panel({ Size = UDim2.fromOffset(74, 80), BackgroundColor3 = C.SurfaceLight, BackgroundTransparency = 0.45, LayoutOrder = i, Radius = 12, Parent = days })
		Kit.Label({ Text = "DAY " .. i, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 10), Font = F.Bold, MaxTextSize = 12, TextColor3 = C.TextDim, Parent = day })
		Widgets.Coin(day, 20, { Position = UDim2.new(0.5, 0, 0, 32), AnchorPoint = Vector2.new(0.5, 0) })
		Kit.Label({ Text = Widgets.Commas(coins), Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 56), Font = F.Bold, MaxTextSize = 14, TextColor3 = C.Gold, Parent = day })
		state.Days[i] = day
	end
	state.Claim, state.ClaimLabel = Kit.Button({
		Name = "ClaimDaily",
		Text = "CLAIM",
		Size = UDim2.fromOffset(240, 44),
		Position = UDim2.new(0.5, 0, 0, 116),
		AnchorPoint = Vector2.new(0.5, 0),
		Color = C.Success,
		TextSize = 17,
		OnClick = function()
			local data = controllers.ClientData.Data
			if data and data.Daily and data.Daily.CanClaim then
				controllers.ClientData:Fire("ClaimDaily")
			end
		end,
		Parent = body,
	})

	Widgets.Caption(body, "TODAY'S QUESTS", UDim2.fromOffset(0, 184))
	for i = 1, 3 do
		local row = Kit.Panel({
			Name = "Quest" .. i,
			Size = UDim2.new(1, 0, 0, 62),
			Position = UDim2.fromOffset(0, 208 + (i - 1) * 70),
			BackgroundColor3 = C.SurfaceLight,
			BackgroundTransparency = 0.45,
			Radius = 12,
			Parent = body,
		})
		local text = Kit.Label({
			Text = "",
			Size = UDim2.new(1, -190, 0, 20),
			Position = UDim2.fromOffset(14, 10),
			Font = F.Bold,
			MaxTextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local bar = Widgets.Bar(row, UDim2.new(1, -250, 0, 8), UDim2.fromOffset(14, 40), C.Accent)
		bar.Label.Visible = false
		local count = Kit.Label({
			Text = "",
			Size = UDim2.fromOffset(60, 16),
			Position = UDim2.new(1, -170, 0, 36),
			AnchorPoint = Vector2.new(1, 0),
			Font = F.Bold,
			MaxTextSize = 13,
			TextColor3 = C.TextDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
		local button, label = Kit.Button({
			Text = "",
			Size = UDim2.fromOffset(140, 40),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Color = C.Neutral,
			TextSize = 15,
			OnClick = function()
				controllers.ClientData:Fire("ClaimQuest", i)
			end,
			Parent = row,
		})
		state.Quests[i] = { Row = row, Text = text, Bar = bar, Count = count, Button = button, Label = label }
	end
	return state
end

function Panel.Refresh(state, data)
	local daily = data.Daily
	local streakDay = (daily.Streak - 1) % #MetaData.DailyRewards + 1
	local today = if daily.CanClaim then streakDay else streakDay + 1
	for i, day in state.Days do
		local stroke = day:FindFirstChildOfClass("UIStroke")
		local isToday = i == streakDay and daily.CanClaim
		day.BackgroundColor3 = if i < today and not isToday then C.SuccessDark elseif isToday then C.AccentDark else C.SurfaceLight
		day.BackgroundTransparency = if isToday then 0.1 else 0.45
		if stroke then
			stroke.Color = if isToday then C.Accent else C.Border
			stroke.Transparency = if isToday then 0.2 else Theme.BorderTransparency
		end
	end
	state.Streak.Text = "DAY " .. tostring(daily.Streak) .. " STREAK"
	if daily.CanClaim then
		state.ClaimLabel.Text = "CLAIM +" .. Widgets.Commas(daily.Reward)
		Kit.SetButtonColor(state.Claim, C.Success)
	else
		state.ClaimLabel.Text = "COME BACK TOMORROW"
		Kit.SetButtonColor(state.Claim, C.Neutral)
	end
	for i, ui in state.Quests do
		local q = data.Quests[i]
		ui.Row.Visible = q ~= nil
		if q then
			local done = q.Progress >= q.Goal
			ui.Text.Text = q.Text
			ui.Bar:Set(q.Progress / math.max(1, q.Goal))
			ui.Count.Text = string.format("%s/%s", Widgets.Commas(math.min(q.Progress, q.Goal)), Widgets.Commas(q.Goal))
			ui.Label.Text = if q.Claimed then "DONE" elseif done then "CLAIM +" .. q.Coins else "+" .. q.Coins
			Kit.SetButtonColor(ui.Button, if q.Claimed then C.SuccessDark elseif done then C.Success else C.Neutral)
		end
	end
end

return Panel
