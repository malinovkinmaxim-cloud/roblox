--[[
	PartyPanel - window: play together (never required).
	  your party (up to 4): name, hero, leader; LEAVE (the leader can remove players)
	  invites you got: JOIN
	  players on this server: INVITE (one invite at a time, it expires by itself)
	When anyone in the party presses PLAY, everyone in the lobby starts together and the
	67 events happen for the whole party at once. Bonuses: +10% coins / XP per member,
	+5% per friend on the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local HeroData = require(Shared.HeroData)

local Kit = require(script.Parent.Parent.Kit)
local Theme = require(script.Parent.Parent.Theme)
local Widgets = require(script.Parent.Parent.Widgets)

local C = Theme.Colors
local F = Theme.Fonts

local Panel = {}
Panel.Kind = "Window"
Panel.Title = "PARTY"
Panel.Size = Vector2.new(600, 520)

local function row(parent: Instance, order: number, name: string, sub: string, buttonText: string?, color: Color3?, onClick: (() -> ())?): Frame
	local frame = Kit.Panel({
		Size = UDim2.new(1, -8, 0, 52),
		LayoutOrder = order,
		BackgroundColor3 = C.SurfaceLight,
		BackgroundTransparency = 0.45,
		Radius = 12,
		Parent = parent,
	})
	Kit.Label({
		Name = "Name",
		Text = name,
		Size = UDim2.new(1, -170, 0, 20),
		Position = UDim2.fromOffset(14, 8),
		Font = F.Bold,
		MaxTextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	Kit.Label({
		Name = "Sub",
		Text = sub,
		Size = UDim2.new(1, -170, 0, 16),
		Position = UDim2.fromOffset(14, 29),
		Font = F.Medium,
		MaxTextSize = 13,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	if buttonText and onClick then
		Kit.Button({
			Name = "Action",
			Text = buttonText,
			Size = UDim2.fromOffset(120, 38),
			Position = UDim2.new(1, -8, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Color = color or C.Neutral,
			TextSize = 14,
			OnClick = onClick,
			Parent = frame,
		})
	end
	return frame
end

function Panel.Build(body: Frame, controllers)
	local state = { C = controllers }
	state.Bonus = Kit.Label({
		Name = "Bonus",
		Text = "",
		Size = UDim2.new(1, 0, 0, 36),
		Font = F.Medium,
		MaxTextSize = 14,
		TextWrapped = true,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	local holder = Kit.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -44), Position = UDim2.fromOffset(0, 44), Parent = body })
	state.List = Widgets.Scroll(holder, nil, 8)
	return state
end

local function caption(parent: Instance, order: number, text: string)
	local label = Kit.Label({
		Text = text,
		Size = UDim2.new(1, -8, 0, 20),
		LayoutOrder = order,
		Font = F.Bold,
		MaxTextSize = 13,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
	return label
end

function Panel.Refresh(state, data)
	local party = data.Party
	if not party then
		return
	end
	local C2 = state.C
	local friends = party.Friends or 0
	local members = #party.Members
	state.Bonus.Text = string.format(
		"Party bonus: +%d%% coins and XP  ·  Friends online: %d (+%d%%)  ·  PLAY starts the whole party together.",
		math.min(3, math.max(0, members - 1)) * 10,
		friends,
		math.min(3, friends) * 5
	)
	local list = state.List
	Widgets.Clear(list)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	local inParty = {}
	if party.InParty then
		caption(list, nextOrder(), string.format("YOUR PARTY  %d/%d", members, party.MaxSize))
		for _, m in party.Members do
			inParty[m.UserId] = true
			local hero = HeroData.ByKey[m.Hero]
			local me = m.UserId == Players.LocalPlayer.UserId
			local sub = (if hero then hero.Name else "") .. (if m.Leader then "  ·  LEADER" else "") .. (if m.InRun then "  ·  in a run" else "")
			if me then
				row(list, nextOrder(), m.Name .. " (you)", sub, "LEAVE", C.Neutral, function()
					C2.ClientData:Fire("PartyLeave")
				end)
			elseif party.Leader then
				row(list, nextOrder(), m.Name, sub, "REMOVE", C.Neutral, function()
					C2.ClientData:Fire("PartyKick", m.UserId)
				end)
			else
				row(list, nextOrder(), m.Name, sub)
			end
		end
	end
	if #party.Invites > 0 then
		caption(list, nextOrder(), "INVITES")
		for _, inv in party.Invites do
			row(list, nextOrder(), inv.Name, string.format("invited you  ·  %ds", inv.Left), "JOIN", C.Success, function()
				C2.ClientData:Fire("PartyAccept", inv.UserId)
			end)
		end
	end
	caption(list, nextOrder(), "PLAYERS ON THIS SERVER")
	local any = false
	for _, p in Players:GetPlayers() do
		if p ~= Players.LocalPlayer and not inParty[p.UserId] then
			any = true
			row(list, nextOrder(), p.DisplayName, "@" .. p.Name, "INVITE", C.AccentSoft, function()
				C2.ClientData:Fire("PartyInvite", p.UserId)
			end)
		end
	end
	if not any then
		caption(list, nextOrder(), "Nobody else here yet. Invite a friend to the server!")
	end
end

return Panel
