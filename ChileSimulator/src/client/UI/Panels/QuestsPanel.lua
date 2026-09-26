--[[
	QuestsPanel - 3 daily quests + achievements.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardConfig = require(Shared.RewardConfig)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Widgets = require(UI.Widgets)

local Panel = { Title = "QUESTS", Icon = "📜", Color = Theme.Colors.Pink }

local function goalText(quest): string
	local goal = if quest.IsLength then Format.Length(quest.Goal) else Format.Number(quest.Goal)
	return string.format(quest.Text, goal)
end

function Panel.Create(content: Frame, controllers)
	local data = controllers.ClientData
	local tabs = Widgets.Tabs(content, { "DAILY QUESTS", "ACHIEVEMENTS" })

	-- daily quests
	local questPage = tabs.Pages["DAILY QUESTS"]
	local resetLabel = Kit.Label({
		Size = UDim2.new(1, 0, 0, 26),
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		Parent = questPage,
	})
	local questRows = {}
	for i, quest in RewardConfig.Quests do
		local frame = Widgets.Row(questPage, 84, i)
		frame.Position = UDim2.fromOffset(3, 32 + (i - 1) * 92)
		Kit.Label({
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.new(1, -230, 0, 28),
			Text = goalText(quest),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		local bar = Widgets.ProgressBar(frame, UDim2.new(1, -230, 0, 26), UDim2.fromOffset(14, 42), Theme.Colors.Pink)
		local button, label = Kit.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(190, 56),
			Parent = frame,
			OnClick = function()
				data:Fire("ClaimQuest", quest.Id)
			end,
		})
		questRows[quest.Id] = { Bar = bar, Button = button, Label = label, Quest = quest }
	end

	-- achievements
	local achList = Widgets.Scroll(tabs.Pages.ACHIEVEMENTS)
	local achRows = {}
	for i, ach in RewardConfig.Achievements do
		local frame = Widgets.Row(achList, 56, i)
		local check = Kit.Label({
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(40, 40),
			Text = "🏆",
			StrokeThickness = 0,
			Parent = frame,
		})
		Kit.Label({
			Position = UDim2.fromOffset(56, 4),
			Size = UDim2.new(1, -250, 0, 26),
			Text = ach.Name,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		Kit.Label({
			Position = UDim2.fromOffset(56, 30),
			Size = UDim2.new(1, -250, 0, 20),
			Text = ach.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Colors.TextDim,
			Font = Theme.Fonts.Body,
			StrokeThickness = 0,
			Parent = frame,
		})
		local status = Kit.Label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 8),
			Size = UDim2.fromOffset(180, 40),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = frame,
		})
		achRows[ach.Id] = { Frame = frame, Check = check, Status = status, Ach = ach }
	end

	local api = {}
	function api.Refresh()
		local rewards = data:Get("Rewards")
		local stats = data:Get("Stats")
		if not rewards or not stats then
			return
		end
		for id, entry in questRows do
			local quest = entry.Quest
			local progress = rewards.Quests.Progress[quest.Stat] or 0
			local claimed = rewards.Quests.Claimed[id] == true
			local shown = if quest.IsLength then Format.Length(math.min(progress, quest.Goal)) else Format.Number(math.min(progress, quest.Goal))
			local goal = if quest.IsLength then Format.Length(quest.Goal) else Format.Number(quest.Goal)
			entry.Bar.Set(progress / quest.Goal, shown .. " / " .. goal)
			if claimed then
				entry.Label.Text = "✔ CLAIMED"
				Kit.SetButtonColor(entry.Button, Theme.Colors.GrayDark)
			elseif progress >= quest.Goal then
				entry.Label.Text = "CLAIM " .. quest.RewardLabel
				Kit.SetButtonColor(entry.Button, Theme.Colors.Green)
			else
				entry.Label.Text = "🎁 " .. quest.RewardLabel
				Kit.SetButtonColor(entry.Button, Theme.Colors.PanelDark)
			end
		end
		for id, entry in achRows do
			local ach = entry.Ach
			if rewards.Achievements[id] then
				entry.Status.Text = "✔ +" .. ach.Gems .. " 💎"
				entry.Status.TextColor3 = Theme.Colors.Green
				entry.Frame.LayoutOrder = 1000 + entry.Frame.LayoutOrder % 1000
				entry.Check.Text = "✅"
			else
				local value
				if ach.Stat == "BestHeight" then
					value = stats.BestHeight
				elseif ach.Stat == "Taps" or ach.Stat == "Rebirths" then
					value = stats[ach.Stat]
				else
					value = rewards.Stats and rewards.Stats[ach.Stat] or 0
				end
				local fraction = math.clamp(value / ach.Goal, 0, 1)
				entry.Status.Text = string.format("%d%%  •  %d 💎", math.floor(fraction * 100), ach.Gems)
				entry.Status.TextColor3 = Theme.Colors.TextDim
				entry.Check.Text = "🏆"
			end
		end
	end
	function api.Tick()
		local rewards = data:Get("Rewards")
		if rewards and rewards.Daily then
			local left = rewards.Daily.SecondsToReset - (os.clock() - data.RewardsClock)
			resetLabel.Text = "New quests in " .. Format.Time(math.max(0, left))
		end
	end
	return api
end

return Panel
