--[[
	DailyPanel - 7 day streak. Claim once a day; miss a day and the streak restarts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardConfig = require(Shared.RewardConfig)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)

local Panel = { Title = "DAILY REWARDS", Icon = "📅", Color = Theme.Colors.Red }

local ICONS = { "🪙", "⚡", "🐾", "💎", "📏", "🐾", "👑" }

function Panel.Create(content: Frame, controllers)
	local data = controllers.ClientData
	local streakLabel = Kit.Label({
		Size = UDim2.new(1, 0, 0, 34),
		Text = "",
		Font = Theme.Fonts.Title,
		Parent = content,
	})
	local row = Kit.New("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 170),
		Parent = content,
	})
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local cards = {}
	for i, day in RewardConfig.Daily do
		local card = Kit.Panel({
			Size = UDim2.fromOffset(88, 164),
			BackgroundColor3 = Theme.Colors.PanelDark,
			LayoutOrder = i,
			Radius = 12,
			Parent = row,
		})
		Kit.Label({ Position = UDim2.fromOffset(4, 6), Size = UDim2.new(1, -8, 0, 24), Text = "DAY " .. i, Font = Theme.Fonts.Title, Parent = card })
		Kit.Label({ Position = UDim2.fromOffset(14, 34), Size = UDim2.fromOffset(60, 60), Text = ICONS[i], StrokeThickness = 0, Parent = card })
		Kit.Label({
			Position = UDim2.fromOffset(4, 98),
			Size = UDim2.new(1, -8, 0, 36),
			Text = day.Label,
			TextWrapped = true,
			Parent = card,
		})
		local state = Kit.Label({ Position = UDim2.fromOffset(4, 136), Size = UDim2.new(1, -8, 0, 22), Text = "", Parent = card })
		cards[i] = { Card = card, State = state }
	end
	local claim, claimLabel = Kit.Button({
		Text = "CLAIM",
		Color = Theme.Colors.Green,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 228),
		Size = UDim2.fromOffset(300, 64),
		Font = Theme.Fonts.Title,
		Parent = content,
		OnClick = function()
			data:Fire("ClaimDaily")
		end,
	})
	local timer = Kit.Label({
		Position = UDim2.fromOffset(0, 300),
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		TextColor3 = Theme.Colors.TextDim,
		Parent = content,
	})

	local api = {}
	function api.Refresh()
		local rewards = data:Get("Rewards")
		if not rewards or not rewards.Daily then
			return
		end
		local daily = rewards.Daily
		streakLabel.Text = string.format("🔥 STREAK: %d", math.max(0, if daily.CanClaim then daily.Streak - 1 else daily.Streak))
		for i, entry in cards do
			local card = entry.Card
			if i < daily.Day or (i == daily.Day and not daily.CanClaim) then
				entry.State.Text = "✔"
				entry.State.TextColor3 = Theme.Colors.Green
				card.BackgroundColor3 = Color3.fromRGB(45, 90, 55)
			elseif i == daily.Day then
				entry.State.Text = "TODAY!"
				entry.State.TextColor3 = Theme.Colors.Yellow
				card.BackgroundColor3 = Theme.Colors.PurpleDark
			else
				entry.State.Text = ""
				card.BackgroundColor3 = Theme.Colors.PanelDark
			end
		end
		claimLabel.Text = if daily.CanClaim then "🎁 CLAIM DAY " .. daily.Day else "COME BACK TOMORROW"
		Kit.SetButtonColor(claim, if daily.CanClaim then Theme.Colors.Green else Theme.Colors.GrayDark)
	end
	function api.Tick()
		local rewards = data:Get("Rewards")
		if rewards and rewards.Daily then
			local left = rewards.Daily.SecondsToReset - (os.clock() - data.RewardsClock)
			timer.Text = "Next reward in " .. Format.Time(math.max(0, left))
		end
	end
	return api
end

return Panel
