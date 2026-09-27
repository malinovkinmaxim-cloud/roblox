--!nocheck
--[[
	Unit tests for the pure modules (data tables, network protocol, stats, save data,
	level-up offers, spatial grid, formatting) + a short headless run per character.
	lune run tests/run.luau
]]

local process = require("@lune/process")
local Harness = require("./harness")
local Bot = require("./bot")

local T, Expect, Eq = Harness.Test, Harness.Expect, Harness.Eq

local function R(path: string)
	return Harness.Require(path)
end

local GameConfig = R("ReplicatedStorage.Modules.GameConfig")
local EnemyData = R("ReplicatedStorage.Modules.EnemyData")
local WeaponData = R("ReplicatedStorage.Modules.WeaponData")
local UpgradeData = R("ReplicatedStorage.Modules.UpgradeData")
local CharacterData = R("ReplicatedStorage.Modules.CharacterData")
local MetaData = R("ReplicatedStorage.Modules.MetaData")
local AchievementData = R("ReplicatedStorage.Modules.AchievementData")
local WaveData = R("ReplicatedStorage.Modules.WaveData")
local MonetizationData = R("ReplicatedStorage.Modules.MonetizationData")
local Protocol = R("ReplicatedStorage.Modules.Protocol")
local Stats = R("ReplicatedStorage.Modules.Stats")
local Format = R("ReplicatedStorage.Modules.Util.Format")
local SpatialGrid = R("ServerScriptService.Server.Sim.SpatialGrid")
local Run = R("ServerScriptService.Server.Sim.Run")
local LevelUp = R("ServerScriptService.Server.Sim.LevelUp")
local Defaults = R("ServerScriptService.Server.Data.Defaults")

---------------------------------------------------------------------------
Harness.Section("data")
---------------------------------------------------------------------------
T("at least 10 regular enemies and 4 bosses", function()
	local regular, bosses = 0, 0
	for _, def in EnemyData.List do
		if def.Boss or def.MiniBoss then
			bosses += 1
		elseif def.Collection and not def.Secret and not def.Rare then
			regular += 1
		end
	end
	Expect(regular >= 7, "regular " .. regular)
	Expect(#EnemyData.List >= 10)
	Expect(bosses >= 4, "bosses " .. bosses)
end)

T("every enemy has complete stats", function()
	for _, def in EnemyData.List do
		for _, field in { "HP", "Speed", "Damage", "XP", "Radius", "Scale", "Mass", "CoinChance", "ItemChance" } do
			Expect(type(def[field]) == "number", def.Key .. "." .. field)
		end
		Expect(def.HP > 0 and def.Radius > 0 and def.Mass > 0, def.Key)
		Expect(type(def.Model) == "string" and type(def.Behavior) == "string", def.Key)
		Expect(typeof(def.Color) == "Color3" and typeof(def.Accent) == "Color3", def.Key)
		if def.Behavior == "Boss" then
			Expect(def.Params.Title and #def.Params.Patterns > 0, def.Key .. " boss params")
		end
		if def.Params.SplitInto then
			Expect(EnemyData.ByKey[def.Params.SplitInto], def.Key .. " split target")
		end
		if def.Params.SummonKey then
			Expect(EnemyData.ByKey[def.Params.SummonKey], def.Key .. " summon target")
		end
	end
	Expect(#EnemyData.List < 256, "enemy ids fit in a byte")
end)

T("12 weapons with contiguous levels", function()
	Eq(#WeaponData.List, 12, "weapon count")
	for _, def in WeaponData.List do
		Expect(def.Icon ~= "" and def.Name ~= "" and def.Desc ~= "", def.Key)
		Expect(def.Base.Damage and def.Base.Cooldown, def.Key .. " base")
		for level = 2, def.MaxLevel do
			local l = def.Levels[level]
			Expect(l and type(l.Desc) == "string", def.Key .. " level " .. level)
		end
		Expect(def.Unlock.Default or def.Unlock.Cost or def.Unlock.Achievement, def.Key .. " unlock")
		if def.Unlock.Achievement then
			Expect(AchievementData.ByKey[def.Unlock.Achievement], def.Key .. " unlock achievement")
		end
		local raw = WeaponData.RawStats(def.Key, def.MaxLevel)
		Expect(raw.Damage > def.Base.Damage or (raw.Amount or 0) > (def.Base.Amount or 0), def.Key .. " gets stronger")
	end
end)

T("characters: start weapons and unlocks exist", function()
	for _, def in CharacterData.List do
		Expect(WeaponData.ByKey[def.StartWeapon], def.Key .. " start weapon")
		if def.Unlock.Achievement then
			Expect(AchievementData.ByKey[def.Unlock.Achievement], def.Key .. " unlock achievement")
		end
		for stat in def.Stats do
			Expect(Stats.Known[stat], def.Key .. " stat " .. stat)
		end
	end
	Expect(CharacterData.ByKey[CharacterData.Default].Unlock.Default)
end)

T("passives / meta upgrades use known stats", function()
	for _, def in UpgradeData.Passives do
		Expect(Stats.Known[def.Stat], def.Key)
	end
	for _, def in MetaData.Upgrades do
		Expect(Stats.Known[def.Stat], def.Key)
		Eq(#def.Costs, def.MaxLevel, def.Key .. " costs")
		for i = 2, #def.Costs do
			Expect(def.Costs[i] > def.Costs[i - 1], def.Key .. " costs grow")
		end
	end
end)

T("timeline is ordered and every mix key exists", function()
	local last = -1
	for _, entry in WaveData.Timeline do
		Expect(entry.At > last, "order")
		last = entry.At
		for key in entry.Mix do
			Expect(EnemyData.ByKey[key], "mix " .. key)
		end
		if entry.Burst then
			Expect(EnemyData.ByKey[entry.Burst.Key], "burst")
		end
		if entry.Boss and entry.Boss ~= "Mid" then
			Expect(EnemyData.ByKey[entry.Boss].Boss or EnemyData.ByKey[entry.Boss].MiniBoss, "boss")
		end
	end
	Expect(WaveData.HPScale(600) > WaveData.HPScale(60))
end)

T("run structure: mini boss 5:00, boss 10:00, final ~13:00", function()
	local bosses = {}
	for _, entry in WaveData.Timeline do
		if entry.Boss then
			bosses[entry.At] = entry.Boss
		end
	end
	Eq(bosses[300], "GiantBrainrot")
	Eq(bosses[600], "Mid")
	Eq(bosses[780], "FinalGoober")
end)

T("achievements and quests are well formed", function()
	local keys = {}
	for _, def in AchievementData.List do
		Expect(not keys[def.Key], "duplicate " .. def.Key)
		keys[def.Key] = true
		Expect(def.Stat or def.Run or def.Flag, def.Key .. " condition")
		Expect(def.Coins > 0, def.Key .. " reward")
	end
	for _, def in AchievementData.Quests do
		Expect(def.Goal > 0 and def.Coins > 0, def.Key)
	end
end)

T("skins: unlock paths exist", function()
	local SkinData = R("ReplicatedStorage.Modules.SkinData")
	for _, def in SkinData.List do
		Expect(def.Default or def.Cost or def.Achievement, def.Key)
		if def.Achievement then
			Expect(AchievementData.ByKey[def.Achievement], def.Key .. " achievement")
		end
	end
end)

T("monetization: no pay-to-win items", function()
	for _, def in MonetizationData.Passes do
		Expect(not string.find(string.lower(def.Desc), "damage"), def.Key)
		Expect(def.Price > 0, def.Key)
	end
	for _, def in MonetizationData.Products do
		Expect(def.Price > 0, def.Key)
	end
end)

T("XP curve grows", function()
	for level = 1, 100 do
		Expect(GameConfig.XPNeeded(level + 1) >= GameConfig.XPNeeded(level), "level " .. level)
	end
	Eq(GameConfig.XPNeeded(1), 5, "first level is quick")
end)

---------------------------------------------------------------------------
Harness.Section("protocol")
---------------------------------------------------------------------------
T("every record round-trips", function()
	local w = Protocol.NewWriter(16) -- tiny: forces growth
	local sent = {}
	local samples = { u8 = 200, u16 = 60000, u32 = 3000000000, i16 = -1234, f32 = 123.5, q = -123.45, a = 1.5, s = 42.42, v = -12.34 }
	for name, record in Protocol.Records do
		local args = {}
		for i, kind in record.Fields do
			args[i] = samples[kind]
		end
		Protocol.Write(w, name, table.unpack(args))
		table.insert(sent, { Name = name, Args = args })
	end
	local frame = Protocol.Finish(w)
	local got = {}
	local handlers = {}
	for name in Protocol.Records do
		handlers[name] = function(...)
			table.insert(got, { Name = name, Args = { ... } })
		end
	end
	Expect(Protocol.Decode(frame, handlers), "decode")
	Eq(#got, #sent, "record count")
	for i, s in sent do
		Eq(got[i].Name, s.Name)
		for j, v in s.Args do
			local tolerance = if Protocol.Records[s.Name].Fields[j] == "a" then 0.001 elseif Protocol.Records[s.Name].Fields[j] == "f32" then 0.01 else 0.011
			Expect(math.abs(got[i].Args[j] - v) <= tolerance, s.Name .. "#" .. j .. " " .. tostring(got[i].Args[j]) .. " vs " .. v)
		end
	end
end)

T("values are clamped, never corrupt the stream", function()
	local w = Protocol.NewWriter()
	Protocol.Write(w, "Pos", 70000, 9999, -9999)
	Protocol.Write(w, "Hit", 5, 0 / 0, 1)
	Protocol.Write(w, "Coin", 3)
	local n = 0
	Expect(Protocol.Decode(Protocol.Finish(w), {
		Pos = function(id, x, z)
			Eq(id, 65535)
			Expect(x > 327 and z < -327)
			n += 1
		end,
		Hit = function(_, dmg)
			Eq(dmg, 0, "nan damage -> 0")
			n += 1
		end,
		Coin = function(c)
			Eq(c, 3)
			n += 1
		end,
	}))
	Eq(n, 3)
end)

T("truncated / garbage frames are rejected safely", function()
	local w = Protocol.NewWriter()
	Protocol.Write(w, "Spawn", 1, 1, 0, 0, 0)
	local frame = Protocol.Finish(w)
	local cut = buffer.create(buffer.len(frame) - 2)
	buffer.copy(cut, 0, frame, 0, buffer.len(cut))
	Expect(not Protocol.Decode(cut, {}), "truncated")
	local junk = buffer.create(4)
	buffer.writeu8(junk, 0, 250)
	Expect(not Protocol.Decode(junk, {}), "unknown record")
	Expect(not Protocol.Decode("not a buffer" :: any, {}), "wrong type")
end)

---------------------------------------------------------------------------
Harness.Section("stats")
---------------------------------------------------------------------------
T("base stats", function()
	local s = Stats.Compute({})
	Eq(s.MaxHP, GameConfig.Player.BaseHP)
	Eq(s.WalkSpeed, GameConfig.Player.BaseWalkSpeed)
	Eq(s.WeaponSlots, GameConfig.Player.MaxWeapons)
end)

T("bonuses stack and clamp", function()
	local s = Stats.Compute({ { Might = 0.5, MoveSpeed = 5, Cooldown = 5, MaxHPMult = -10 }, { Might = 0.25 } })
	Expect(math.abs(s.Might - 1.75) < 1e-9)
	Eq(s.WalkSpeed, GameConfig.Player.MaxWalkSpeed, "walk speed capped")
	Expect(s.CooldownMult >= 0.2, "cooldown floor")
	Expect(s.MaxHP >= 10, "hp floor")
	local bad = Stats.Compute({ { Might = 0 / 0, Area = math.huge, Nonsense = 5 } })
	Eq(bad.Might, 1, "nan ignored")
	Eq(bad.Area, 1, "inf ignored")
end)

T("weapon stats scale with player stats", function()
	local base = Stats.Compute({})
	local strong = Stats.Compute({ { Might = 1, Area = 0.5, Amount = 1 } })
	local a = Stats.Weapon("BrainBlast", 1, false, base)
	local b = Stats.Weapon("BrainBlast", 1, false, strong)
	Expect(b.Damage == a.Damage * 2, "might")
	Expect(b.Amount == a.Amount + 1, "amount")
	local aura = Stats.Weapon("SigmaAura", 1, false, strong)
	Eq(aura.Amount, 1, "NoAmount weapons ignore amount")
	local awakened = Stats.Weapon("BrainBlast", 7, true, base)
	local normal = Stats.Weapon("BrainBlast", 7, false, base)
	Expect(awakened.Damage > normal.Damage and awakened.Amount > normal.Amount, "awaken")
end)

---------------------------------------------------------------------------
Harness.Section("save data")
---------------------------------------------------------------------------
T("defaults are valid", function()
	local d = Defaults.New()
	Eq(d.Coins, 0)
	Expect(d.Characters.Goober and not d.Characters.Sigma)
	Expect(d.Weapons.BrainBlast and not d.Weapons.FinalAura)
	Eq(d.Selected, "Goober")
end)

T("reconcile repairs garbage", function()
	local d = Defaults.Reconcile({
		Coins = 0 / 0,
		BrainXP = -50,
		Selected = "Sigma", -- not unlocked
		Characters = { Sigma = "yes", FakeGuy = true },
		Weapons = { FinalAura = true, Nope = true },
		Meta = { Might = 99, Hacks = 5 },
		Stats = { Kills = math.huge, BestTime = "7" },
		Settings = { Sfx = "loud", Shake = false },
		Quests = { Day = 5, List = { { Key = "Kill300", Progress = 10 }, { Key = "Bogus" }, "x" } },
		Receipts = { "a", 5, "b" },
		StudioPasses = { VIP = true, Hack = true },
		Extra = { junk = true },
	})
	Eq(d.Coins, 0, "nan coins")
	Eq(d.BrainXP, 0, "negative xp")
	Eq(d.Selected, "Goober", "locked selection")
	Expect(d.Characters.Sigma == false and d.Characters.FakeGuy == nil)
	Expect(d.Weapons.FinalAura == true and d.Weapons.Nope == nil)
	Eq(d.Meta.Might, MetaData.ByKey.Might.MaxLevel, "meta clamped")
	Expect(d.Meta.Hacks == nil)
	Expect(d.Stats.Kills <= 1e12 and d.Stats.BestTime == 0)
	Expect(d.Settings.Sfx == true and d.Settings.Shake == false)
	Eq(#d.Quests.List, 1, "only valid quests")
	Eq(#d.Receipts, 2, "only string receipts")
	Expect(d.StudioPasses.VIP == true and d.StudioPasses.Hack == nil)
	Expect(d.Extra == nil, "unknown keys dropped")
end)

T("reconcile is idempotent", function()
	local a = Defaults.Reconcile({ Coins = 50, Meta = { Might = 2 } })
	local b = Defaults.Reconcile(a)
	Eq(b.Coins, 50)
	Eq(b.Meta.Might, 2)
end)

---------------------------------------------------------------------------
Harness.Section("level up offers")
---------------------------------------------------------------------------
local function unlockedAll()
	local u = {}
	for _, def in WeaponData.List do
		u[def.Key] = true
	end
	return u
end

T("offers have distinct, valid cards", function()
	for seed = 1, 50 do
		local run = Run.new({ Seed = seed, Unlocked = unlockedAll() })
		run.Level = 30
		for _ = 1, 20 do
			local cards = LevelUp.Build(run, "Level")
			Eq(#cards, 3, "card count")
			local seen = {}
			for _, card in cards do
				Expect(not seen[card.Id], "duplicate " .. card.Id)
				seen[card.Id] = true
				Expect(card.Title and card.Desc and card.Icon, card.Id)
			end
			LevelUp.Apply(run, cards[run.Rng:NextInteger(1, #cards)])
		end
		Expect(#run.Weapons <= run.Stats.WeaponSlots, "slots respected")
	end
end)

T("Brainrot sees 4 cards", function()
	local run = Run.new({ Seed = 3, Character = "Brainrot", Unlocked = unlockedAll() })
	Eq(#LevelUp.Build(run, "Level"), 4)
end)

T("locked weapons are never offered", function()
	local run = Run.new({ Seed = 9, Unlocked = { BrainBlast = true } })
	for _ = 1, 40 do
		for _, card in LevelUp.Build(run, "Level") do
			Expect(card.Type ~= "Weapon", "offered " .. card.Key)
		end
	end
end)

T("maxed build falls back to filler cards", function()
	local run = Run.new({ Seed = 4, Unlocked = { BrainBlast = true } })
	run:GetWeapon("BrainBlast").Level = 7
	run:GetWeapon("BrainBlast").Awakened = true
	for _, def in UpgradeData.Passives do
		run.Passives[def.Key] = def.MaxStacks
	end
	for _, def in UpgradeData.Rares do
		run.Rares[def.Key] = def.MaxStacks
	end
	local cards = LevelUp.Build(run, "Level")
	for _, card in cards do
		Eq(card.Type, "Filler")
	end
end)

T("choose validates the index", function()
	local run = Run.new({ Seed = 5, Unlocked = unlockedAll() })
	run.PendingLevels = 1
	LevelUp.OpenNext(run)
	Expect(run.Offer ~= nil)
	Expect(not run:Choose(0) and not run:Choose(4) and not run:Choose(1.5) and not run:Choose("1" :: any))
	Expect(run.Offer ~= nil, "still open")
	Expect(run:Choose(2))
	Expect(run.Offer == nil and run.PendingLevels == 0)
end)

T("reroll spends a reroll, skip closes", function()
	local run = Run.new({ Seed = 6, Unlocked = unlockedAll() })
	run.PendingLevels = 2
	LevelUp.OpenNext(run)
	local rerolls = run.Rerolls
	Expect(run:RerollOffer())
	Eq(run.Rerolls, rerolls - 1)
	Expect(run:SkipOffer())
	Expect(run.Offer ~= nil, "second pending level opens")
	Expect(run:SkipOffer())
	Expect(run.Offer == nil)
end)

---------------------------------------------------------------------------
Harness.Section("simulation")
---------------------------------------------------------------------------
T("spatial grid finds neighbours", function()
	local grid = SpatialGrid.new(8)
	local items = {}
	for i = 1, 100 do
		local it = { X = (i % 10) * 5 - 25, Z = (i // 10) * 5 - 25 }
		items[i] = it
		SpatialGrid.Insert(grid, it, it.X, it.Z)
	end
	local out = {}
	local n = SpatialGrid.Query(grid, 0, 0, 6, out)
	local found = 0
	for i = 1, n do
		local it = out[i]
		if it.X * it.X + it.Z * it.Z <= 36 then
			found += 1
		end
	end
	local expected = 0
	for _, it in items do
		if it.X * it.X + it.Z * it.Z <= 36 then
			expected += 1
		end
	end
	Eq(found, expected, "exact neighbours")
	SpatialGrid.Clear(grid)
	Eq(SpatialGrid.Query(grid, 0, 0, 50, out), 0, "cleared")
end)

T("every character survives the first minute headless", function()
	for _, def in CharacterData.List do
		local run = Run.new({ Seed = 11, Character = def.Key, Unlocked = unlockedAll() })
		for _ = 1, 60 * 20 do
			Bot.Step(run, 1 / 20, 1)
			if run.Steps % 2 == 0 then
				run:Flush()
				run:TakeEvents()
			end
		end
		Expect(run.Kills > 20, def.Key .. " kills " .. run.Kills)
		Expect(run.Level >= 3, def.Key .. " level " .. run.Level)
		Expect(not run.Ended, def.Key .. " died in the first minute")
	end
end)

T("first level up comes in the first 15 seconds", function()
	local run = Run.new({ Seed = 21, Unlocked = unlockedAll() })
	local at = nil
	for _ = 1, 30 * 20 do
		Bot.Step(run, 1 / 20, 1)
		if not at and run.Level >= 2 then
			at = run.Time
		end
	end
	Expect(at and at < 15, "first level at " .. tostring(at))
end)

T("time can jump (debug) and bosses appear", function()
	local run = Run.new({ Seed = 31, Unlocked = unlockedAll(), MidBoss = "King67" })
	run.Time = 598
	for _ = 1, 6 * 20 do
		Bot.Step(run, 1 / 20, 1)
	end
	Expect(run.Boss and run.Boss.Key == "King67", "mid boss")
end)

T("dead run offers a revive window, then ends", function()
	local run = Run.new({ Seed = 41, Unlocked = unlockedAll() })
	run:HurtPlayer(1e6, true)
	Expect(run.Dead and not run.Ended)
	for _ = 1, (GameConfig.Run.DeathReviveWindow + 2) * 20 do
		run:Step(1 / 20)
	end
	Expect(run.Ended and run.EndReason == "Death")
end)

T("free revive is used automatically", function()
	local run = Run.new({ Seed = 42, Unlocked = unlockedAll(), Meta = { Revive = 1 } })
	Eq(run.Revives, 1)
	run:HurtPlayer(1e6, true)
	Expect(not run.Dead and run.HP > 0 and run.Revives == 0)
end)

---------------------------------------------------------------------------
Harness.Section("format")
---------------------------------------------------------------------------
T("numbers and times", function()
	Eq(Format.Time(125), "2:05")
	Eq(Format.Time(-5), "0:00")
	Eq(Format.Number(999), "999")
	Eq(Format.Number(1234), "1.23K")
	Eq(Format.Number(15600000), "15.6M")
	Eq(Format.Commas(1234567), "1,234,567")
	Eq(Format.Number(0 / 0), "0")
end)

process.exit(if Harness.Finish() then 0 else 1)
