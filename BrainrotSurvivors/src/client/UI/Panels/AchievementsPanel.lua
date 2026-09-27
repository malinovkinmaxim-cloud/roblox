--[[
	AchievementsPanel - full-screen, two tabs:
	  ACHIEVEMENTS  every achievement with progress and its coin reward (secret ones stay
	                hidden until found)
	  COLLECTION    every enemy and boss you have defeated, and how many times
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local AchievementData = require(Shared.AchievementData)
local EnemyData = require(Shared.EnemyData)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Screen"
Panel.Title = "ACHIEVEMENTS"

local function row(parent: Instance, order: number): Frame
	return Kit.Panel({
		Size = UDim2.fromScale(1, 1),
		LayoutOrder = order,
		Radius = 14,
		Parent = parent,
	})
end

function Panel.Build(body: Frame, controllers)
	local state = { C = controllers, Rows = {}, Enemies = {}, Pages = {} }

	state.Tabs = Widgets.Tabs(body, { "Achievements", "Collection" }, { Achievements = "ACHIEVEMENTS", Collection = "COLLECTION" }, function(name)
		Panel.Show(state, name)
	end)
	state.Summary = Kit.Label({
		Name = "Summary",
		Text = "",
		Size = UDim2.fromOffset(300, 20),
		Position = UDim2.new(1, 0, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		Font = F.Bold,
		MaxTextSize = 16,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = body,
	})
	local holder = Kit.New("Frame", { Name = "Pages", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -58), Position = UDim2.fromOffset(0, 58), Parent = body })

	-- achievements
	local list = Widgets.Scroll(holder, Vector2.new(494, 76), 12)
	list.Name = "Achievements"
	state.Pages.Achievements = list
	for i, def in AchievementData.List do
		local frame = row(list, i)
		local icon = Kit.New("Frame", { Name = "IconHolder", BackgroundTransparency = 1, Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(14, 14), Parent = frame })
		local name = Kit.Label({
			Name = "Title",
			Text = def.Name,
			Size = UDim2.new(1, -210, 0, 22),
			Position = UDim2.fromOffset(76, 12),
			Font = F.Bold,
			MaxTextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		local desc = Kit.Label({
			Name = "Desc",
			Text = def.Desc,
			Size = UDim2.new(1, -210, 0, 18),
			Position = UDim2.fromOffset(76, 38),
			Font = F.Medium,
			MaxTextSize = 14,
			TextColor3 = C.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		local reward = Kit.New("Frame", {
			Name = "Reward",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(116, 24),
			Position = UDim2.new(1, -16, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = frame,
		})
		Widgets.Coin(reward, 18, { Position = UDim2.new(0, 16, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
		local amount = Kit.Label({
			Text = "+" .. Widgets.Commas(def.Coins),
			Size = UDim2.new(1, -42, 1, 0),
			Position = UDim2.fromOffset(42, 0),
			Font = F.Bold,
			MaxTextSize = 16,
			TextColor3 = C.Gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = reward,
		})
		local done = Widgets.Tag(frame, "DONE", C.Success, UDim2.new(1, -16, 0.5, 0), UDim2.fromOffset(70, 24))
		done.AnchorPoint = Vector2.new(1, 0.5)
		state.Rows[def.Key] = { Frame = frame, Icon = icon, Name = name, Desc = desc, Reward = reward, Amount = amount, Done = done, Mark = "" }
	end

	-- collection
	local grid = Widgets.Scroll(holder, Vector2.new(240, 124), 12)
	grid.Name = "Collection"
	state.Pages.Collection = grid
	local order = 0
	for _, def in EnemyData.List do
		if def.Collection then
			order += 1
			local boss = def.Boss or def.MiniBoss
			local frame = row(grid, (if boss then 100 else 0) + order)
			local swatch = Kit.New("Frame", { Name = "Swatch", Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(14, 14), BackgroundColor3 = def.Color, Parent = frame })
			Kit.Corner(swatch, 20)
			Kit.Stroke(swatch, 2, C.Border, 0.7)
			local name = Kit.Label({
				Name = "Title",
				Text = def.Name,
				Size = UDim2.new(1, -(if boss then 130 else 78), 0, 20),
				Position = UDim2.fromOffset(64, 14),
				Font = F.Bold,
				MaxTextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = frame,
			})
			local count = Kit.Label({
				Name = "Count",
				Text = "",
				Size = UDim2.new(1, -78, 0, 16),
				Position = UDim2.fromOffset(64, 36),
				Font = F.Medium,
				MaxTextSize = 13,
				TextColor3 = C.TextDim,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = frame,
			})
			local desc = Kit.Label({
				Name = "Desc",
				Text = def.Desc,
				Size = UDim2.new(1, -28, 0, 44),
				Position = UDim2.fromOffset(14, 66),
				Font = F.Body,
				MaxTextSize = 13,
				TextWrapped = true,
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = frame,
			})
			if boss then
				local tag = Widgets.Tag(frame, "BOSS", C.Danger, UDim2.new(1, -12, 0, 14), UDim2.fromOffset(52, 20))
				tag.AnchorPoint = Vector2.new(1, 0)
			end
			state.Enemies[def.Key] = { Swatch = swatch, Name = name, Count = count, Desc = desc, Def = def }
		end
	end

	Panel.Show(state, "Achievements")
	return state
end

function Panel.Show(state, name: string)
	state.Current = name
	state.Tabs.Select(name)
	for key, page in state.Pages do
		page.Visible = key == name
	end
	if state.Data then
		Panel.Refresh(state, state.Data)
	end
end

local function setIcon(ui, mark: string, color: Color3)
	local key = mark .. tostring(color)
	if ui.Mark == key then
		return
	end
	ui.Mark = key
	Widgets.Clear(ui.Icon)
	Widgets.Mono(ui.Icon, mark, color, 48)
end

function Panel.Refresh(state, data)
	state.Data = data
	local stats = data.Stats or {}
	local got, total = 0, 0
	for _, def in AchievementData.List do
		total += 1
		local ui = state.Rows[def.Key]
		local done = data.Achievements[def.Key] ~= nil
		local hidden = def.Secret and not done
		if done then
			got += 1
		end
		ui.Name.Text = if hidden then "Secret achievement" else def.Name
		ui.Frame.BackgroundColor3 = if done then C.SurfaceLight else C.Surface
		ui.Done.Visible = done
		ui.Reward.Visible = not done
		if done then
			setIcon(ui, "★", C.Gold)
			ui.Desc.Text = def.Desc
		elseif hidden then
			setIcon(ui, "?", C.TextMuted)
			ui.Desc.Text = "Keep playing. Look around."
		elseif def.Stat and def.Goal then
			local value = math.min(stats[def.Stat] or 0, def.Goal)
			setIcon(ui, string.format("%d%%", math.floor(value / def.Goal * 100)), C.TextMuted)
			ui.Desc.Text = string.format("%s  ·  %s / %s", def.Desc, Widgets.Commas(value), Widgets.Commas(def.Goal))
		else
			setIcon(ui, "0%", C.TextMuted)
			ui.Desc.Text = def.Desc
		end
	end

	local found, kinds = 0, 0
	for key, ui in state.Enemies do
		kinds += 1
		local n = data.Collection[key] or 0
		local def = ui.Def
		if n > 0 then
			found += 1
			ui.Name.Text = def.Name
			ui.Desc.Text = def.Desc
			ui.Count.Text = "Defeated " .. Widgets.Commas(n) .. "x"
			ui.Swatch.BackgroundColor3 = def.Color
		else
			ui.Name.Text = "???"
			ui.Desc.Text = if def.Secret then "A secret. Very rare." else "Not defeated yet."
			ui.Count.Text = ""
			ui.Swatch.BackgroundColor3 = C.Neutral
		end
	end

	state.Summary.Text = if state.Current == "Collection"
		then string.format("Discovered %d / %d", found, kinds)
		else string.format("Unlocked %d / %d", got, total)
end

function Panel.OnOpen(state, _controllers, arg)
	Panel.Show(state, if arg == "Collection" then "Collection" else "Achievements")
end

return Panel
