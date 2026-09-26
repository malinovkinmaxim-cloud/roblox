--[[
	WorldsPanel - every zone, its multiplier and what it takes to unlock it. TELEPORT.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneConfig = require(Shared.ZoneConfig)
local Format = require(Shared.Util.Format)

local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Widgets = require(UI.Widgets)

local Panel = { Title = "WORLDS", Icon = "🌍", Color = Theme.Colors.Green }

function Panel.Create(content: Frame, controllers)
	local data = controllers.ClientData
	local list = Widgets.Scroll(content)
	local rows = {}
	for i, zone in ZoneConfig.Zones do
		local frame = Widgets.Row(list, 68, i)
		local swatch = Kit.New("Frame", {
			BackgroundColor3 = zone.Ground,
			Position = UDim2.fromOffset(10, 10),
			Size = UDim2.fromOffset(48, 48),
			Parent = frame,
		})
		Kit.Corner(swatch, 10)
		Kit.Stroke(swatch, 3, zone.Accent)
		Kit.Label({ Size = UDim2.fromScale(1, 1), Text = tostring(i), Font = Theme.Fonts.Title, Parent = swatch })
		Kit.Label({
			Position = UDim2.fromOffset(70, 6),
			Size = UDim2.new(1, -300, 0, 30),
			Text = string.format("%s   %s growth", zone.Name, Format.Mult(zone.Multiplier)),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		Kit.Label({
			Position = UDim2.fromOffset(70, 38),
			Size = UDim2.new(1, -300, 0, 22),
			Text = zone.Description,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Colors.TextDim,
			Font = Theme.Fonts.Body,
			StrokeThickness = 0,
			Parent = frame,
		})
		local button, label = Kit.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(210, 50),
			Parent = frame,
			OnClick = function()
				local stats = data:Get("Stats")
				if stats and stats.HighestZone >= i then
					data:Fire("TeleportZone", i)
					controllers.PanelController:Close(true)
				else
					controllers.SoundController:Play("Error")
				end
			end,
		})
		rows[i] = { Button = button, Label = label, Zone = zone }
	end

	local api = {}
	function api.Refresh()
		local stats = data:Get("Stats")
		if not stats then
			return
		end
		for i, entry in rows do
			if i == stats.ZoneIndex then
				entry.Label.Text = "📍 YOU ARE HERE"
				Kit.SetButtonColor(entry.Button, Theme.Colors.Purple)
			elseif stats.HighestZone >= i then
				entry.Label.Text = "🌀 TELEPORT"
				Kit.SetButtonColor(entry.Button, Theme.Colors.Green)
			else
				entry.Label.Text = "🔒 " .. Format.Length(entry.Zone.Unlock * 100)
				Kit.SetButtonColor(entry.Button, Theme.Colors.GrayDark)
			end
		end
	end
	return api
end

return Panel
