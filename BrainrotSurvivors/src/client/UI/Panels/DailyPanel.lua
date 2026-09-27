--[[
	DailyPanel - daily login reward (7-day streak) and today's 3 quests.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local MetaData = require(Shared.MetaData)
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors

local Panel = {}
Panel.Title = "DAILY"
Panel.Size = Vector2.new(820, 520)

function Panel.Build(body: Frame, controllers)
	local state = { C = controllers, Days = {}, Quests = {} }
	Kit.Label({ Text = "📅 DAILY REWARD", Size = UDim2.fromOffset(400, 30), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.Fonts.Title, Parent = body })
	local days = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 90), Position = UDim2.fromOffset(0, 36), Parent = body })
	Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = days })
	for i, coins in MetaData.DailyRewards do
		local day = Kit.Panel({ Size = UDim2.fromOffset(100, 86), BackgroundColor3 = C.PanelLight, LayoutOrder = i, Radius = 12, Parent = days })
		Kit.Label({ Text = "DAY " .. i, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 6), Parent = day })
		Kit.Label({ Text = "🪙 " .. coins, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 38), TextColor3 = C.Coin, Parent = day })
		state.Days[i] = day
	end
	local claim, claimLabel = Kit.Button({
		Text = "CLAIM",
		Size = UDim2.fromOffset(260, 52),
		Position = UDim2.fromOffset(0, 134),
		Color = C.Lime,
		OnClick = function()
			controllers.ClientData:Fire("ClaimDaily")
		end,
		Parent = body,
	})
	state.Claim, state.ClaimLabel = claim, claimLabel

	Kit.Label({ Text = "🎯 TODAY'S QUESTS", Size = UDim2.fromOffset(400, 30), Position = UDim2.fromOffset(0, 200), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.Fonts.Title, Parent = body })
	for i = 1, 3 do
		local row = Widgets.Row(body, 70, i)
		row.Position = UDim2.fromOffset(0, 236 + (i - 1) * 78)
		local text = Kit.Label({ Text = "", Size = UDim2.new(1, -200, 0, 30), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		local bar = Widgets.Bar(row, UDim2.new(1, -220, 0, 20), UDim2.fromOffset(12, 40), C.Lime)
		local button, label = Kit.Button({
			Text = "",
			Size = UDim2.fromOffset(170, 50),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Color = C.Gray,
			OnClick = function()
				controllers.ClientData:Fire("ClaimQuest", i)
			end,
			Parent = row,
		})
		state.Quests[i] = { Row = row, Text = text, Bar = bar, Button = button, Label = label }
	end
	return state
end

function Panel.Refresh(state, data)
	local daily = data.Daily
	local streakDay = (daily.Streak - 1) % #MetaData.DailyRewards + 1
	for i, day in state.Days do
		day.BackgroundColor3 = if i == streakDay then C.Pink elseif i < streakDay then C.LimeDark else C.PanelLight
	end
	state.ClaimLabel.Text = if daily.CanClaim then "CLAIM 🪙 " .. Format.Commas(daily.Reward) else "COME BACK TOMORROW"
	Kit.SetButtonColor(state.Claim, if daily.CanClaim then C.Lime else C.Gray)
	for i, ui in state.Quests do
		local q = data.Quests[i]
		ui.Row.Visible = q ~= nil
		if q then
			ui.Text.Text = q.Text
			ui.Bar:Set(q.Progress / math.max(1, q.Goal), string.format("%s / %s", Format.Commas(q.Progress), Format.Commas(q.Goal)))
			local done = q.Progress >= q.Goal
			ui.Label.Text = if q.Claimed then "✔ DONE" elseif done then "CLAIM 🪙 " .. q.Coins else "🪙 " .. q.Coins
			Kit.SetButtonColor(ui.Button, if q.Claimed then C.Gold elseif done then C.Lime else C.Gray)
		end
	end
end

return Panel
