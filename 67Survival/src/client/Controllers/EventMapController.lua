--[[
	EventMapController - brings 67 LAND (the lobby event map, server Map/EventMap) to life
	for this player. Everything here is local: other players see their own map.
	  * every EVENT GATE shows YOUR state (shared/EventMapData.GateState): open (a glowing
	    portal, walk in to play), selected, NEXT (the goal and your progress) or locked (a
	    lock, a dark closed door you cannot walk through, a dimmed frame)
	  * a column of light stands on your NEXT gate (on the selected one once all are open)
	  * NPCs talk when you come close: one short line after another
	  * the TODAY IN 67 LAND board lists today's live events
	  * open portals breathe; particles follow the Fewer Effects setting
	The server decides what a gate does (GameManager:EnterGate); this only draws it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local DifficultyData = require(Shared.DifficultyData)
local EventMapData = require(Shared.EventMapData)

local EventMapController = {}

local rgb = Color3.fromRGB
local CLOSED = rgb(58, 54, 78)
local STATE_COLOR = {
	Selected = rgb(255, 230, 120),
	Open = rgb(236, 232, 250),
	Next = rgb(255, 196, 120),
	Locked = rgb(170, 164, 196),
}

type Gate = {
	Index: number,
	Portal: BasePart?,
	Locks: { BasePart },
	Frames: { { Part: BasePart, Color: Color3 } },
	Label: BillboardGui?,
	State: string?,
}

function EventMapController:Init(controllers)
	self.C = controllers
	self.Gates = {} :: { [number]: Gate }
	self.Npcs = {} :: { { Marker: BasePart, Bubble: BillboardGui?, Def: any, Since: number? } }
	self.Board = nil :: SurfaceGui?
	self.Beacon = nil :: BasePart?
	self.BeaconColor = rgb(255, 214, 120)
	self.Emitters = {} :: { ParticleEmitter }
	self.Found = false
	self.NextTalk = 0
end

local function gateOf(self, index: number): Gate
	local gate = self.Gates[index]
	if not gate then
		gate = { Index = index, Locks = {}, Frames = {} }
		self.Gates[index] = gate
	end
	return gate
end

-- finds the map's live pieces (once the server's lobby has replicated)
function EventMapController:Find(): boolean
	local map = Workspace:FindFirstChild("Map")
	local lobby = map and map:FindFirstChild("Lobby")
	if not lobby then
		return false
	end
	for _, d in lobby:GetDescendants() do
		if d:IsA("BasePart") then
			local g = d:GetAttribute("EventGate")
			if type(g) == "number" then
				gateOf(self, g).Portal = d
			end
			local lock = d:GetAttribute("GateLock")
			if type(lock) == "number" then
				table.insert(gateOf(self, lock).Locks, d)
			end
			local frame = d:GetAttribute("GateFrame")
			if type(frame) == "number" then
				table.insert(gateOf(self, frame).Frames, { Part = d, Color = d.Color })
			end
			local marker = d:GetAttribute("GateMarker")
			if type(marker) == "number" then
				gateOf(self, marker).Label = d:FindFirstChild("GateLabel") :: BillboardGui?
			end
			local npc = d:GetAttribute("NpcKey")
			if type(npc) == "string" and EventMapData.NpcByKey[npc] then
				table.insert(self.Npcs, { Marker = d, Bubble = d:FindFirstChild("Bubble") :: BillboardGui?, Def = EventMapData.NpcByKey[npc] })
			end
			if d:GetAttribute("EventBoard") then
				self.Board = d:FindFirstChild("EventBoardGui") :: SurfaceGui?
			end
			if d:GetAttribute("Beacon") then
				self.Beacon = d
			end
		elseif d:IsA("ParticleEmitter") then
			table.insert(self.Emitters, d)
		end
	end
	self.Found = next(self.Gates) ~= nil
	return self.Found
end

local function setText(gui: Instance?, name: string, text: string, color: Color3?)
	local label = gui and gui:FindFirstChild(name) :: TextLabel?
	if label then
		label.Text = text
		if color then
			label.TextColor3 = color
		end
	end
end

-- one gate, drawn for this player's state
function EventMapController:StyleGate(gate: Gate, difficulty: any)
	local state = EventMapData.GateState(gate.Index, difficulty)
	local tier = DifficultyData.Get(gate.Index)
	gate.State = state
	local open = state == "Selected" or state == "Open"
	local portal = gate.Portal
	if portal then
		portal.Material = if open then Enum.Material.Neon else Enum.Material.SmoothPlastic
		portal.Color = if open then tier.Color elseif state == "Next" then tier.Color:Lerp(CLOSED, 0.62) else CLOSED
		portal.Transparency = if open then 0.35 else 0.12
		-- a closed door is a door (only for you: the server still tells you why)
		portal.CanCollide = not open
		local glow = portal:FindFirstChildOfClass("PointLight")
		if glow then
			glow.Enabled = open or state == "Next"
		end
	end
	for _, lock in gate.Locks do
		lock.Transparency = if open then 1 else 0
	end
	-- a locked gate's frame dims (THE 67's golden frame is the island's landmark: it stays)
	for _, f in gate.Frames do
		f.Part.Color = if state == "Locked" and gate.Index < DifficultyData.Count then f.Color:Lerp(rgb(96, 92, 112), 0.45) else f.Color
	end
	local title, line, detail = EventMapData.GateLines(gate.Index, difficulty)
	setText(gate.Label, "Line1", title, if state == "Locked" then tier.Color:Lerp(rgb(150, 146, 170), 0.5) else tier.Color)
	setText(gate.Label, "Line2", line, STATE_COLOR[state])
	setText(gate.Label, "Line3", detail)
end

function EventMapController:Refresh(data)
	if not data then
		return
	end
	if not self.Found and not self:Find() then
		return
	end
	local difficulty = data.Difficulty
	local target: Gate? = nil
	for _, gate in self.Gates do
		self:StyleGate(gate, difficulty)
	end
	-- the beacon: your NEXT gate, or the selected one when everything is open
	for _, want in { "Next", "Selected" } do
		for _, gate in self.Gates do
			if not target and gate.State == want then
				target = gate
			end
		end
	end
	local beacon = self.Beacon
	if beacon then
		local portal = target and target.Portal
		if target and portal then
			beacon.CFrame = CFrame.new(portal.Position + Vector3.new(0, 38, 0)) * CFrame.Angles(0, 0, math.rad(90))
			self.BeaconColor = DifficultyData.Get(target.Index).Color
			beacon.Color = self.BeaconColor
		else
			beacon.CFrame = CFrame.new(0, -500, 0)
		end
	end
	-- today's live events
	if self.Board then
		local title, sub = EventMapData.BoardText(data.LiveEvents)
		setText(self.Board, "Sub", title .. "\n" .. sub)
	end
	local fewer = self.C.ClientData:Setting("FewerEffects") == true
	for _, e in self.Emitters do
		e.Enabled = not fewer
	end
end

-- NPC speech bubbles: the closest NPCs within range talk, a line every few seconds
function EventMapController:UpdateNpcs(now: number)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local inRun = self.C.RunClient and self.C.RunClient.Active
	for _, npc in self.Npcs do
		local bubble = npc.Bubble
		if bubble then
			local close = root ~= nil and not inRun and (root.Position - npc.Marker.Position).Magnitude < EventMapData.TalkRange
			if close then
				if not npc.Since then
					npc.Since = now
				end
				local lines = npc.Def.Lines
				local i = math.floor((now - npc.Since) / EventMapData.LineTime) % #lines + 1
				setText(bubble, "Line2", lines[i])
			else
				npc.Since = nil
			end
			bubble.Enabled = close
		end
	end
end

function EventMapController:Update(now: number)
	if not self.Found then
		return
	end
	-- open portals breathe, the beacon shimmers
	local breath = math.sin(now * 2.2)
	for _, gate in self.Gates do
		local portal = gate.Portal
		if portal and (gate.State == "Open" or gate.State == "Selected") then
			portal.Transparency = 0.34 + breath * 0.08
		end
	end
	if self.Beacon then
		self.Beacon.Transparency = 0.68 + math.sin(now * 1.4) * 0.08
	end
	if now >= self.NextTalk then
		self.NextTalk = now + 0.2
		self:UpdateNpcs(now)
	end
end

function EventMapController:Start()
	local ClientData = self.C.ClientData
	ClientData.Changed:Connect(function(data)
		self:Refresh(data)
	end)
	task.spawn(function()
		-- the lobby replicates after the client starts: look until it is there
		for _ = 1, 60 do
			if self:Find() then
				break
			end
			task.wait(0.5)
		end
		self:Refresh(ClientData.Data)
	end)
	RunService.Heartbeat:Connect(function()
		self:Update(os.clock())
	end)
end

return EventMapController
