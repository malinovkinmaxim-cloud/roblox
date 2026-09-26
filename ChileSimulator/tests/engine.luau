--!nocheck
--[[
	A tiny offline "Roblox engine" for end-to-end tests (runs with Lune).

	It runs the REAL server and client code of the game:
	  * instances are real Lune/rbx-dom instances, so class names, property names and property
	    types are validated exactly like in Roblox; a thin proxy adds what Lune lacks
	    (events, WaitForChild, attribute signals, Destroy semantics, PivotTo, BulkMoveTo...)
	  * a cooperative scheduler implements task.spawn / defer / delay / wait with virtual time
	  * services are stubbed: RunService, Players, UserInputService, ContextActionService,
	    TweenService, DataStoreService (JSON round-trip, like the real one), MarketplaceService...
	  * one server world + one client world per player; RemoteEvents are bridged with Roblox's
	    serialization rules (sparse / mixed tables are rejected), player and Workspace attributes
	    replicate server -> clients, the built map is copied to clients
	Every runtime error in any script thread is collected in Engine.Errors.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local RealInstance = roblox.Instance
local Enum = roblox.Enum
local Vector2, Vector3, CFrame, Color3 = roblox.Vector2, roblox.Vector3, roblox.CFrame, roblox.Color3

local Engine = {}
Engine.Now = 0
Engine.BaseTime = 1_780_000_000
Engine.Errors = {}
Engine.Warnings = {}
Engine.Verbose = false
Engine.Studio = true
Engine.SoundPlays = {}
Engine.Kicks = {}
Engine.Prompts = {}
Engine.DataStores = {} -- name -> { [key] = json }
Engine.OrderedStores = {} -- name -> { [key] = number }
Engine.DataStoreDown = false
Engine.OwnedPasses = {}

---------------------------------------------------------------------------
-- scheduler
---------------------------------------------------------------------------
local queue = {}
local seq = 0

local function report(co, err)
	local trace = debug.traceback(co, tostring(err))
	table.insert(Engine.Errors, trace)
	print("\n[ENGINE ERROR] " .. trace)
end

local function resume(co, ...)
	if coroutine.status(co) ~= "suspended" then
		return
	end
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		report(co, err)
	end
end
Engine.Resume = resume

local function schedule(t, co, args)
	seq += 1
	table.insert(queue, { T = t, Co = co, Args = args, Seq = seq })
end

local task = {}
function task.spawn(f, ...)
	local co = if type(f) == "thread" then f else coroutine.create(f)
	resume(co, ...)
	return co
end
function task.defer(f, ...)
	local co = if type(f) == "thread" then f else coroutine.create(f)
	schedule(Engine.Now, co, table.pack(...))
	return co
end
function task.delay(t, f, ...)
	local co = if type(f) == "thread" then f else coroutine.create(f)
	schedule(Engine.Now + (t or 0), co, table.pack(...))
	return co
end
function task.wait(t)
	local co = coroutine.running()
	local started = Engine.Now
	schedule(Engine.Now + math.max(t or 0, 0), co, { n = 0, Waiting = true })
	coroutine.yield()
	return Engine.Now - started
end
function task.cancel(co)
	for _, item in queue do
		if item.Co == co then
			item.Cancelled = true
		end
	end
end
Engine.task = task
Engine.Queue = queue

function Engine.RunDue()
	local guard = 0
	while true do
		local best
		for i, item in queue do
			if item.T <= Engine.Now + 1e-9 then
				local b = best and queue[best]
				if not b or item.T < b.T or (item.T == b.T and item.Seq < b.Seq) then
					best = i
				end
			end
		end
		if not best then
			return
		end
		local item = table.remove(queue, best)
		if not item.Cancelled then
			if item.Args.Waiting then
				resume(item.Co, Engine.Now)
			else
				resume(item.Co, table.unpack(item.Args, 1, item.Args.n))
			end
		end
		guard += 1
		if guard > 500000 then
			error("scheduler runaway (infinite task loop?)")
		end
	end
end

---------------------------------------------------------------------------
-- signals
---------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
function Signal.new(name)
	return setmetatable({ Conns = {}, Waiting = {}, Name = name }, Signal)
end
function Signal:Connect(fn)
	assert(type(fn) == "function", "Connect expects a function (" .. tostring(self.Name) .. ")")
	local conn = { Connected = true, Fn = fn }
	function conn.Disconnect(c)
		c.Connected = false
	end
	table.insert(self.Conns, conn)
	return conn
end
function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end
function Signal:Fire(...)
	for _, conn in table.clone(self.Conns) do
		if conn.Connected then
			task.spawn(conn.Fn, ...)
		end
	end
	local waiting = self.Waiting
	self.Waiting = {}
	for _, co in waiting do
		resume(co, ...)
	end
end
function Signal:Wait()
	table.insert(self.Waiting, coroutine.running())
	return coroutine.yield()
end
function Signal:HasListeners()
	for _, c in self.Conns do
		if c.Connected then
			return true
		end
	end
	return #self.Waiting > 0
end
Engine.Signal = Signal

---------------------------------------------------------------------------
-- instance proxies
---------------------------------------------------------------------------
local meta = {}
local proxies = {}
local nextId = 0
local ID = "__eid"

local function idOf(real)
	local id = real:GetAttribute(ID)
	if id == nil then
		nextId += 1
		id = nextId
		real:SetAttribute(ID, id)
	end
	return id
end

local function isProxy(v)
	return type(v) == "table" and getmetatable(v) == meta
end
Engine.IsProxy = isProxy

local function wrap(real, world)
	if real == nil or typeof(real) ~= "Instance" then
		return real
	end
	local id = idOf(real)
	local p = proxies[id]
	if p then
		return p
	end
	p = setmetatable({ __real = real, __id = id, __world = world, __signals = {}, __virtual = {} }, meta)
	proxies[id] = p
	return p
end
Engine.Wrap = wrap

local function unwrap(v)
	if isProxy(v) then
		return rawget(v, "__real")
	end
	return v
end
Engine.Unwrap = unwrap

local function wrapAll(world, ...)
	local out = table.pack(...)
	for i = 1, out.n do
		local v = out[i]
		if typeof(v) == "Instance" then
			out[i] = wrap(v, world)
		elseif type(v) == "table" and not isProxy(v) then
			local copy = {}
			for k, x in v do
				copy[k] = if typeof(x) == "Instance" then wrap(x, world) else x
			end
			out[i] = copy
		end
	end
	return table.unpack(out, 1, out.n)
end

local function unwrapAll(...)
	local out = table.pack(...)
	for i = 1, out.n do
		out[i] = unwrap(out[i])
	end
	return table.unpack(out, 1, out.n)
end

local function signalOf(p, name)
	local signals = rawget(p, "__signals")
	local s = signals[name]
	if not s then
		s = Signal.new(name)
		signals[name] = s
	end
	return s
end
Engine.SignalOf = signalOf

local function peekSignal(p, name)
	return rawget(p, "__signals")[name]
end

local EVENTS = {
	Activated = true, MouseButton1Down = true, MouseButton1Up = true, MouseButton1Click = true,
	MouseLeave = true, MouseEnter = true, InputBegan = true, InputEnded = true, InputChanged = true,
	ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true,
	AncestryChanged = true, Changed = true, OnServerEvent = true, OnClientEvent = true,
	CharacterAdded = true, CharacterRemoving = true, Touched = true, TouchEnded = true,
	Triggered = true, PromptTriggered = true, Died = true, Completed = true, Destroying = true,
	PlayerAdded = true, PlayerRemoving = true, FocusLost = true,
}

local function isA(real, class)
	local ok, r = pcall(function()
		return real:IsA(class)
	end)
	return ok and r
end

local customMethods = {}

function customMethods.WaitForChild(p, real, world, name, timeout)
	local limit = timeout or 20
	local started = Engine.Now
	while true do
		local child = real:FindFirstChild(name)
		if child then
			return wrap(child, world)
		end
		if coroutine.isyieldable() and Engine.Now - started < limit then
			task.wait(0.1)
		else
			if timeout then
				return nil
			end
			error("Infinite yield: " .. real:GetFullName() .. ":WaitForChild(\"" .. tostring(name) .. "\")", 3)
		end
	end
end

function customMethods.GetPropertyChangedSignal(p, _real, _world, prop)
	return signalOf(p, "__prop_" .. prop)
end

function customMethods.GetAttributeChangedSignal(p, _real, _world, name)
	return signalOf(p, "__attr_" .. name)
end

function customMethods.SetAttribute(p, real, _world, name, value)
	local old = real:GetAttribute(name)
	real:SetAttribute(name, unwrap(value))
	if old ~= value then
		local s = peekSignal(p, "__attr_" .. name)
		if s then
			s:Fire()
		end
	end
	local mirrors = rawget(p, "__mirrors")
	if mirrors then
		for _, m in mirrors do
			m:SetAttribute(name, value)
		end
	end
end

local function markDestroyed(proxy)
	rawset(proxy, "__destroyed", true)
	-- like Roblox: every connection on a destroyed instance is disconnected
	for _, signal in rawget(proxy, "__signals") do
		for _, conn in signal.Conns do
			conn.Connected = false
		end
	end
end

function customMethods.Destroy(p, real)
	if rawget(p, "__destroyed") then
		return
	end
	markDestroyed(p)
	-- descendants are destroyed too (their Parent reads nil afterwards)
	for _, d in real:GetDescendants() do
		local id = d:GetAttribute(ID)
		local dp = id and proxies[id]
		if dp then
			markDestroyed(dp)
		end
	end
	local oldParent = real.Parent
	real.Parent = nil
	if oldParent then
		local op = proxies[oldParent:GetAttribute(ID)]
		if op then
			local s = peekSignal(op, "ChildRemoved")
			if s then
				s:Fire(p)
			end
		end
	end
end

function customMethods.Clone(p, real, world)
	local copy = real:Clone()
	copy:SetAttribute(ID, nil)
	for _, d in copy:GetDescendants() do
		d:SetAttribute(ID, nil)
	end
	return wrap(copy, world)
end

function customMethods.PivotTo(p, real, world, cf)
	if isA(real, "Model") then
		local root = real:FindFirstChild("HumanoidRootPart") or real.PrimaryPart
		if root then
			root.CFrame = cf
		end
	else
		real.CFrame = cf
	end
end

function customMethods.GetPivot(p, real)
	if isA(real, "Model") then
		local root = real:FindFirstChild("HumanoidRootPart") or real.PrimaryPart
		return root and root.CFrame or CFrame.new()
	end
	return real.CFrame
end

function customMethods.Play(p, real)
	local key = real.Name
	Engine.SoundPlays[key] = (Engine.SoundPlays[key] or 0) + 1
end
function customMethods.Stop() end
function customMethods.Emit() end

function customMethods.Kick(p, real, _world, message)
	table.insert(Engine.Kicks, { Name = real.Name, Message = message })
end

function customMethods.FireServer(p, real, world, ...)
	Engine.Bridge.ToServer(world, real.Name, ...)
end
function customMethods.FireClient(p, real, world, player, ...)
	Engine.Bridge.ToClient(world, player, real.Name, ...)
end
function customMethods.FireAllClients(p, real, world, ...)
	Engine.Bridge.ToAll(world, real.Name, ...)
end

function customMethods.BulkMoveTo(p, real, world, parts, cframes)
	for i, part in parts do
		part.CFrame = cframes[i]
	end
end
function customMethods.GetServerTimeNow()
	return Engine.BaseTime + Engine.Now
end

local FALLBACKS = {
	Position = function(real)
		return real.CFrame.Position
	end,
	AssemblyLinearVelocity = function()
		return Vector3.zero
	end,
	AbsolutePosition = function()
		return Vector2.new(100, 100)
	end,
	AbsoluteSize = function()
		return Vector2.new(1280, 720)
	end,
}

meta.__index = function(p, key)
	local real = rawget(p, "__real")
	local world = rawget(p, "__world")
	local custom = customMethods[key]
	if custom then
		return function(_self, ...)
			return custom(p, real, world, ...)
		end
	end
	if world and world.Custom then
		local handler = world.Custom(p, real, key)
		if handler ~= nil then
			return handler
		end
	end
	local virtual = rawget(p, "__virtual")
	if virtual[key] ~= nil then
		return virtual[key]
	end
	if key == "Parent" and rawget(p, "__destroyed") then
		return nil
	end
	local ok, value = pcall(function()
		return real[key]
	end)
	if ok then
		if type(value) == "function" then
			return function(_self, ...)
				return wrapAll(world, value(real, unwrapAll(...)))
			end
		end
		if typeof(value) == "Instance" then
			return wrap(value, world)
		end
		return value
	end
	local message = tostring(value)
	if EVENTS[key] then
		return signalOf(p, key)
	end
	if FALLBACKS[key] then
		return FALLBACKS[key](real)
	end
	error(message, 2)
end

meta.__newindex = function(p, key, value)
	local real = rawget(p, "__real")
	local raw = unwrap(value)
	if key == "Parent" and rawget(p, "__destroyed") then
		error("The Parent property of " .. real.Name .. " is locked (destroyed)", 2)
	end
	local ok, err = pcall(function()
		real[key] = raw
	end)
	if not ok then
		local message = tostring(err)
		if string.find(message, "not a valid member", 1, true) or string.find(message, "Failed to convert", 1, true) then
			error(message, 2)
		end
		rawget(p, "__virtual")[key] = value
	end
	local s = peekSignal(p, "__prop_" .. key)
	if s then
		s:Fire()
	end
	if key == "Parent" and raw ~= nil then
		-- ChildAdded / DescendantAdded on the new ancestors
		local parentProxy = proxies[raw:GetAttribute(ID)]
		if parentProxy then
			local c = peekSignal(parentProxy, "ChildAdded")
			if c then
				c:Fire(p)
			end
		end
		local ancestor = raw
		while ancestor do
			local ap = proxies[ancestor:GetAttribute(ID)]
			local d = ap and peekSignal(ap, "DescendantAdded")
			if d then
				d:Fire(p)
				for _, sub in real:GetDescendants() do
					d:Fire(wrap(sub, rawget(p, "__world")))
				end
			end
			ancestor = ancestor.Parent
		end
	end
end

meta.__tostring = function(p)
	return "Proxy(" .. rawget(p, "__real"):GetFullName() .. ")"
end

---------------------------------------------------------------------------
-- serialization rules of RemoteEvents (subset): no functions, no sparse / mixed tables
---------------------------------------------------------------------------
local function netCopy(v, path)
	local t = type(v)
	if t == "function" or t == "thread" then
		error("cannot send a " .. t .. " over the network at " .. path)
	end
	if isProxy(v) then
		return v -- instances: resolved by the receiving side (not used by this game)
	end
	if t ~= "table" then
		return v
	end
	local numeric, strings, count = 0, 0, 0
	for k in v do
		count += 1
		if type(k) == "number" then
			numeric += 1
		elseif type(k) == "string" then
			strings += 1
		else
			error("unsupported key type " .. type(k) .. " at " .. path)
		end
	end
	if numeric > 0 and strings > 0 then
		error("mixed table (numbers + strings) would lose data over the network at " .. path)
	end
	if numeric > 0 and #v ~= numeric then
		error("sparse array would be truncated over the network at " .. path)
	end
	local out = {}
	for k, x in v do
		out[k] = netCopy(x, path .. "." .. tostring(k))
	end
	return out
end
Engine.NetCopy = netCopy

---------------------------------------------------------------------------
-- worlds
---------------------------------------------------------------------------
Engine.Worlds = {}
Engine.Server = nil
Engine.Clients = {} -- name -> client world

local sourcemap = serde.decode("json", fs.readFile("sourcemap.json"))

-- fs.readFile yields to Lune's own scheduler, so every script source is read up front
local sources = {}
local function preload(node)
	for _, path in node.filePaths or {} do
		if string.match(path, "%.luau?$") then
			sources[path] = fs.readFile(path)
		end
	end
	for _, child in node.children or {} do
		preload(child)
	end
end
preload(sourcemap)

local function buildTree(world, node, parentReal)
	local real
	if node.className == "DataModel" then
		real = nil
	elseif parentReal == nil then
		real = world.DM:GetService(node.className)
	else
		real = RealInstance.new(node.className)
		real.Name = node.name
		if node.filePaths then
			for _, path in node.filePaths do
				if string.match(path, "%.luau?$") then
					real:SetAttribute("__file", path)
				end
			end
		end
		real.Parent = parentReal
	end
	for _, child in node.children or {} do
		if node.className == "DataModel" then
			if world.Roots[child.name] then
				buildTree(world, child, nil)
			end
		else
			buildTree(world, child, real)
		end
	end
end

local FakeRandom = {}
FakeRandom.__index = FakeRandom
local randomSeed = 1
function FakeRandom.new(seed)
	randomSeed += 7919
	local s = math.floor(seed or randomSeed) % 2147483646 + 1
	return setmetatable({ State = s }, FakeRandom)
end
function FakeRandom:_next()
	self.State = (self.State * 48271) % 2147483647
	return (self.State - 1) / 2147483646
end
function FakeRandom:NextNumber(min, max)
	local r = self:_next()
	if min and max then
		return min + (max - min) * r
	end
	return r
end
function FakeRandom:NextInteger(min, max)
	return min + math.floor(self:_next() * (max - min + 1))
end

local function makeStubs(world)
	local stubs = {}
	local RunService = {
		Heartbeat = Signal.new("Heartbeat"),
		RenderStepped = Signal.new("RenderStepped"),
		Stepped = Signal.new("Stepped"),
		Binds = {},
	}
	function RunService:IsStudio()
		return Engine.Studio
	end
	function RunService:IsServer()
		return world.IsServer
	end
	function RunService:IsClient()
		return not world.IsServer
	end
	function RunService:BindToRenderStep(name, priority, fn)
		table.insert(self.Binds, { Name = name, Priority = priority, Fn = fn })
		table.sort(self.Binds, function(a, b)
			return a.Priority < b.Priority
		end)
	end
	function RunService:UnbindFromRenderStep(name)
		for i, b in self.Binds do
			if b.Name == name then
				table.remove(self.Binds, i)
				return
			end
		end
	end
	stubs.RunService = RunService

	stubs.UserInputService = {
		TouchEnabled = world.Touch == true,
		KeyboardEnabled = world.Touch ~= true,
		MouseEnabled = world.Touch ~= true,
		GamepadEnabled = false,
		InputBegan = Signal.new("InputBegan"),
		InputEnded = Signal.new("InputEnded"),
		GetFocusedTextBox = function()
			return nil
		end,
	}
	stubs.ContextActionService = {
		Actions = {},
		BindActionAtPriority = function(self, name, fn, _touch, _priority, ...)
			self.Actions[name] = { Fn = fn, Keys = { ... } }
		end,
		BindAction = function(self, name, fn, _touch, ...)
			self.Actions[name] = { Fn = fn, Keys = { ... } }
		end,
		UnbindAction = function(self, name)
			self.Actions[name] = nil
		end,
	}
	stubs.TweenService = {
		Create = function(_self, instance, _info, props)
			local tween = { Completed = Signal.new("Completed") }
			function tween.Play()
				for k, v in props do
					instance[k] = v -- final state immediately (validates property names)
				end
				tween.Completed:Fire(Enum.PlaybackState.Completed)
			end
			function tween.Cancel() end
			function tween.Pause() end
			return tween
		end,
	}
	stubs.PhysicsService = {
		RegisterCollisionGroup = function() end,
		CollisionGroupSetCollidable = function() end,
	}
	local guid = 0
	stubs.HttpService = {
		GenerateGUID = function()
			guid += 1
			return "guid-" .. guid
		end,
		JSONEncode = function(_self, v)
			return serde.encode("json", v)
		end,
		JSONDecode = function(_self, s)
			return serde.decode("json", s)
		end,
	}
	stubs.ProximityPromptService = { PromptTriggered = Signal.new("PromptTriggered") }
	stubs.MarketplaceService = {
		PromptGamePassPurchaseFinished = Signal.new("PromptGamePassPurchaseFinished"),
		UserOwnsGamePassAsync = function(_self, userId, passId)
			return Engine.OwnedPasses[userId .. ":" .. passId] == true
		end,
		PromptGamePassPurchase = function(_self, player, id)
			table.insert(Engine.Prompts, { Kind = "Pass", Id = id })
		end,
		PromptProductPurchase = function(_self, player, id)
			table.insert(Engine.Prompts, { Kind = "Product", Id = id })
		end,
	}

	local function checkStore()
		if Engine.DataStoreDown then
			error("502: DataStore request failed (simulated outage)")
		end
	end
	local function encode(v)
		if v == nil then
			return nil
		end
		return serde.encode("json", v)
	end
	local function decode(s)
		if s == nil then
			return nil
		end
		return serde.decode("json", s)
	end
	stubs.DataStoreService = {
		GetDataStore = function(_self, name)
			if Engine.StudioNoApi then
				error("Studio access to API services is not enabled")
			end
			Engine.DataStores[name] = Engine.DataStores[name] or {}
			local data = Engine.DataStores[name]
			local store = {}
			function store:GetAsync(key)
				if Engine.StudioNoApi then
					error("403: Studio access to API services is not enabled")
				end
				checkStore()
				return decode(data[key])
			end
			function store:SetAsync(key, value)
				checkStore()
				data[key] = encode(value)
			end
			function store:UpdateAsync(key, transform)
				checkStore()
				local new = transform(decode(data[key]))
				if new == nil then
					return nil
				end
				data[key] = encode(new) -- json: nan/inf/functions/mixed tables fail like the real store
				return decode(data[key])
			end
			function store:RemoveAsync(key)
				checkStore()
				local old = data[key]
				data[key] = nil
				return decode(old)
			end
			return store
		end,
		GetOrderedDataStore = function(_self, name)
			Engine.OrderedStores[name] = Engine.OrderedStores[name] or {}
			local data = Engine.OrderedStores[name]
			local store = {}
			function store:SetAsync(key, value)
				checkStore()
				assert(type(value) == "number" and value == math.floor(value), "OrderedDataStore values must be integers")
				data[key] = value
			end
			function store:GetSortedAsync(ascending, pageSize)
				checkStore()
				local rows = {}
				for k, v in data do
					table.insert(rows, { key = k, value = v })
				end
				table.sort(rows, function(a, b)
					return if ascending then a.value < b.value else a.value > b.value
				end)
				local page = {}
				for i = 1, math.min(pageSize, #rows) do
					page[i] = rows[i]
				end
				return {
					GetCurrentPage = function()
						return page
					end,
					IsFinished = true,
				}
			end
			return store
		end,
		GetRequestBudgetForRequestType = function()
			return 100
		end,
	}
	return stubs
end

local function newWorld(name, isServer, opts)
	local world = {
		Name = name,
		IsServer = isServer,
		Touch = opts and opts.Touch,
		DM = RealInstance.new("DataModel"),
		Modules = {},
		CloseCallbacks = {},
		Roots = if isServer
			then { ReplicatedStorage = true, ServerScriptService = true }
			else { ReplicatedStorage = true, StarterPlayer = true },
	}
	world.Stubs = makeStubs(world)
	buildTree(world, sourcemap, nil)
	world.Camera = {
		CFrame = CFrame.new(0, 20, 30),
		FieldOfView = 70,
		ViewportSize = if opts and opts.Touch then Vector2.new(844, 390) else Vector2.new(1280, 720),
		Signals = {},
	}
	function world.Camera:GetPropertyChangedSignal(prop)
		self.Signals[prop] = self.Signals[prop] or Signal.new(prop)
		return self.Signals[prop]
	end
	function world.Camera:WorldToViewportPoint(_pos)
		return Vector3.new(640, 300, 10), true
	end

	local CUSTOM_KEYS = { CurrentCamera = true, LocalPlayer = true, GetPlayers = true, GetPlayerByUserId = true, GetNameFromUserIdAsync = true }
	world.Custom = function(p, real, key)
		if not CUSTOM_KEYS[key] then
			return nil
		end
		if key == "CurrentCamera" and isA(real, "Workspace") then
			return world.Camera
		end
		if isA(real, "Players") then
			if key == "LocalPlayer" then
				return world.LocalPlayer
			elseif key == "GetPlayers" then
				return function()
					local list = {}
					for _, c in real:GetChildren() do
						if c:IsA("Player") then
							table.insert(list, wrap(c, world))
						end
					end
					return list
				end
			elseif key == "GetPlayerByUserId" then
				return function(_self, userId)
					for _, c in real:GetChildren() do
						if c:IsA("Player") and c.UserId == userId then
							return wrap(c, world)
						end
					end
					return nil
				end
			elseif key == "GetNameFromUserIdAsync" then
				return function(_self, userId)
					return "User" .. tostring(userId)
				end
			end
		end
		return nil
	end

	local gameObject = {
		JobId = "",
		PlaceId = 0,
		CreatorId = 0,
		CreatorType = Enum.CreatorType.User,
	}
	function gameObject:GetService(serviceName)
		local stub = world.Stubs[serviceName]
		if stub then
			return stub
		end
		return wrap(world.DM:GetService(serviceName), world)
	end
	function gameObject:BindToClose(fn)
		table.insert(world.CloseCallbacks, fn)
	end
	world.Game = gameObject

	local env = {
		game = gameObject,
		workspace = gameObject:GetService("Workspace"),
		Instance = {
			new = function(className, parent)
				local inst = wrap(RealInstance.new(className), world)
				if parent then
					inst.Parent = parent
				end
				return inst
			end,
		},
		task = task,
		os = setmetatable({
			clock = function()
				return Engine.Now
			end,
			time = function()
				return Engine.BaseTime + math.floor(Engine.Now)
			end,
		}, { __index = os }),
		tick = function()
			return Engine.BaseTime + Engine.Now
		end,
		typeof = function(v)
			if isProxy(v) then
				return "Instance"
			end
			return typeof(v)
		end,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			local message = table.concat(parts, " ")
			table.insert(Engine.Warnings, "[" .. name .. "] " .. message)
			if Engine.Verbose then
				print("[warn:" .. name .. "] " .. message)
			end
		end,
		print = function(...)
			if Engine.Verbose then
				print("[" .. name .. "]", ...)
			end
		end,
		Enum = Enum,
		Vector2 = Vector2,
		Vector3 = Vector3,
		CFrame = CFrame,
		Color3 = Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		Font = roblox.Font,
		TweenInfo = {
			new = function(...)
				return { ... }
			end,
		},
		Random = FakeRandom,
	}
	env.require = function(target)
		if isProxy(target) then
			local real = rawget(target, "__real")
			local id = rawget(target, "__id")
			local cached = world.Modules[id]
			if cached ~= nil then
				return cached
			end
			local file = real:GetAttribute("__file")
			assert(file, "not a module: " .. real:GetFullName())
			local result = Engine.RunFile(world, target, file)
			world.Modules[id] = result
			return result
		end
		return require(target)
	end
	world.Env = env
	return world
end

function Engine.RunFile(world, scriptProxy, file)
	local source = assert(sources[file], "source not preloaded: " .. file)
	local env = table.clone(world.Env)
	env.script = scriptProxy
	local chunk = luau.load(source, { debugName = file, environment = env })
	return chunk()
end

-- Find an instance by path in a world ("ServerScriptService.Server.Main")
function Engine.Find(world, path)
	local parts = string.split(path, ".")
	local current = world.Game:GetService(parts[1])
	for i = 2, #parts do
		current = current:FindFirstChild(parts[i])
		assert(current, "path not found: " .. path)
	end
	return current
end

-- The loaded module table for an instance path (e.g. a service or a controller)
function Engine.Module(world, path)
	local inst = Engine.Find(world, path)
	local result = world.Modules[rawget(inst, "__id")]
	assert(result ~= nil, "module not loaded: " .. path)
	return result
end

-- Count descendants of a class (performance checks)
function Engine.Count(root, className)
	local n = 0
	for _, d in rawget(root, "__real"):GetDescendants() do
		if d:IsA(className) then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- remotes bridge
---------------------------------------------------------------------------
local Bridge = {}
Engine.Bridge = Bridge

local function remoteIn(world, name)
	local rs = world.Game:GetService("ReplicatedStorage")
	local folder = rs:FindFirstChild("ChileRemotes")
	return folder and folder:FindFirstChild(name)
end

local function packNet(remoteName, ...)
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = netCopy(args[i], remoteName .. "#" .. i)
	end
	return args
end

local function serverPlayerFor(clientWorld)
	return clientWorld.ServerPlayer
end

function Bridge.ToServer(clientWorld, remoteName, ...)
	local server = Engine.Server
	local remote = remoteIn(server, remoteName)
	assert(remote, "server remote missing: " .. remoteName)
	local args = packNet(remoteName, ...)
	local signal = signalOf(remote, "OnServerEvent")
	signal:Fire(serverPlayerFor(clientWorld), table.unpack(args, 1, args.n))
end

local function clientFor(serverPlayer)
	for _, world in Engine.Clients do
		if world.ServerPlayer == serverPlayer then
			return world
		end
	end
	return nil
end

function Bridge.ToClient(_serverWorld, player, remoteName, ...)
	local world = clientFor(player)
	if not world then
		return
	end
	local remote = remoteIn(world, remoteName)
	assert(remote, "client remote missing: " .. remoteName)
	local args = packNet(remoteName, ...)
	world.NetLog[remoteName] = (world.NetLog[remoteName] or 0) + 1
	signalOf(remote, "OnClientEvent"):Fire(table.unpack(args, 1, args.n))
end

function Bridge.ToAll(serverWorld, remoteName, ...)
	for _, world in Engine.Clients do
		Bridge.ToClient(serverWorld, world.ServerPlayer, remoteName, ...)
	end
end

---------------------------------------------------------------------------
-- lifecycle
---------------------------------------------------------------------------
function Engine.StartServer()
	local server = newWorld("server", true)
	Engine.Server = server
	table.insert(Engine.Worlds, server)
	local main = Engine.Find(server, "ServerScriptService.Server.Main")
	local co = task.spawn(function()
		Engine.RunFile(server, main, rawget(main, "__real"):GetAttribute("__file"))
	end)
	Engine.RunDue()
	if coroutine.status(co) ~= "dead" and Engine.Verbose then
		print("[engine] server main still running:", debug.traceback(co))
	end
	return server
end

local function addPlayerInstance(world, name, userId)
	local players = world.Game:GetService("Players")
	local p = world.Env.Instance.new("Player")
	p.Name = name
	p.DisplayName = name
	p.UserId = userId
	local gui = world.Env.Instance.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = p
	p.Parent = players
	return p
end

local function buildRig(world, name, position)
	local new = world.Env.Instance.new
	local model = new("Model")
	model.Name = name
	local root = new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(position)
	root.Transparency = 1
	root.Parent = model
	model.PrimaryPart = root
	local humanoid = new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2
	humanoid.Parent = model
	local head = new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0))
	head.Parent = model
	local mesh = new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local face = new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = head
	local hatAttachment = new("Attachment")
	hatAttachment.Name = "HatAttachment"
	hatAttachment.CFrame = CFrame.new(0, 0.6, 0)
	hatAttachment.Parent = head
	local torso = new("Part")
	torso.Name = "UpperTorso"
	torso.Size = Vector3.new(2, 1.6, 1)
	torso.Parent = model
	local colors = new("BodyColors")
	colors.HeadColor3 = Color3.fromRGB(234, 184, 146)
	colors.Parent = model
	model.Parent = world.Game:GetService("Workspace")
	return model
end

function Engine.AddAccessory(world, character)
	local new = world.Env.Instance.new
	local accessory = new("Accessory")
	accessory.Name = "TopHat"
	local handle = new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	local mesh = new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = "rbxassetid://1"
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = handle
	local attachment = new("Attachment")
	attachment.Name = "HatAttachment"
	attachment.CFrame = CFrame.new(0, -0.4, 0)
	attachment.Parent = handle
	handle.Parent = accessory
	accessory.Parent = character
	return accessory
end

Engine.Characters = {} -- name -> position (so late joiners also see existing characters)

function Engine.SpawnCharacter(name, position)
	position = position or Vector3.new(-120, 3, 0)
	Engine.Characters[name] = position
	for _, world in Engine.Worlds do
		local player = world.PlayersByName and world.PlayersByName[name]
		if player then
			local rig = buildRig(world, name, position)
			player.Character = rig
			signalOf(player, "CharacterAdded"):Fire(rig)
		end
	end
	Engine.RunDue()
end

function Engine.MoveCharacter(name, position, velocity)
	Engine.Characters[name] = position
	for _, world in Engine.Worlds do
		local player = world.PlayersByName and world.PlayersByName[name]
		local character = player and player.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart")
			root.CFrame = CFrame.new(position)
			if velocity then
				rawget(root, "__virtual").AssemblyLinearVelocity = velocity
			end
		end
	end
end

local nextUserId = 1000

-- A player joins: server Player + a new client world running the client scripts
function Engine.AddPlayer(name, opts)
	nextUserId += 1
	local userId = opts and opts.UserId or nextUserId
	local server = Engine.Server
	server.PlayersByName = server.PlayersByName or {}

	local serverPlayer = addPlayerInstance(server, name, userId)
	server.PlayersByName[name] = serverPlayer

	local client = newWorld("client:" .. name, false, opts)
	client.NetLog = {}
	client.ServerPlayer = serverPlayer
	client.PlayersByName = {}
	Engine.Clients[name] = client
	table.insert(Engine.Worlds, client)
	-- replicated things the client needs: remotes, the map, workspace attributes
	local serverRS = rawget(server.Game:GetService("ReplicatedStorage"), "__real")
	local remotes = serverRS:FindFirstChild("ChileRemotes")
	if remotes then
		local copy = remotes:Clone()
		copy:SetAttribute(ID, nil)
		for _, d in copy:GetDescendants() do
			d:SetAttribute(ID, nil)
		end
		copy.Parent = rawget(client.Game:GetService("ReplicatedStorage"), "__real")
	end
	local serverWS = server.Game:GetService("Workspace")
	local map = serverWS:FindFirstChild("ChileMap")
	if map then
		map:Clone().Parent = client.Game:GetService("Workspace")
	end
	local ws = client.Game:GetService("Workspace")
	for _, attr in { "EventId", "EventEndsAt" } do
		ws:SetAttribute(attr, serverWS:GetAttribute(attr))
	end
	rawset(serverWS, "__mirrors", rawget(serverWS, "__mirrors") or {})
	table.insert(rawget(serverWS, "__mirrors"), ws)

	-- players in this client: everyone (existing players first)
	for otherName, otherServerPlayer in server.PlayersByName do
		local p = addPlayerInstance(client, otherName, otherServerPlayer.UserId)
		client.PlayersByName[otherName] = p
		rawset(otherServerPlayer, "__mirrors", rawget(otherServerPlayer, "__mirrors") or {})
		table.insert(rawget(otherServerPlayer, "__mirrors"), p)
		for attr, value in rawget(otherServerPlayer, "__real"):GetAttributes() do
			if attr ~= ID then
				p:SetAttribute(attr, value)
			end
		end
		if otherName == name then
			client.LocalPlayer = p
		end
	end
	-- existing clients learn about the new player
	for otherName, other in Engine.Clients do
		if otherName ~= name then
			local p = addPlayerInstance(other, name, userId)
			other.PlayersByName[name] = p
			table.insert(rawget(serverPlayer, "__mirrors"), p)
			signalOf(other.Game:GetService("Players"), "PlayerAdded"):Fire(p)
		end
	end

	-- characters that already exist replicate to the new client
	for otherName, pos in Engine.Characters do
		local p = client.PlayersByName[otherName]
		if p and otherName ~= name then
			local rig = buildRig(client, otherName, pos)
			p.Character = rig
		end
	end

	-- client scripts start (like StarterPlayerScripts)
	local main = Engine.Find(client, "StarterPlayer.StarterPlayerScripts.Client.Main")
	task.spawn(function()
		Engine.RunFile(client, main, rawget(main, "__real"):GetAttribute("__file"))
	end)
	-- the server learns about the player
	signalOf(server.Game:GetService("Players"), "PlayerAdded"):Fire(serverPlayer)
	Engine.RunDue()
	return client, serverPlayer
end

function Engine.RemovePlayer(name)
	local server = Engine.Server
	local serverPlayer = server.PlayersByName[name]
	signalOf(server.Game:GetService("Players"), "PlayerRemoving"):Fire(serverPlayer)
	for otherName, other in Engine.Clients do
		if otherName ~= name then
			local p = other.PlayersByName[name]
			if p then
				signalOf(other.Game:GetService("Players"), "PlayerRemoving"):Fire(p)
				p:Destroy()
				other.PlayersByName[name] = nil
			end
		end
	end
	local client = Engine.Clients[name]
	Engine.Clients[name] = nil
	for i, world in Engine.Worlds do
		if world == client then
			table.remove(Engine.Worlds, i)
			break
		end
	end
	Engine.RunDue()
	-- the character leaves with the player (in every world)
	Engine.Characters[name] = nil
	for _, world in Engine.Worlds do
		local ws = world.Game:GetService("Workspace")
		local rig = ws:FindFirstChild(name)
		if rig and rig:IsA("Model") then
			rig:Destroy()
		end
	end
	serverPlayer:Destroy()
	server.PlayersByName[name] = nil
end

-- Advance virtual time in frames of dt
function Engine.Step(seconds, dt)
	dt = dt or 1 / 30
	local steps = math.max(1, math.floor(seconds / dt + 0.5))
	for _ = 1, steps do
		Engine.Now += dt
		Engine.RunDue()
		for _, world in Engine.Worlds do
			local rs = world.Stubs.RunService
			rs.Stepped:Fire(Engine.Now, dt)
			if not world.IsServer then
				for _, bind in table.clone(rs.Binds) do
					task.spawn(bind.Fn, dt)
				end
				rs.RenderStepped:Fire(dt)
			end
			rs.Heartbeat:Fire(dt)
		end
		Engine.RunDue()
	end
end

function Engine.Shutdown()
	local server = Engine.Server
	local pending = 0
	for _, fn in server.CloseCallbacks do
		pending += 1
		task.spawn(function()
			fn()
			pending -= 1
		end)
	end
	local guard = 0
	while pending > 0 and guard < 3000 do
		Engine.Step(0.1, 0.1)
		guard += 1
	end
	return pending == 0
end

-- Fire a GUI button like a player tap/click
function Engine.Click(button)
	signalOf(button, "MouseButton1Down"):Fire()
	signalOf(button, "InputBegan"):Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(640, 500, 0) })
	signalOf(button, "MouseButton1Up"):Fire()
	signalOf(button, "Activated"):Fire()
	Engine.RunDue()
end

return Engine
