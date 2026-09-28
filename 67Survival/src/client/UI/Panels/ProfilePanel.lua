--[[
	ProfilePanel - you: avatar, account level (grows every run) with its title,
	and a few key numbers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local AchievementData = require(Shared.AchievementData)
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Window"
Panel.Title = "PROFILE"
Panel.Size = Vector2.new(560, 384)

function Panel.Build(body: Frame, _controllers)
	local player = Players.LocalPlayer
	local state = {}
	local avatar = Kit.New("ImageLabel", {
		Name = "Avatar",
		Size = UDim2.fromOffset(96, 96),
		BackgroundColor3 = C.SurfaceLight,
		Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", player.UserId),
		Parent = body,
	})
	Kit.Corner(avatar, 48)
	Kit.Stroke(avatar, 2, C.Accent, 0.2)
	Kit.Label({
		Name = "DisplayName",
		Text = player.DisplayName,
		Size = UDim2.new(1, -120, 0, 28),
		Position = UDim2.fromOffset(118, 6),
		Font = F.Title,
		MaxTextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	Kit.Label({
		Name = "UserName",
		Text = "@" .. player.Name,
		Size = UDim2.new(1, -120, 0, 18),
		Position = UDim2.fromOffset(118, 36),
		Font = F.Medium,
		MaxTextSize = 15,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	state.Title = Widgets.Tag(body, "", C.Accent, UDim2.fromOffset(118, 64), UDim2.fromOffset(0, 24))
	state.Title.AutomaticSize = Enum.AutomaticSize.X
	state.Title.TextScaled = false
	state.Title.TextSize = 13

	Widgets.Caption(body, "ACCOUNT LEVEL", UDim2.fromOffset(0, 118))
	state.Level = Kit.Label({
		Name = "Level",
		Text = "1",
		Size = UDim2.fromOffset(120, 34),
		Position = UDim2.fromOffset(0, 134),
		Font = F.Title,
		MaxTextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	state.XPText = Kit.Label({
		Name = "XP",
		Text = "",
		Size = UDim2.fromOffset(200, 18),
		Position = UDim2.new(1, 0, 0, 146),
		AnchorPoint = Vector2.new(1, 0),
		Font = F.Bold,
		MaxTextSize = 14,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = body,
	})
	state.Bar = Widgets.Bar(body, UDim2.new(1, 0, 0, 10), UDim2.fromOffset(0, 174), C.Accent)
	state.Bar.Label.Visible = false

	local tiles = Kit.New("Frame", { Name = "Tiles", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 84), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1), Parent = body })
	Kit.New("UIGridLayout", { CellSize = UDim2.new(1 / 3, -8, 1, 0), CellPadding = UDim2.fromOffset(12, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tiles })
	state.Tiles = {}
	for i, key in { "BestTime", "BestLevel", "Achievements" } do
		local tile = Kit.Panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.SurfaceLight, BackgroundTransparency = 0.45, LayoutOrder = i, Radius = 12, Parent = tiles })
		Widgets.Caption(tile, if key == "BestTime" then "BEST TIME" elseif key == "BestLevel" then "BEST LEVEL" else "ACHIEVEMENTS", UDim2.fromOffset(14, 14), 140)
		state.Tiles[key] = Kit.Label({
			Text = "",
			Size = UDim2.new(1, -28, 0, 28),
			Position = UDim2.fromOffset(14, 38),
			Font = F.Title,
			MaxTextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = tile,
		})
	end
	return state
end

function Panel.Refresh(state, data)
	local stats = data.Stats or {}
	state.Title.Text = string.upper(data.Title or "")
	state.Title.Visible = (data.Title or "") ~= ""
	state.Level.Text = tostring(data.Level or 1)
	local need = math.max(1, data.LevelNeed or 1)
	local have = data.LevelXP or 0
	state.Bar:Set(have / need)
	state.XPText.Text = string.format("%s / %s XP", Widgets.Commas(have), Widgets.Commas(need))
	state.Tiles.BestTime.Text = Format.Time(stats.BestTime or 0)
	state.Tiles.BestLevel.Text = tostring(stats.BestLevel or 0)
	local got = 0
	for _ in data.Achievements or {} do
		got += 1
	end
	state.Tiles.Achievements.Text = string.format("%d / %d", got, #AchievementData.List)
end

return Panel
