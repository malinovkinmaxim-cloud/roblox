--[[
	CollectionPanel - enemy and boss collection: every enemy you have defeated, how many times,
	with its description. Undiscovered ones are "???" (secret ones included).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local EnemyData = require(Shared.EnemyData)
local Format = require(Shared.Util.Format)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors

local Panel = {}
Panel.Title = "COLLECTION"
Panel.Size = Vector2.new(900, 520)

function Panel.Build(body: Frame, _controllers)
	local summary = Kit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 30), TextColor3 = C.Gold, Parent = body })
	local holder = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -38), Position = UDim2.fromOffset(0, 38), Parent = body })
	local scroll = Widgets.Scroll(holder, Vector2.new(270, 120), 8)
	local cards = {}
	local order = 0
	for _, def in EnemyData.List do
		if def.Collection then
			order += 1
			local boss = def.Boss or def.MiniBoss
			local card = Kit.Panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = if boss then C.RedDark else C.PanelLight, LayoutOrder = (if boss then 100 else 0) + order, Radius = 12, Parent = scroll })
			local swatch = Kit.New("Frame", { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(10, 10), BackgroundColor3 = def.Color, Parent = card })
			Kit.Corner(swatch, 22)
			Kit.Stroke(swatch, 3)
			local name = Kit.Label({ Text = def.Name, Size = UDim2.new(1, -74, 0, 26), Position = UDim2.fromOffset(62, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
			local count = Kit.Label({ Text = "", Size = UDim2.new(1, -74, 0, 20), Position = UDim2.fromOffset(62, 34), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.Gold, Font = Theme.Fonts.Body, Parent = card })
			local desc = Kit.Label({
				Text = def.Desc,
				Size = UDim2.new(1, -20, 0, 52),
				Position = UDim2.fromOffset(10, 62),
				TextWrapped = true,
				Font = Theme.Fonts.Body,
				TextColor3 = C.TextDim,
				StrokeThickness = 0,
				Parent = card,
			})
			cards[def.Key] = { Swatch = swatch, Name = name, Count = count, Desc = desc, Def = def }
		end
	end
	return { Summary = summary, Cards = cards }
end

function Panel.Refresh(state, data)
	local found, total = 0, 0
	for key, ui in state.Cards do
		total += 1
		local n = data.Collection[key] or 0
		local def = ui.Def
		if n > 0 then
			found += 1
			ui.Name.Text = def.Name
			ui.Desc.Text = def.Desc
			ui.Count.Text = "Defeated x" .. Format.Commas(n)
			ui.Swatch.BackgroundColor3 = def.Color
		else
			ui.Name.Text = "???"
			ui.Desc.Text = if def.Secret then "A secret. Very rare." else "Not defeated yet."
			ui.Count.Text = ""
			ui.Swatch.BackgroundColor3 = C.Gray
		end
	end
	state.Summary.Text = string.format("📚 Discovered %d / %d", found, total)
end

return Panel
