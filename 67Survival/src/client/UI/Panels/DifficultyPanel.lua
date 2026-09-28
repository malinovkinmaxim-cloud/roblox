--[[
	DifficultyPanel - DIFFICULTY (full screen): HERO -> DIFFICULTY -> PLAY.

	  left    the ladder: I CALM ... VII THE 67. Each row: numeral + name in the tier's colour,
	          SELECTED / LOCKED / CLEARED. Clicking an open tier selects it; a locked one
	          shows what opens it.
	  right   the focused tier: description, its RULES (new ones marked NEW), what the enemies
	          and bosses get, the rewards (multiplier, fragments, luck, first clear bonus), the
	          recommended account level, the unlock goal + progress, SELECT and PLAY.

	Colour identity per tier is kept small (the numeral, a side bar and a faint top tint):
	calm tiers are cool and quiet, high tiers warm and tense, never a rainbow.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local DifficultyData = require(Shared.DifficultyData)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Screen"
Panel.Title = "DIFFICULTY"

local LADDER_W = 290
local ROW_H = 50

local function x(n: number): string
	return "x" .. string.format("%g", n)
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	props.Parent = parent
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return Kit.Label(props)
end

function Panel.Build(body: Frame, controllers)
	local state = { C = controllers, Rows = {}, Focus = nil :: number? }

	-- the ladder
	local ladder = Kit.New("ScrollingFrame", {
		Name = "Ladder",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, LADDER_W, 1, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = body,
	})
	Kit.New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = ladder })
	Kit.New("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 2), Parent = ladder })
	for i, tier in DifficultyData.List do
		local row = Widgets.Card(ladder, UDim2.new(1, -4, 0, ROW_H), i, "Tier" .. i)
		row.BackgroundColor3 = C.Surface
		row.BackgroundTransparency = Theme.Glass
		local bar = Kit.New("Frame", {
			Name = "Bar",
			Size = UDim2.new(0, 5, 1, -18),
			Position = UDim2.new(0, 9, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = tier.Color,
			Parent = row,
		})
		Kit.Corner(bar, 3)
		local numeral = label(row, {
			Name = "Numeral",
			Text = tier.Numeral,
			Size = UDim2.fromOffset(46, 24),
			Position = UDim2.new(0, 22, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Font = F.Title,
			MaxTextSize = 20,
			TextColor3 = tier.Color,
		})
		local name = label(row, {
			Name = "Name",
			Text = tier.Name,
			Size = UDim2.new(1, -176, 0, 22),
			Position = UDim2.new(0, 70, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Font = F.Bold,
			MaxTextSize = 17,
		})
		local status = label(row, {
			Name = "Status",
			Text = "",
			Size = UDim2.fromOffset(96, 16),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Font = F.Bold,
			MaxTextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = C.TextMuted,
		})
		local stroke = row:FindFirstChildOfClass("UIStroke")
		row.Activated:Connect(function()
			if Kit.ClickSound then
				Kit.ClickSound()
			end
			Panel.ClickTier(state, i)
		end)
		state.Rows[i] = { Row = row, Bar = bar, Numeral = numeral, Name = name, Status = status, Stroke = stroke }
	end

	-- the detail of the focused tier
	local detail = Kit.Panel({
		Name = "Detail",
		Size = UDim2.new(1, -(LADDER_W + 16), 1, 0),
		Position = UDim2.fromOffset(LADDER_W + 16, 0),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = Theme.GlassStrong,
		Radius = 20,
		ClipsDescendants = true,
		Parent = body,
	})
	-- a faint wash of the tier colour at the top
	local wash = Kit.New("Frame", {
		Name = "Wash",
		Size = UDim2.new(1, 0, 0, 150),
		BackgroundColor3 = Color3.new(1, 1, 1), -- the gradient colours it (UIGradient multiplies)
		BackgroundTransparency = 0.84,
		BorderSizePixel = 0,
		Parent = detail,
	})
	state.WashGradient = Kit.New("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Parent = wash,
	})
	state.Wash = wash
	local inner = Kit.New("Frame", { Name = "Inner", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = detail })
	Kit.Padding(inner, 24, 18)
	state.BigNumeral = label(inner, { Name = "BigNumeral", Text = "", Size = UDim2.fromOffset(84, 48), Font = F.Title, MaxTextSize = 44 })
	state.Name = label(inner, { Name = "TierName", Text = "", Size = UDim2.new(1, -200, 0, 38), Position = UDim2.fromOffset(92, 4), Font = F.Title, MaxTextSize = 34 })
	state.Desc = label(inner, { Name = "Desc", Text = "", Size = UDim2.new(1, -110, 0, 20), Position = UDim2.fromOffset(92, 44), Font = F.Medium, MaxTextSize = 16, TextColor3 = C.TextDim })
	state.Cleared = Widgets.Tag(inner, "CLEARED", C.Gold, UDim2.new(1, 0, 0, 8), UDim2.fromOffset(92, 24))
	state.Cleared.AnchorPoint = Vector2.new(1, 0)

	-- two columns: rules | numbers
	local cols = Kit.New("Frame", { Name = "Columns", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -150), Position = UDim2.fromOffset(0, 78), Parent = inner })
	local left = Kit.New("Frame", { Name = "Rules", BackgroundTransparency = 1, Size = UDim2.new(0.5, -10, 1, 0), Parent = cols })
	local right = Kit.New("Frame", { Name = "Numbers", BackgroundTransparency = 1, Size = UDim2.new(0.5, -10, 1, 0), Position = UDim2.fromScale(0.5, 0), Parent = cols })
	right.Position = UDim2.new(0.5, 10, 0, 0)
	Widgets.Caption(left, "RULES", UDim2.fromOffset(0, 0))
	state.RuleList = Kit.New("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -22),
		Position = UDim2.fromOffset(0, 22),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = left,
	})
	Kit.New("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = state.RuleList })

	Widgets.Caption(right, "ENEMIES", UDim2.fromOffset(0, 0))
	state.Enemies = label(right, { Name = "EnemyStats", Text = "", Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 20), Font = F.Medium, MaxTextSize = 14, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	Widgets.Caption(right, "BOSSES", UDim2.fromOffset(0, 66))
	state.Bosses = label(right, { Name = "BossStats", Text = "", Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 86), Font = F.Medium, MaxTextSize = 14 })
	Widgets.Caption(right, "REWARDS", UDim2.fromOffset(0, 116))
	state.Rewards = label(right, { Name = "RewardText", Text = "", Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 136), Font = F.Bold, MaxTextSize = 15, TextWrapped = true, TextColor3 = C.Gold, TextYAlignment = Enum.TextYAlignment.Top })
	state.FirstClear = label(right, { Name = "FirstClear", Text = "", Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 180), Font = F.Medium, MaxTextSize = 13, TextColor3 = C.TextDim })

	-- footer: recommended level + unlock goal, SELECT, PLAY
	local footer = Kit.New("Frame", { Name = "Footer", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1), Parent = inner })
	state.Recommended = label(footer, { Name = "Recommended", Text = "", Size = UDim2.new(1, -330, 0, 18), Position = UDim2.fromOffset(0, 6), Font = F.Bold, MaxTextSize = 14, TextColor3 = C.TextDim })
	state.Goal = label(footer, { Name = "Goal", Text = "", Size = UDim2.new(1, -330, 0, 18), Position = UDim2.fromOffset(0, 30), Font = F.Medium, MaxTextSize = 13, TextColor3 = C.TextMuted })
	state.Select, state.SelectLabel = Kit.Button({
		Name = "Select",
		Text = "SELECT",
		Size = UDim2.fromOffset(140, 50),
		Position = UDim2.new(1, -170, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.Neutral,
		TextSize = 17,
		OnClick = function()
			local i = state.Focus
			if i then
				controllers.ClientData:Fire("SelectDifficulty", i)
			end
		end,
		Parent = footer,
	})
	state.Play, state.PlayLabel = Kit.Button({
		Name = "Play",
		Text = "PLAY",
		Size = UDim2.fromOffset(160, 54),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.Accent,
		Dark = C.AccentDark,
		Radius = 18,
		TextSize = 22,
		Font = F.Title,
		OnClick = function()
			Panel.PlayFocused(state)
		end,
		Parent = footer,
	})
	return state
end

function Panel.ClickTier(state, index: number)
	state.Focus = index
	local data = state.C.ClientData.Data
	if data and data.Difficulty and index <= data.Difficulty.Unlocked and index ~= data.Difficulty.Selected then
		state.C.ClientData:Fire("SelectDifficulty", index)
	end
	if data then
		Panel.Refresh(state, data)
	end
end

function Panel.PlayFocused(state)
	local data = state.C.ClientData.Data
	local diff = data and data.Difficulty
	local i = state.Focus
	if not diff or not i or i > diff.Unlocked then
		return
	end
	if i ~= diff.Selected then
		state.C.ClientData:Fire("SelectDifficulty", i)
	end
	state.C.LobbyController:Play()
end

local function rule(parent: Instance, order: number, mod, isNew: boolean, color: Color3)
	local row = Kit.New("Frame", { Name = mod.Key, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = order, Parent = parent })
	label(row, { Name = "RuleName", Text = mod.Name, Size = UDim2.new(1, -60, 0, 17), Font = F.Bold, MaxTextSize = 14, TextColor3 = if isNew then color else C.Text })
	if isNew then
		local tag = Widgets.Tag(row, "NEW", color, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(48, 18))
		tag.AnchorPoint = Vector2.new(1, 0)
	end
	label(row, { Name = "RuleDesc", Text = mod.Desc, Size = UDim2.new(1, 0, 0, 15), Position = UDim2.fromOffset(0, 18), Font = F.Medium, MaxTextSize = 12, TextColor3 = C.TextDim })
end

function Panel.Refresh(state, data)
	local diff = data.Difficulty
	if not diff then
		return
	end
	state.Focus = state.Focus or diff.Selected
	local level = data.Level or 1
	-- ladder
	for i, ui in state.Rows do
		local tier = DifficultyData.Get(i)
		local open = i <= diff.Unlocked
		local selected = i == diff.Selected
		local cleared = diff.Cleared and diff.Cleared[i]
		ui.Numeral.TextColor3 = if open then tier.Color else C.TextMuted
		ui.Name.TextColor3 = if open then C.Text else C.TextMuted
		ui.Bar.BackgroundColor3 = if open then tier.Color else C.Neutral
		ui.Status.Text = if selected then "SELECTED" elseif not open then "LOCKED" elseif cleared then "CLEARED" else ""
		ui.Status.TextColor3 = if selected then C.Accent elseif cleared then C.Gold else C.TextMuted
		ui.Row.BackgroundColor3 = if i == state.Focus then C.SurfaceLight else C.Surface
		if ui.Stroke then
			ui.Stroke.Color = if i == state.Focus then tier.Color else C.Border
			ui.Stroke.Transparency = if i == state.Focus then 0.2 else Theme.BorderTransparency
		end
	end

	-- detail
	local i = state.Focus
	local tier = DifficultyData.Get(i)
	local open = i <= diff.Unlocked
	state.WashGradient.Color = ColorSequence.new(tier.Color)
	state.BigNumeral.Text = tier.Numeral
	state.BigNumeral.TextColor3 = tier.Color
	state.Name.Text = tier.Name
	state.Desc.Text = tier.Desc
	state.Cleared.Visible = diff.Cleared ~= nil and diff.Cleared[i] == true

	Widgets.Clear(state.RuleList)
	local fresh = {}
	for _, key in DifficultyData.NewMods(i) do
		fresh[key] = true
	end
	if #tier.Mods == 0 then
		label(state.RuleList, { Name = "None", Text = if i == 1 then "No special rules. A gentler horde." else "No special rules. The classic horde.", Size = UDim2.new(1, 0, 0, 18), Font = F.Medium, MaxTextSize = 14, TextColor3 = C.TextDim })
	else
		for order, key in tier.Mods do
			rule(state.RuleList, order, DifficultyData.Modifiers[key], fresh[key] == true, tier.Color)
		end
	end

	state.Enemies.Text = string.format("Health %s  ·  Damage %s  ·  Speed %s\nHorde %s  ·  Elites %s", x(tier.EnemyHP), x(tier.EnemyDamage), x(tier.EnemySpeed), x(tier.Spawn), x(tier.Elite))
	state.Bosses.Text = string.format("Health %s  ·  Damage %s", x(tier.BossHP), x(tier.BossDamage))
	local parts = { "Coins & XP " .. x(tier.Reward) }
	if tier.Fragments > 0 then
		local noun = if tier.Fragments == 1 then "fragment" else "fragments"
		table.insert(parts, string.format("+%d %s per run (+%d on a win)", tier.Fragments, noun, tier.Fragments))
	end
	if tier.Luck > 0 then
		table.insert(parts, string.format("+%d%% luck", math.floor(tier.Luck * 100 + 0.5)))
	end
	state.Rewards.Text = table.concat(parts, "  ·  ")
	local claimed = diff.Cleared and diff.Cleared[i]
	state.FirstClear.Text = string.format("First win: +%s coins, +%d fragments%s", Widgets.Commas(tier.FirstClear.Coins), tier.FirstClear.Fragments, if claimed then "  (claimed)" else "")

	state.Recommended.Text = string.format("Recommended: account level %d  (you: %d)", tier.Recommended, level)
	state.Recommended.TextColor3 = if level >= tier.Recommended then C.TextDim else C.Gold
	if open then
		state.Goal.Text = if tier.Unlock then "Opened: " .. tier.Unlock.Text else "Open from the start"
	else
		state.Goal.Text = string.format("To open: %s  (%s)", tier.Unlock and tier.Unlock.Text or "", DifficultyData.GoalProgress(tier, diff.Best))
	end
	state.Goal.TextColor3 = if open then C.TextMuted else C.Text

	local selected = i == diff.Selected
	state.Select.Visible = open
	state.SelectLabel.Text = if selected then "SELECTED" else "SELECT"
	Kit.SetButtonColor(state.Select, if selected then C.SuccessDark else C.Neutral)
	state.PlayLabel.Text = if open then "PLAY" else "LOCKED"
	Kit.SetButtonColor(state.Play, if open then C.Accent else C.Neutral, if open then C.AccentDark else nil)
end

function Panel.OnOpen(state)
	-- open on the selected tier
	local data = state.C.ClientData.Data
	state.Focus = data and data.Difficulty and data.Difficulty.Selected or 1
	if data then
		Panel.Refresh(state, data)
	end
end

return Panel
