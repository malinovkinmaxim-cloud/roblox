--[[
	FreePanel - FREE REWARDS: gifts for playing 5 / 10 / 20 / 30 / 60 minutes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardConfig = require(Shared.RewardConfig)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Widgets = require(UI.Widgets)

local Panel = { Title = "FREE REWARDS", Icon = "🎁", Color = Theme.Colors.Yellow }

function Panel.Create(content: Frame, controllers)
	local data = controllers.ClientData
	local list = Widgets.Scroll(content)
	local rows = {}
	for i, gift in RewardConfig.Playtime do
		local frame = Widgets.Row(list, 62, i)
		Kit.Label({ Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(46, 46), Text = "🎁", StrokeThickness = 0, Parent = frame })
		Kit.Label({
			Position = UDim2.fromOffset(64, 6),
			Size = UDim2.new(1, -290, 0, 28),
			Text = gift.Label,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		Kit.Label({
			Position = UDim2.fromOffset(64, 34),
			Size = UDim2.new(1, -290, 0, 22),
			Text = "Play " .. gift.Minutes .. " minutes",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Colors.TextDim,
			Font = Theme.Fonts.Body,
			StrokeThickness = 0,
			Parent = frame,
		})
		local button, label = Kit.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(200, 46),
			Parent = frame,
			OnClick = function()
				data:Fire("ClaimPlaytime", i)
			end,
		})
		rows[i] = { Button = button, Label = label, Gift = gift }
	end
	Kit.Label({
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 99,
		Text = "Gifts reset when you join a new server. Also check 📅 DAILY and 📜 QUESTS!",
		TextColor3 = Theme.Colors.TextDim,
		Font = Theme.Fonts.Body,
		StrokeThickness = 0,
		Parent = list,
	})

	local api = {}
	function api.Refresh()
		local rewards = data:Get("Rewards")
		if not rewards then
			return
		end
		local elapsed = (rewards.PlaytimeElapsed or 0) + (os.clock() - data.RewardsClock)
		for i, entry in rows do
			local claimed = rewards.PlaytimeClaimed and rewards.PlaytimeClaimed[tostring(i)]
			local left = entry.Gift.Minutes * 60 - elapsed
			if claimed then
				entry.Label.Text = "✔ CLAIMED"
				Kit.SetButtonColor(entry.Button, Theme.Colors.GrayDark)
			elseif left <= 0 then
				entry.Label.Text = "🎁 CLAIM!"
				Kit.SetButtonColor(entry.Button, Theme.Colors.Green)
			else
				entry.Label.Text = "⏳ " .. Format.Time(left)
				Kit.SetButtonColor(entry.Button, Theme.Colors.PanelDark)
			end
		end
	end
	api.Tick = api.Refresh
	return api
end

return Panel
