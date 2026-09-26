--[[
	PetController - equipped pets follow every player (local rendering from the replicated
	"Pets" attribute). Pets float behind you in a little arc, bob, hop while you walk and
	grow a bit with you so a 500-stud giant still sees them. One BulkMoveTo per frame.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PetBuilder = require(script.Parent.Parent.Util.PetBuilder)

local LocalPlayer = Players.LocalPlayer

local PetController = {}

local MAX_PER_PLAYER = 5

function PetController:Init(controllers)
	self.Controllers = controllers
	self.Owners = {} -- [Player] = { Key = "Doggy,Kitty", Pets = { {Pet, Pos} } }
	self.Folder = Instance.new("Folder")
	self.Folder.Name = "ChilePets"
	self.Folder.Parent = Workspace
	self.Parts = {}
	self.CFrames = {}
end

function PetController:Clear(player: Player)
	local owner = self.Owners[player]
	if owner then
		for _, entry in owner.Pets do
			entry.Pet:Destroy()
		end
		self.Owners[player] = nil
	end
end

function PetController:Sync(player: Player)
	local key = player:GetAttribute("Pets")
	key = if type(key) == "string" then key else ""
	local show = player == LocalPlayer or self.Controllers.ClientData:Setting("OthersFx")
	if not show then
		key = ""
	end
	local owner = self.Owners[player]
	if owner and owner.Key == key then
		return
	end
	self:Clear(player)
	if key == "" then
		return
	end
	owner = { Key = key, Pets = {} }
	for id in string.gmatch(key, "[^,]+") do
		if #owner.Pets >= MAX_PER_PLAYER then
			break
		end
		table.insert(owner.Pets, { Pet = PetBuilder.Build(id, self.Folder), Pos = nil })
	end
	self.Owners[player] = owner
end

function PetController:Step(dt: number)
	local parts, cframes = self.Parts, self.CFrames
	table.clear(parts)
	table.clear(cframes)
	local function push(part: BasePart, cf: CFrame)
		table.insert(parts, part)
		table.insert(cframes, cf)
	end
	local bodies = self.Controllers.BodyController
	local t = os.clock()
	for player, owner in self.Owners do
		local body = bodies:GetBody(player)
		if not body or not body.FeetCF or not body.Shape then
			continue
		end
		local shape = body.Shape
		local size = math.clamp(1.6 + shape.Total * 0.045, 1.6, 18)
		local n = #owner.Pets
		local walking = (body.Walk or 0) > 0.2
		for i, entry in owner.Pets do
			entry.Pet:SetScale(size)
			local angle = (i - (n + 1) / 2) * 0.75
			local distance = shape.Width * 0.9 + size * 1.6 + 1.5
			local hop = if walking then math.abs(math.sin(t * 9 + i)) * size * 0.35 else 0
			local bob = math.sin(t * 2.5 + i * 1.3) * size * 0.12
			local target = (body.FeetCF * CFrame.new(math.sin(angle) * distance, size * 0.75 + hop + bob, math.cos(angle) * distance)).Position
			entry.Pos = if entry.Pos then entry.Pos:Lerp(target, 1 - math.exp(-dt * 10)) else target
			local look = body.FeetCF.LookVector
			entry.Pet:Pose(CFrame.lookAt(entry.Pos, entry.Pos + look), t + i, push)
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function PetController:Start()
	local function watch(player: Player)
		player:GetAttributeChangedSignal("Pets"):Connect(function()
			self:Sync(player)
		end)
		self:Sync(player)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		self:Clear(player)
	end)
	self.Controllers.ClientData.Changed:Connect(function(section)
		if section == "Settings" then
			for _, player in Players:GetPlayers() do
				self:Sync(player)
			end
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		self:Step(math.min(dt, 0.1))
	end)
end

return PetController
