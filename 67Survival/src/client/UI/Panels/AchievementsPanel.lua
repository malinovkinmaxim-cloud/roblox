--[[
	AchievementsPanel - full screen: every achievement with progress and its reward (coins,
	sometimes fragments) and what it unlocks. Secret ones stay hidden until found.
	(Enemies, bosses and everything else discovered live in the Collection Book.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local AchievementData = require(Shared.AchievementData)

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
	local state = { C = controllers, Rows = {} }

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
	Kit.Label({
		Name = "Hint",
		Text = "Achievements give coins, some give fragments and unlock heroes, abilities and cosmetics.",
		Size = UDim2.new(1, -320, 0, 20),
		Position = UDim2.fromOffset(0, 12),
		Font = F.Medium,
		MaxTextSize = 15,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	local holder = Kit.New("Frame", { Name = "Pages", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -46), Position = UDim2.fromOffset(0, 46), Parent = body })

	local list = Widgets.Scroll(holder, Vector2.new(494, 76), 12)
	list.Name = "Achievements"
	for i, def in AchievementData.List do
		local frame = row(list, i)
		local icon = Kit.New("Frame", { Name = "IconHolder", BackgroundTransparency = 1, Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(14, 14), Parent = frame })
		local name = Kit.Label({
			Name = "Title",
			Text = def.Name,
			Size = UDim2.new(1, -210, 0, 22),
			Position = UDim2.fromOffset(76, 10),
			Font = F.Bold,
			MaxTextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		local desc = Kit.Label({
			Name = "Desc",
			Text = def.Desc,
			Size = UDim2.new(1, -210, 0, 34),
			Position = UDim2.fromOffset(76, 34),
			Font = F.Medium,
			MaxTextSize = 13,
			TextWrapped = true,
			TextColor3 = C.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
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
			Text = "+" .. Widgets.Commas(def.Coins) .. (if def.Fragments then "  +" .. def.Fragments .. "F" else ""),
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

	return state
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
		if def.Unlocks and not hidden then
			ui.Desc.Text ..= "  ·  Unlocks: " .. def.Unlocks
		end
	end

	state.Summary.Text = string.format("Unlocked %d / %d", got, total)
end

return Panel
