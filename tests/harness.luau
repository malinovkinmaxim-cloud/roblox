--[[
	Test harness for running game modules outside Roblox with Lune (https://lune-org.github.io).
	Provides a tiny fake DataModel: `game:GetService(...)`, `script`, `require(instancePath)`
	resolved to files through the same layout as default.project.json.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Harness = {}

local ROOTS = {
	["ReplicatedStorage.Shared"] = "src/shared",
	["ServerScriptService.Server"] = "src/server",
	["ServerStorage.Levels"] = "src/levels",
	["StarterPlayer.StarterPlayerScripts.Client"] = "src/client",
}

-- Deterministic stand-in for Roblox's Random
local FakeRandom = {}
FakeRandom.__index = FakeRandom
function FakeRandom.new(seed: number?)
	return setmetatable({ State = (seed or 1) % 2147483647 }, FakeRandom)
end
function FakeRandom:_next(): number
	self.State = (self.State * 48271) % 2147483647
	return self.State / 2147483647
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

-- Proxy objects that represent instance paths ("ServerScriptService.Server.Level.LevelKit")
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
	-- methods on services used at module top level are no-ops
	if type(key) == "string" and string.match(key, "^[A-Z]") and (key == "Connect" or key == "IsStudio" or key == "IsServer" or key == "IsClient") then
		return function()
			return false
		end
	end
	return makeProxy(self.__path .. "." .. tostring(key))
end

local function resolveFile(path: string): string?
	for prefix, dir in ROOTS do
		if path == prefix then
			return nil
		end
		if string.sub(path, 1, #prefix + 1) == prefix .. "." then
			local rest = string.sub(path, #prefix + 2)
			local file = dir .. "/" .. string.gsub(rest, "%.", "/")
			if fs.isFile(file .. ".lua") then
				return file .. ".lua"
			end
			if fs.isFile(file .. ".luau") then
				return file .. ".luau"
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

local function stubTweenInfo()
	return {
		new = function(...)
			return { ... }
		end,
	}
end

environment = {
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	TweenInfo = stubTweenInfo(),
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

function Harness.LevelModuleNames(): { string }
	local names = {}
	for _, name in fs.readDir("src/levels") do
		if string.match(name, "%.lua$") then
			table.insert(names, (string.gsub(name, "%.lua$", "")))
		end
	end
	table.sort(names)
	return names
end

Harness.Random = FakeRandom

---------------------------------------------------------------------------
-- tiny test runner
---------------------------------------------------------------------------
local results = { passed = 0, failed = 0, failures = {} }

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

function Harness.Near(a: number, b: number, epsilon: number?, message: string?)
	if math.abs(a - b) > (epsilon or 1e-6) then
		error(string.format("%s: expected %s ~= %s", message or "near", tostring(a), tostring(b)), 2)
	end
end

function Harness.Results()
	return results
end

return Harness
