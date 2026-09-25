--[[
	Offline test suite (run from the repository root):
	    lune run tests/run.luau

	Covers everything that can be verified without the Roblox engine:
	  - every level module loads and passes LevelValidator
	  - level geometry: every AI route node stands on a real floor, route graphs reach the
	    finish, no coplanar overlapping floors (z-fighting), fake groups leave a real platform
	  - TrailRecorder (Shadow recording / playback) maths
	  - reward calculation, XP progression, moving platform motion
]]

local process = require("@lune/process")
local Vector3 = require("@lune/roblox").Vector3

local H = require("./harness")
local Test, Expect, Near = H.Test, H.Expect, H.Near

local LevelValidator = H.Require("ServerScriptService.Server.Level.LevelValidator")
local TrailRecorder = H.Require("ServerScriptService.Server.Doppelganger.TrailRecorder")
local Progression = H.Require("ReplicatedStorage.Shared.Progression")
local Config = H.Require("ReplicatedStorage.Shared.Config")

---------------------------------------------------------------------------
print("\n[levels]")
---------------------------------------------------------------------------
local levels = {}
for _, name in H.LevelModuleNames() do
	Test("load " .. name, function()
		local def = H.Require("ServerStorage.Levels." .. name)
		Expect(type(def) == "table", "module must return a table")
		table.insert(levels, def)
	end)
end
table.sort(levels, function(a, b)
	return a.Id < b.Id
end)

Test("at least 10 levels with unique ids", function()
	Expect(#levels >= 10, "only " .. #levels .. " levels")
	local seen = {}
	for _, def in levels do
		Expect(not seen[def.Id], "duplicate id " .. def.Id)
		seen[def.Id] = true
	end
end)

for _, def in levels do
	Test(string.format("validate level %02d %s", def.Id, def.Name), function()
		local errors = LevelValidator.Validate(def)
		Expect(#errors == 0, table.concat(errors, "\n       "))
	end)
end

-- floor surfaces an actor can stand on: { minX, maxX, minZ, maxZ, top, id }
local function surfaces(def)
	local list = {}
	local function add(center, size, top, spec)
		table.insert(list, {
			MinX = center.X - size.X / 2,
			MaxX = center.X + size.X / 2,
			MinZ = center.Z - size.Z / 2,
			MaxZ = center.Z + size.Z / 2,
			Top = top,
			Spec = spec,
		})
	end
	for _, spec in def.Elements do
		local t = spec.Type
		if t == "Platform" or t == "Fake" or t == "Disappearing" or t == "Falling" or t == "MovingPlatform" or t == "Kill" then
			add(spec.Pos, spec.Size, spec.Pos.Y + spec.Size.Y / 2, spec)
		elseif t == "Start" or t == "Checkpoint" or t == "Finish" then
			add(spec.Pos, spec.Size, spec.Pos.Y, spec)
		elseif t == "Door" and spec.Bridge then
			local pos = spec.Pos + spec.OpenOffset
			add(pos, spec.Size, pos.Y + spec.Size.Y / 2, spec)
		end
	end
	return list
end

local function standsOn(list, pos, tolerance)
	for _, s in list do
		if pos.X >= s.MinX - 0.5 and pos.X <= s.MaxX + 0.5 and pos.Z >= s.MinZ - 0.5 and pos.Z <= s.MaxZ + 0.5 then
			if math.abs(s.Top - pos.Y) <= tolerance then
				return s
			end
		end
	end
	return nil
end

for _, def in levels do
	if def.Route then
		Test(string.format("level %02d route nodes stand on floors", def.Id), function()
			local list = surfaces(def)
			local bad = {}
			for _, node in def.Route do
				local s = standsOn(list, node.Pos, 0.6)
				if not s then
					table.insert(bad, node.Id .. " @ " .. tostring(node.Pos))
				elseif s.Spec.Type == "Kill" then
					table.insert(bad, node.Id .. " stands on a kill brick")
				end
			end
			Expect(#bad == 0, "floating nodes: " .. table.concat(bad, ", "))
		end)

		Test(string.format("level %02d route reaches the finish", def.Id), function()
			local byId, order = {}, {}
			for index, node in def.Route do
				byId[node.Id] = node
				order[index] = node.Id
			end
			local function nextOf(index, node)
				if node.Next then
					return node.Next
				end
				if node.Finish then
					return {}
				end
				return { order[index + 1] }
			end
			local indexOf = {}
			for index, id in order do
				indexOf[id] = index
			end
			-- every node must be able to reach a finish node
			for _, node in def.Route do
				local seen, stack, found = {}, { node.Id }, false
				while #stack > 0 do
					local id = table.remove(stack)
					if not seen[id] then
						seen[id] = true
						local current = byId[id]
						Expect(current, "unknown node " .. tostring(id))
						if current.Finish then
							found = true
							break
						end
						for _, nextId in nextOf(indexOf[id], current) do
							table.insert(stack, nextId)
						end
						for _, nextId in current.Fallback or {} do
							table.insert(stack, nextId)
						end
					end
				end
				Expect(found, "node " .. node.Id .. " can't reach the finish")
			end
		end)

		Test(string.format("level %02d route hops are jumpable", def.Id), function()
			local byId, order = {}, {}
			for index, node in def.Route do
				byId[node.Id] = node
				order[index] = node.Id
			end
			for index, node in def.Route do
				local nextIds = node.Next or (if node.Finish then {} else { order[index + 1] })
				for _, nextId in nextIds do
					local other = byId[nextId]
					local attachedToMover = false
					for _, spec in def.Elements do
						if spec.Id == other.On and spec.Type == "MovingPlatform" then
							attachedToMover = true
						end
						if spec.Id == node.On and spec.Type == "MovingPlatform" then
							attachedToMover = true
						end
					end
					local dy = other.Pos.Y - node.Pos.Y
					Expect(dy <= 5, string.format("%s -> %s climbs %.1f studs", node.Id, nextId, dy))
					if not attachedToMover then
						local flat = Vector3.new(other.Pos.X - node.Pos.X, 0, other.Pos.Z - node.Pos.Z).Magnitude
						-- long hops are fine only when there is floor all the way (walking)
						local list = surfaces(def)
						local gapFound = false
						for step = 1, 9 do
							local p = node.Pos:Lerp(other.Pos, step / 10)
							if not standsOn(list, p, 1.2) then
								gapFound = true
							end
						end
						if gapFound then
							Expect(flat <= 16, string.format("%s -> %s jumps %.1f studs", node.Id, nextId, flat))
						end
					end
				end
			end
		end)
	end

	Test(string.format("level %02d has no z-fighting floors", def.Id), function()
		local list = surfaces(def)
		local problems = {}
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i], list[j]
				if math.abs(a.Top - b.Top) < 0.01 then
					local overlapX = math.min(a.MaxX, b.MaxX) - math.max(a.MinX, b.MinX)
					local overlapZ = math.min(a.MaxZ, b.MaxZ) - math.max(a.MinZ, b.MinZ)
					if overlapX > 0.05 and overlapZ > 0.05 then
						table.insert(problems, string.format("%s@%s & %s@%s", a.Spec.Type, tostring(a.Spec.Pos), b.Spec.Type, tostring(b.Spec.Pos)))
					end
				end
			end
		end
		Expect(#problems == 0, table.concat(problems, "\n       "))
	end)

	Test(string.format("level %02d start -> finish is forward (+X)", def.Id), function()
		local startX, finishX
		for _, spec in def.Elements do
			if spec.Type == "Start" then
				startX = spec.Pos.X
			elseif spec.Type == "Finish" then
				finishX = spec.Pos.X
			end
		end
		Expect(startX and finishX and finishX > startX + 50, "finish must be well ahead of the start on +X")
	end)
end

Test("validator rejects broken levels", function()
	local errors = LevelValidator.Validate({
		Id = 99,
		Name = "Broken",
		ParTime = 10,
		Role = "Wizard",
		Elements = {
			{ Type = "Button", Id = "B", Pos = Vector3.zero, Activator = "Cat", Mode = "Hold", Targets = { "Nope" } },
		},
	})
	Expect(#errors >= 4, "expected several errors, got " .. #errors)
end)

---------------------------------------------------------------------------
print("\n[shadow recording]")
---------------------------------------------------------------------------
local function walkRecorder(maxAge)
	local recorder = TrailRecorder.new(maxAge or 30)
	for i = 0, 20 do
		local t = i * 0.1
		recorder:Push(t, Vector3.new(t * 16, 3, 0), 0, true, 0)
	end
	return recorder
end

Test("sample interpolates position", function()
	local recorder = walkRecorder()
	local sample = recorder:Sample(0.55)
	Expect(sample, "sample")
	Near(sample.Position.X, 8.8, 1e-4, "x")
	Expect(sample.Grounded, "grounded")
end)

Test("sample before the first snapshot is nil, after the last is the last", function()
	local recorder = walkRecorder()
	Expect(recorder:Sample(-1) == nil, "before")
	local sample = recorder:Sample(99)
	Near(sample.Position.X, 32, 1e-4, "clamped")
	Expect(sample.AtEnd, "AtEnd flag")
end)

Test("never interpolates across a teleport", function()
	local recorder = walkRecorder()
	recorder:MarkTeleport()
	recorder:Push(2.1, Vector3.new(500, 3, 0), 0, true, 0)
	local sample = recorder:Sample(2.05)
	Near(sample.Position.X, 32, 1e-4, "should hold the pre-teleport position")
	local after = recorder:Sample(2.1)
	Near(after.Position.X, 500, 1e-4, "arrives at the teleport target")
end)

Test("jump arcs are not ground-checked", function()
	local recorder = TrailRecorder.new(30)
	recorder:Push(0, Vector3.new(0, 3, 0), 0, true, 0)
	recorder:Push(0.1, Vector3.new(1.6, 6, 0), 0, false, 30)
	recorder:Push(0.2, Vector3.new(3.2, 7, 0), 0, false, 10)
	recorder:Push(0.3, Vector3.new(4.8, 3, 0), 0, true, -30)
	Expect(recorder.Snapshots[2].Jump, "jump flag on take-off")
	Expect(not recorder:Sample(0.05).Grounded, "take-off segment not grounded")
	Expect(not recorder:Sample(0.25).Grounded, "landing segment not grounded")
end)

Test("distance behind for the follower", function()
	local recorder = walkRecorder()
	local t = recorder:TimeAtDistanceBehind(6)
	Near(t, 2 - 6 / 16, 1e-4, "time 6 studs behind")
end)

Test("old snapshots are trimmed and compacted", function()
	local recorder = TrailRecorder.new(2)
	for i = 0, 2000 do
		recorder:Push(i * 0.05, Vector3.new(i, 0, 0), 0, true, 0)
	end
	Expect(recorder:Count() <= 42, "count " .. recorder:Count())
	local oldest = recorder:Oldest()
	Expect(oldest.T >= 100 - 2 - 0.051, "oldest " .. oldest.T)
	local sample = recorder:Sample(99.5)
	Near(sample.Position.X, 1990, 1e-3, "sample after compaction")
end)

Test("yaw interpolates the short way around", function()
	local recorder = TrailRecorder.new(30)
	recorder:Push(0, Vector3.zero, math.pi - 0.1, true, 0)
	recorder:Push(1, Vector3.zero, -math.pi + 0.1, true, 0)
	local sample = recorder:Sample(0.5)
	Expect(math.abs(math.abs(sample.Yaw) - math.pi) < 0.01, "yaw " .. sample.Yaw)
end)

---------------------------------------------------------------------------
print("\n[progression & rewards]")
---------------------------------------------------------------------------
Test("xp -> level", function()
	local level, into, need = Progression.FromXP(0)
	Expect(level == 1 and into == 0 and need == Config.XP_PER_LEVEL, "level 1 at 0 xp")
	level = Progression.FromXP(Config.XP_PER_LEVEL)
	Expect(level == 2, "level 2 exactly at threshold")
	level, into = Progression.FromXP(Config.XP_PER_LEVEL + Progression.XPForLevel(2) + 5)
	Expect(level == 3 and into == 5, "level 3 + 5 xp")
end)

local RewardService = H.Require("ServerScriptService.Server.Services.RewardService")

Test("first clear, no deaths, under par, beat rival", function()
	local calc = RewardService.Calculate({ FirstClear = true, Deaths = 0, Time = 20, ParTime = 30, HadRival = true, RivalFinished = false })
	local expected = Config.LEVEL_REWARD.Coins + Config.NO_DEATH_BONUS.Coins + Config.TIME_BONUS.Coins + Config.PERFECT_BONUS.Coins + Config.RIVAL_WIN_BONUS.Coins
	Expect(calc.Coins == expected, "coins " .. calc.Coins .. " ~= " .. expected)
	Expect(calc.Perfect and calc.RivalResult == "Won", "flags")
end)

Test("replay with deaths, over par, rival won", function()
	local calc = RewardService.Calculate({ FirstClear = false, Deaths = 3, Time = 50, ParTime = 30, HadRival = true, RivalFinished = true })
	Expect(calc.Coins == math.floor(Config.LEVEL_REWARD.Coins * Config.REPLAY_MULTIPLIER + 0.5), "replay coins " .. calc.Coins)
	Expect(not calc.Perfect and calc.RivalResult == "Lost", "flags")
	Expect(#calc.Lines == 1, "only the base line")
end)

---------------------------------------------------------------------------
print("\n[obstacles]")
---------------------------------------------------------------------------
local ObstacleService = H.Require("ServerScriptService.Server.Services.ObstacleService")

Test("linear mover: pause at both ends", function()
	local base = Vector3.new(0, 0, 0)
	local motion = { Kind = "Linear", Offset = Vector3.new(10, 0, 0), Period = 4, Pause = 0.5 }
	Near(ObstacleService.MotionAt(base, motion, 0.2).X, 0, 1e-6, "start pause")
	Near(ObstacleService.MotionAt(base, motion, 2.2).X, 10, 1e-6, "end pause")
	Near(ObstacleService.MotionAt(base, motion, 4.2).X, 0, 1e-6, "loops")
	local mid = ObstacleService.MotionAt(base, motion, 1.25).X
	Expect(mid > 4 and mid < 6, "midpoint " .. mid)
end)

Test("circle mover starts at its base position", function()
	local base = Vector3.new(5, 2, 1)
	local p = ObstacleService.MotionAt(base, { Kind = "Circle", Radius = 3, Period = 5 }, 0)
	Near((p - base).Magnitude, 0, 1e-6, "circle start")
	local half = ObstacleService.MotionAt(base, { Kind = "Circle", Radius = 3, Period = 5 }, 2.5)
	Near(half.X, base.X - 6, 1e-6, "opposite side")
end)

---------------------------------------------------------------------------
print("\n[AI simulations]")
---------------------------------------------------------------------------
local Sim = require("./sim")

for _, def in levels do
	local rivalLevel = def.Role == "Rival" or def.RivalStartCheckpoint ~= nil
	if rivalLevel then
		Test(string.format("rival finishes level %02d (20 seeds, never stuck)", def.Id), function()
			local worst, deaths, revealed = 0, 0, 0
			for seed = 1, 20 do
				local result = Sim.RunRival(def, seed, 300)
				Expect(result.Finished, "seed " .. seed .. ": rival never reached the finish")
				worst = math.max(worst, result.Time)
				deaths += result.Deaths
				revealed += result.Revealed
			end
			print(string.format("       slowest %.1fs, avg deaths %.2f, avg fakes revealed %.2f", worst, deaths / 20, revealed / 20))
		end)
	end
end

Test("shadow replays the player 0.7 s later", function()
	local samples = Sim.RunShadow({ Delay = 0.7, Seconds = 4 })
	for _, sample in samples do
		if sample.T > 1 and sample.T < 3.5 then
			local expected = math.min((sample.T - 0.7) * 16, 95)
			Near(sample.Shadow.X, expected, 1.2, string.format("t=%.2f", sample.T))
		end
	end
end)

Test("shadow waits at a closed door, then catches up when it opens", function()
	local samples = Sim.RunShadow({ Delay = 0.7, Seconds = 6, Door = 30, OpenDoorAt = 3, Phase = false })
	local atDoor, caughtUp = false, false
	for _, sample in samples do
		if sample.T > 2.5 and sample.T < 2.9 then
			Expect(sample.Shadow.X < 30, "passed a closed door at t=" .. sample.T)
			atDoor = sample.Shadow.X > 28
		end
		if sample.T > 5.8 then
			caughtUp = math.abs(sample.Shadow.X - math.min((sample.T - 0.7) * 16, 95)) < 1.5
		end
	end
	Expect(atDoor, "shadow should wait right at the door")
	Expect(caughtUp, "shadow should catch up after the door opens")
end)

Test("shadow phases through a door that stays closed", function()
	local samples = Sim.RunShadow({ Delay = 0.7, Seconds = 7, Door = 30, Phase = true })
	local last = samples[#samples]
	Expect(last.Shadow.X > 60, "shadow stuck at " .. tostring(last.Shadow.X))
end)

---------------------------------------------------------------------------
local results = H.Results()
print(string.format("\n%d passed, %d failed", results.passed, results.failed))
if results.failed > 0 then
	process.exit(1)
end
