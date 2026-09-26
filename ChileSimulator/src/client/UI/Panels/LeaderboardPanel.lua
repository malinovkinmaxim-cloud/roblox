--[[
	LeaderboardPanel - this server, live: who is the tallest right now.
	(All-time global boards stand in the world next to the spawn.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Widgets = require(UI.Widgets)

local Panel = { Title = "TALLEST IN THIS SERVER", Icon = "🏆", Color = Theme.Colors.Yellow }

local MEDALS = { "🥇", "🥈", "🥉" }

function Panel.Create(content: Frame, controllers)
	local _ = controllers
	local list = Widgets.Scroll(content)

	local api = {}
	function api.Refresh()
		Widgets.Clear(list)
		local rows = {}
		for _, player in Players:GetPlayers() do
			local h = player:GetAttribute("Height")
			table.insert(rows, {
				Player = player,
				Height = if type(h) == "number" then h else 1,
				Rebirths = player:GetAttribute("Rebirths") or 0,
			})
		end
		table.sort(rows, function(a, b)
			return a.Height > b.Height
		end)
		for i, entry in rows do
			local isMe = entry.Player == Players.LocalPlayer
			local frame = Widgets.Row(list, 52, i, if isMe then Theme.Colors.PurpleDark else nil)
			Kit.Label({
				Position = UDim2.fromOffset(8, 6),
				Size = UDim2.fromOffset(50, 40),
				Text = MEDALS[i] or ("#" .. i),
				StrokeThickness = if MEDALS[i] then 0 else 2,
				Parent = frame,
			})
			local title = Formulas.Title(entry.Height)
			Kit.Label({
				Position = UDim2.fromOffset(64, 8),
				Size = UDim2.new(0.5, -64, 1, -16),
				Text = string.format('<font color="#%s">[%s]</font> %s%s', title.Color:ToHex(), title.Name, entry.Player.DisplayName, if isMe then " (you)" else ""),
				RichText = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = frame,
			})
			Kit.Label({
				Position = UDim2.new(0.5, 0, 0, 8),
				Size = UDim2.new(0.3, 0, 1, -16),
				Text = "📏 " .. Format.Length(entry.Height),
				TextColor3 = Theme.Colors.Green,
				Parent = frame,
			})
			Kit.Label({
				Position = UDim2.new(0.8, 0, 0, 8),
				Size = UDim2.new(0.2, -10, 1, -16),
				Text = "♻️ " .. Format.Number(entry.Rebirths),
				Parent = frame,
			})
		end
	end
	api.Tick = api.Refresh
	return api
end

return Panel
