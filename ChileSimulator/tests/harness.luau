--[[
	Test harness: runs the game's pure Luau modules outside Roblox with Lune
	(https://lune-org.github.io).

	Provides a tiny fake DataModel so `require(script.Parent.X)` and
	`game:GetService("ReplicatedStorage").Shared.X` resolve to files using the same layout as
	default.project.json. Roblox datatypes (Color3, Vector3, CFrame...) come from @lune/roblox.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Harness = {}

local ROOTS = {
	["ReplicatedStorage.Shared"] = "src/shared",
	["ServerScriptService.Server"] = "src/server",
	["StarterPlayer.StarterPlayerScripts.Client"] = "src/client",
}

-- Deterministic stand-in for Roblox's Random (Park-Miller)
local FakeRandom = {}
FakeRandom.__index = FakeRandom
function FakeRandom.new(seed: number?)
	local s = math.floor(seed or 1) % 2147483646 + 1
	return setmetatable({ State = s }, FakeRandom)
end
function FakeRandom:_next(): number
	self.State = (self.State * 48271) % 2147483647
	return (self.State - 1) / 2147483646
end
function FakeRandom:NextNumber(min: number?, max: number?): number
	local r = self:_next()
	if min and max then
		return min + (max - min) * r
	end
	return r
end
function FakeRandom:NextInteger(min: number, max: number): number
	return min + math.floor(self:_next() * (max - min + 1))
end
Harness.Random = FakeRandom

-- Proxy objects that stand for instance paths ("ReplicatedStorage.Shared.Config")
local proxyMeta = {}
local function makeProxy(path: string)
	return setmetatable({ __path = path }, proxyMeta)
end
proxyMeta.__index = function(self, key)
	if key == "Parent" then
		local parent = string.match(self.__path, "^(.*)%.[^%.]+$")
		return makeProxy(parent or "")
	end
	if key == "WaitForChild" or key == "FindFirstChild" then
		return function(proxy, name)
			return makeProxy(proxy.__path .. "." .. name)
		end
	end
	if key == "GetService" then
		return function(_, name)
			return makeProxy(name)
		end
	end
	if key == "IsStudio" or key == "IsServer" or key == "IsClient" then
		return function()
			return false
		end
	end
	local prefix = if self.__path == "" then "" else self.__path .. "."
	return makeProxy(prefix .. tostring(key))
end

local function resolveFile(path: string): string?
	for prefix, dir in ROOTS do
		if string.sub(path, 1, #prefix + 1) == prefix .. "." then
			local rest = string.sub(path, #prefix + 2)
			local file = dir .. "/" .. string.gsub(rest, "%.", "/")
			for _, ext in { ".lua", ".luau" } do
				if fs.isFile(file .. ext) then
					return file .. ext
				end
			end
		end
	end
	return nil
end

local cache = {}
local environment

local function requireProxy(target)
	if type(target) == "table" and getmetatable(target) == proxyMeta then
		local path = target.__path
		if cache[path] ~= nil then
			return cache[path]
		end
		local file = resolveFile(path)
		assert(file, "harness: cannot resolve module " .. path)
		local source = fs.readFile(file)
		local env = table.clone(environment)
		env.script = makeProxy(path)
		local chunk = luau.load(source, { debugName = file, environment = env })
		local result = chunk()
		cache[path] = result
		return result
	end
	return require(target)
end

local fakeClock = 0
function Harness.SetClock(t: number)
	fakeClock = t
end
function Harness.Clock(): number
	return fakeClock
end

environment = {
	os = setmetatable({
		clock = function()
			return fakeClock
		end,
	}, { __index = os }),
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	UDim2 = roblox.UDim2,
	UDim = roblox.UDim,
	Enum = roblox.Enum,
	Random = FakeRandom,
	game = makeProxy(""),
	workspace = makeProxy("Workspace"),
	require = requireProxy,
	typeof = typeof,
	task = {
		wait = function() end,
		spawn = function(fn, ...)
			fn(...)
		end,
		defer = function(fn, ...)
			fn(...)
		end,
		delay = function() end,
	},
}

function Harness.Require(path: string)
	return requireProxy(makeProxy(path))
end

---------------------------------------------------------------------------
-- tiny test runner
---------------------------------------------------------------------------
local results = { passed = 0, failed = 0, failures = {} }

function Harness.Section(name: string)
	print("\n[" .. name .. "]")
end

function Harness.Test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		results.passed += 1
		print("  ok   " .. name)
	else
		results.failed += 1
		table.insert(results.failures, name .. ": " .. tostring(err))
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end

function Harness.Expect(condition: any, message: string?)
	if not condition then
		error(message or "expectation failed", 2)
	end
end

function Harness.Eq(a: any, b: any, message: string?)
	if a ~= b then
		error(string.format("%s: expected %s, got %s", message or "Eq", tostring(b), tostring(a)), 2)
	end
end

function Harness.Near(a: number, b: number, epsilon: number?, message: string?)
	if math.abs(a - b) > (epsilon or 1e-6) then
		error(string.format("%s: %s is not near %s", message or "Near", tostring(a), tostring(b)), 2)
	end
end

function Harness.Finish(): boolean
	print(string.format("\n%d passed, %d failed", results.passed, results.failed))
	for _, f in results.failures do
		print("  - " .. f)
	end
	return results.failed == 0
end

return Harness
