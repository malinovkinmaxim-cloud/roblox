--[[
	ArenaController - brings 67 TOWN (the battle map, server Map/BattleMap) to life for THIS
	player's run. Every player fights their own run on the same map, so everything here is
	local (like the gates of 67 LAND):
	  * THE RIFT gates: a force field you can't walk through until your rift opens (4:30);
	    their label says when
	  * a lair lights up (red ring + a column of light) while its boss is out for you
	  * a 67 VAULT glows gold while it is awake; its ring fills while you crack it open
	  * a 67 SPOT lights up when a boss waits on one
	  * THE 67 ARENA: its pylons burn red while THE FINAL ONE is out; the SEAL (a ring wall of
	    force field) becomes visible and solid for you while your arena is sealed
	The server decides all of it (Sim/ArenaDirector); this only draws what RunClient knows.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Modules")
local ArenaData = require(Shared.ArenaData)

local ArenaController = {}

local rgb = Color3.fromRGB
local RED = rgb(255, 70, 60)
local GOLD = rgb(255, 205, 60)

type Remember = { Part: BasePart, Color: Color3, Material: Enum.Material, Transparency: number }

local function remember(p: BasePart): Remember
	return { Part = p, Color = p.Color, Material = p.Material, Transparency = p.Transparency }
end

local function restore(r: Remember)
	r.Part.Color = r.Color
	r.Part.Material = r.Material
	r.Part.Transparency = r.Transparency
end

function ArenaController:Init(controllers)
	self.C = controllers
	self.Found = false
	self.Seals = {} :: { Remember }
	self.Lairs = {} :: { [string]: { Ring: Remember?, Beam: BasePart? } }
	self.Vaults = {} :: { [number]: { Ring: Remember?, Beam: BasePart?, Safe: Remember? } }
	self.Spots = {} :: { [number]: Remember }
	self.ArenaSeals = {} :: { BasePart }
	self.Pylons = {} :: { Remember }
	self.Sealed = nil :: any
	self.Lit = {} -- lair key / "vault:i" / "spot:i" / "arena" -> true while lit
end

-- THE FINAL ONE's arena was sealed (seal = { X, Z, R }) or opened again (nil)
function ArenaController:SetSeal(seal)
	self.Sealed = seal
	self:Refresh()
end

function ArenaController:Find(): boolean
	local map = Workspace:FindFirstChild("Map")
	local arena = map and map:FindFirstChild("Arena")
	if not arena then
		return false
	end
	for _, d in arena:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("RiftSeal") then
				table.insert(self.Seals, remember(d))
			end
			local lairRing = d:GetAttribute("LairRing")
			if type(lairRing) == "string" then
				self.Lairs[lairRing] = self.Lairs[lairRing] or {}
				self.Lairs[lairRing].Ring = remember(d)
			end
			local lairBeam = d:GetAttribute("LairBeam")
			if type(lairBeam) == "string" then
				self.Lairs[lairBeam] = self.Lairs[lairBeam] or {}
				self.Lairs[lairBeam].Beam = d
			end
			for _, key in { "VaultRing", "VaultBeam", "VaultSafe" } do
				local index = d:GetAttribute(key)
				if type(index) == "number" then
					self.Vaults[index] = self.Vaults[index] or {}
					local slot = string.sub(key, 6)
					if slot == "Beam" then
						self.Vaults[index].Beam = d
					else
						(self.Vaults[index] :: any)[slot] = remember(d)
					end
				end
			end
			local spot = d:GetAttribute("Spot67")
			if type(spot) == "number" then
				self.Spots[spot] = remember(d)
			end
			if d:GetAttribute("ArenaSeal") then
				table.insert(self.ArenaSeals, d)
			end
			if d:GetAttribute("ArenaPylon") then
				table.insert(self.Pylons, remember(d))
			end
		end
	end
	self.Found = #self.Seals > 0
	return self.Found
end

local function setLabel(seal: BasePart, open: boolean)
	local gui = seal:FindFirstChild("RiftLabel") :: BillboardGui?
	if gui then
		gui.Enabled = not open
		local line2 = gui:FindFirstChild("Line2") :: TextLabel?
		if line2 then
			line2.Text = string.format("OPENS AT %d:%02d", math.floor(ArenaData.RiftOpensAt / 60), ArenaData.RiftOpensAt % 60)
		end
	end
end

-- applies the run's state to the map (called on every state change)
function ArenaController:Refresh()
	if not self.Found and not self:Find() then
		return
	end
	local run = self.C.RunClient
	local active = run.Active
	-- the rift: sealed for you until it opens in your run (and outside runs)
	local open = active and run.Map.Rift == true
	for _, s in self.Seals do
		s.Part.CanCollide = not open
		s.Part.Transparency = if open then 1 else s.Transparency
		setLabel(s.Part, open)
	end
	-- lairs with a mini-boss out
	local busy = {}
	local spotsLit = {}
	for _, enc in run.Encounters do
		local zone = ArenaData.ZoneAt(enc.X, enc.Z)
		local lair = ArenaData.LairOfZone[zone.Key]
		if lair and (lair.X - enc.X) ^ 2 + (lair.Z - enc.Z) ^ 2 < 4 then
			busy[lair.Key] = true
		else
			for i, s in ArenaData.Spots do
				if (s[1] - enc.X) ^ 2 + (s[2] - enc.Z) ^ 2 < 4 then
					spotsLit[i] = true
				end
			end
		end
	end
	for key, l in self.Lairs do
		local lit = active and busy[key] == true
		self.Lit[key] = lit or nil
		if l.Ring then
			if lit then
				l.Ring.Part.Color = RED
				l.Ring.Part.Material = Enum.Material.Neon
			else
				restore(l.Ring)
			end
		end
		if l.Beam then
			l.Beam.Transparency = if lit then 0.7 else 1
			l.Beam.Color = RED
		end
	end
	for i, v in self.Vaults do
		local state = run.Map.Vaults[i]
		local awake = active and state ~= nil and state.State == 1
		self.Lit["vault:" .. i] = awake or nil
		if v.Ring then
			if awake then
				v.Ring.Part.Material = Enum.Material.Neon
				v.Ring.Part.Color = GOLD:Lerp(rgb(255, 255, 255), (state.Pct or 0) / 100 * 0.7)
			else
				restore(v.Ring)
			end
		end
		if v.Safe then
			if awake then
				v.Safe.Part.Color = GOLD
				v.Safe.Part.Material = Enum.Material.Neon
			else
				restore(v.Safe)
			end
		end
		if v.Beam then
			v.Beam.Transparency = if awake then 0.72 else 1
		end
	end
	for i, s in self.Spots do
		local lit = active and spotsLit[i] == true
		if lit then
			s.Part.Color = RED
			s.Part.Material = Enum.Material.Neon
			s.Part.Transparency = 0.3
		else
			restore(s)
		end
	end
	-- THE 67 ARENA
	local mainOut = false
	for _, enc in run.Encounters do
		mainOut = mainOut or enc.Main == true
	end
	mainOut = active and mainOut
	for _, p in self.Pylons do
		if mainOut then
			p.Part.Color = RED
			p.Part.Material = Enum.Material.Neon
		else
			restore(p)
		end
	end
	local sealed = active and self.Sealed ~= nil
	for _, wall in self.ArenaSeals do
		wall.CanCollide = sealed
		wall.Transparency = if sealed then 0.35 else 1
	end
	self.Lit.arena = (mainOut or sealed) or nil
end

-- lit things pulse; a column of light is for finding the place from afar: it fades out as you
-- get close (it would stand between the camera and the fight)
local NEAR, FAR = 45, 90

local function beamAlpha(beam: BasePart, x: number?, z: number?, base: number): number
	if not x or not z then
		return base
	end
	local center = beam.Position
	local d = math.sqrt((center.X - x) ^ 2 + (center.Z - z) ^ 2)
	local k = math.clamp((d - NEAR) / (FAR - NEAR), 0, 1)
	return 1 - (1 - base) * k
end

function ArenaController:Update()
	if not next(self.Lit) then
		return
	end
	local t = os.clock()
	local run = self.C.RunClient
	local px, pz = run:LocalXZ()
	if px and pz then
		px += run.Center.X
		pz += run.Center.Z
	end
	if self.Lit.arena and self.Sealed then
		local a = 0.3 + math.sin(t * 5) * 0.08
		for _, wall in self.ArenaSeals do
			wall.Transparency = a
		end
	end
	for key in self.Lit do
		local l = self.Lairs[key]
		if l and l.Beam then
			l.Beam.Transparency = beamAlpha(l.Beam, px, pz, 0.66 + math.sin(t * 4) * 0.08)
		end
		local index = tonumber(string.match(key, "^vault:(%d+)$"))
		local v = index and self.Vaults[index]
		if v and v.Beam then
			v.Beam.Transparency = beamAlpha(v.Beam, px, pz, 0.7 + math.sin(t * 3) * 0.08)
		end
	end
end

function ArenaController:Start()
	task.spawn(function()
		for _ = 1, 60 do
			if self:Find() then
				break
			end
			task.wait(0.5)
		end
		self:Refresh()
	end)
	self.C.RunClient.Started:Connect(function()
		self:Refresh()
	end)
	self.C.RunClient.Ended:Connect(function()
		self:Refresh()
	end)
	RunService.Heartbeat:Connect(function()
		self:Update()
	end)
end

return ArenaController
