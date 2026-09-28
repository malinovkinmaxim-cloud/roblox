--[[
	AfkCampPanel - window: the AFK CAMP.
	  slots   heroes resting at the camp (1 free, more for coins, +1 with a pass); tap a slot
	          to choose who rests there
	  camp    what the camp holds right now (coins / XP / fragments), how full it is (the cap)
	  CLAIM AFK REWARDS
	A reminder that playing gives much more is always visible: the camp is a bonus.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local HeroData = require(Shared.HeroData)
local GameConfig = require(Shared.GameConfig)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)
local Previews = require(script.Parent.Parent.Previews)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Window"
Panel.Title = "AFK CAMP"
Panel.Size = Vector2.new(640, 540)

local SLOT = Vector2.new(136, 170)
local MAX_SLOTS = #GameConfig.Afk.SlotCosts + 1

function Panel.Build(body: Frame, controllers)
	local state = { C = controllers, Slots = {}, Picking = nil }
	Kit.Label({
		Text = "Heroes you are not playing rest here and collect a little while you are away. Playing gives much more!",
		Size = UDim2.new(1, 0, 0, 36),
		Font = F.Medium,
		MaxTextSize = 14,
		TextWrapped = true,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	local row = Kit.New("Frame", { Name = "Slots", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, SLOT.Y), Position = UDim2.fromOffset(0, 46), Parent = body })
	Kit.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	for i = 1, MAX_SLOTS do
		local card = Widgets.Card(row, UDim2.fromOffset(SLOT.X, SLOT.Y), i, "Slot" .. i)
		card.BackgroundColor3 = C.SurfaceLight
		card.BackgroundTransparency = 0.4
		local holder = Kit.New("Frame", { Name = "Hero", BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 110), Position = UDim2.fromOffset(6, 6), Parent = card })
		local label = Kit.Label({
			Name = "Label",
			Text = "",
			Size = UDim2.new(1, -12, 0, 18),
			Position = UDim2.new(0, 6, 1, -44),
			Font = F.Bold,
			MaxTextSize = 14,
			Parent = card,
		})
		local sub = Kit.Label({
			Name = "Sub",
			Text = "",
			Size = UDim2.new(1, -12, 0, 16),
			Position = UDim2.new(0, 6, 1, -24),
			Font = F.Medium,
			MaxTextSize = 12,
			TextColor3 = C.TextMuted,
			Parent = card,
		})
		card.Activated:Connect(function()
			if Kit.ClickSound then
				Kit.ClickSound()
			end
			Panel.ClickSlot(state, i)
		end)
		state.Slots[i] = { Card = card, Holder = holder, Label = label, Sub = sub, Key = nil }
	end

	-- hero picker (shown after tapping an open slot)
	local picker = Kit.Panel({
		Name = "Picker",
		Size = UDim2.new(1, 0, 0, 132),
		Position = UDim2.fromOffset(0, 226),
		BackgroundTransparency = Theme.GlassStrong,
		Radius = 14,
		Visible = false,
		ZIndex = 5,
		Parent = body,
	})
	local list = Kit.New("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -16, 1, -16),
		Position = UDim2.fromOffset(8, 8),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 4,
		Parent = picker,
	})
	Kit.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	state.Picker = picker
	state.PickerList = list

	-- what the camp holds
	local camp = Kit.Panel({
		Name = "Camp",
		Size = UDim2.new(1, 0, 0, 132),
		Position = UDim2.fromOffset(0, 226),
		BackgroundColor3 = C.SurfaceLight,
		BackgroundTransparency = 0.45,
		Radius = 14,
		Parent = body,
	})
	Widgets.Caption(camp, "READY TO CLAIM", UDim2.fromOffset(16, 12))
	state.Rewards = Kit.Label({
		Name = "Rewards",
		Text = "",
		Size = UDim2.new(1, -32, 0, 24),
		Position = UDim2.fromOffset(16, 34),
		Font = F.Title,
		MaxTextSize = 20,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = camp,
	})
	state.Fill = Widgets.Bar(camp, UDim2.new(1, -32, 0, 20), UDim2.fromOffset(16, 66), C.Gold)
	state.Info = Kit.Label({
		Name = "Info",
		Text = "",
		Size = UDim2.new(1, -32, 0, 18),
		Position = UDim2.fromOffset(16, 96),
		Font = F.Medium,
		MaxTextSize = 13,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = camp,
	})
	state.Camp = camp

	state.Claim, state.ClaimLabel = Kit.Button({
		Name = "ClaimAfk",
		Text = "CLAIM AFK REWARDS",
		Size = UDim2.fromOffset(300, 48),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = C.Success,
		TextSize = 17,
		OnClick = function()
			controllers.ClientData:Fire("AfkClaim")
		end,
		Parent = body,
	})
	return state
end

function Panel.ClickSlot(state, index: number)
	local data = state.C.ClientData.Data
	if not data or not data.Afk then
		return
	end
	local afk = data.Afk
	if index > afk.MaxSlots then
		-- a locked slot: buy it with coins, or the pass for the last one
		if afk.NextSlotCost and index == afk.MaxSlots + 1 then
			state.C.ClientData:Fire("AfkBuySlot")
		else
			state.C.ClientData:Fire("Buy", "Pass", "ExtraHeroSlot")
		end
		return
	end
	state.Picking = index
	Panel.ShowPicker(state, data)
end

function Panel.ShowPicker(state, data)
	Widgets.Clear(state.PickerList)
	local used = {}
	for _, key in data.Afk.Slots do
		used[key] = true
	end
	local order = 0
	local function option(key: string, name: string)
		order += 1
		local card = Widgets.Card(state.PickerList, UDim2.fromOffset(96, 112), order, key ~= "" and key or "Empty")
		card.BackgroundColor3 = C.SurfaceLight
		card.BackgroundTransparency = 0.3
		if key ~= "" then
			local holder = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 84), Parent = card })
			Previews.Hero(holder, key)
		end
		Kit.Label({
			Text = name,
			Size = UDim2.new(1, -8, 0, 16),
			Position = UDim2.new(0, 4, 1, -20),
			Font = F.Bold,
			MaxTextSize = 11,
			Parent = card,
		})
		card.Activated:Connect(function()
			state.C.ClientData:Fire("AfkSetSlot", state.Picking, key)
			state.Picking = nil
			state.Picker.Visible = false
			state.Camp.Visible = true
		end)
	end
	option("", "EMPTY")
	for _, def in HeroData.List do
		if data.Heroes[def.Key] and not used[def.Key] then
			option(def.Key, def.Name)
		end
	end
	state.Picker.Visible = true
	state.Camp.Visible = false
end

local function minutesText(m: number): string
	if m >= 60 then
		return string.format("%dh %02dm", m // 60, m % 60)
	end
	return string.format("%dm", m)
end

function Panel.Refresh(state, data)
	local afk = data.Afk
	if not afk then
		return
	end
	for i, ui in state.Slots do
		local key = if i <= afk.MaxSlots then afk.Slots[i] else nil
		local mark = if i > afk.MaxSlots then "locked" else (key or "")
		if ui.Key ~= mark then
			ui.Key = mark
			Widgets.Clear(ui.Holder)
			if key and key ~= "" then
				Previews.Hero(ui.Holder, key)
			elseif i > afk.MaxSlots then
				Widgets.Lock(ui.Holder, 40, C.TextMuted, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
			else
				Widgets.Mono(ui.Holder, "+", C.TextDim, 60, { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
			end
		end
		if i > afk.MaxSlots then
			ui.Label.Text = "LOCKED"
			ui.Sub.Text = if afk.NextSlotCost and i == afk.MaxSlots + 1 then Widgets.Commas(afk.NextSlotCost) .. " coins" else "Gamepass"
		elseif key and key ~= "" then
			local def = HeroData.ByKey[key]
			ui.Label.Text = if def then def.Name else key
			ui.Sub.Text = "resting"
		else
			ui.Label.Text = "EMPTY"
			ui.Sub.Text = "tap to add a hero"
		end
	end
	state.Rewards.Text = string.format("%s coins   %s XP   %d fragments", Widgets.Commas(afk.Coins), Widgets.Commas(afk.XP), afk.Fragments)
	state.Fill:Set(afk.Minutes / math.max(1, afk.CapMinutes), string.format("%s / %s", minutesText(afk.Minutes), minutesText(afk.CapMinutes)))
	local info = if afk.Heroes == 0 then "Add a hero to start the camp." elseif afk.Full then "The camp is full: claim to keep collecting." else "Keeps collecting while you are offline."
	if (afk.BoostLeft or 0) > 0 then
		info ..= string.format("  AFK BOOST x2: %dm left", math.ceil(afk.BoostLeft / 60))
	end
	state.Info.Text = info
	local ready = afk.Coins + afk.XP + afk.Fragments > 0
	Kit.SetButtonColor(state.Claim, if ready then C.Success else C.Neutral)
end

function Panel.OnOpen(state)
	state.Picking = nil
	state.Picker.Visible = false
	state.Camp.Visible = true
end

return Panel
