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
local HeroData = R("ReplicatedStorage.Modules.HeroData")
local HeroModels = R("ReplicatedStorage.Modules.HeroModels")
local CosmeticData = R("ReplicatedStorage.Modules.CosmeticData")
local CollectionData = R("ReplicatedStorage.Modules.CollectionData")
local LiveEvents = R("ReplicatedStorage.Modules.LiveEvents")
local Rarity = R("ReplicatedStorage.Modules.Rarity")
local MetaData = R("ReplicatedStorage.Modules.MetaData")
local AchievementData = R("ReplicatedStorage.Modules.AchievementData")
local WaveData = R("ReplicatedStorage.Modules.WaveData")
local MonetizationData = R("ReplicatedStorage.Modules.MonetizationData")
local DifficultyData = R("ReplicatedStorage.Modules.DifficultyData")
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
T("15 horde enemies, specials and 8 bosses", function()
	local regular, bosses = 0, 0
	local models = {}
	for _, def in EnemyData.List do
		if def.Boss or def.MiniBoss then
			bosses += 1
		elseif def.Collection and not def.Secret and not def.Rare then
			regular += 1
		end
		models[def.Model] = true
	end
	Expect(regular >= 15, "regular " .. regular)
	Expect(bosses >= 8, "bosses " .. bosses)
	local n = 0
	for _ in models do
		n += 1
	end
	Expect(n >= 24, "distinct enemy models " .. n)
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

T("every boss pattern has its timing numbers", function()
	local EVERY = { Slam = "SlamEvery", DoubleSlam = "SlamEvery", Dash = "DashEvery", Ring = "RingEvery", Spiral = "SpiralEvery", Summon = "SummonEvery", Rain = "RainEvery", Leap = "LeapEvery", Teleport = "TeleportEvery", Barrage = "BarrageEvery", Sweep = "SweepEvery", Hazard = "HazardEvery" }
	for _, def in EnemyData.List do
		if def.Behavior == "Boss" then
			local patterns = table.clone(def.Params.Patterns)
			for _, extra in def.Params.EnragePatterns or {} do
				table.insert(patterns, extra)
			end
			for _, pattern in patterns do
				Expect(EVERY[pattern] and def.Params[EVERY[pattern]], def.Key .. " " .. pattern)
			end
		end
	end
end)

T("30 abilities + 12 evolutions with contiguous levels", function()
	local base, evo = 0, 0
	local categories = {}
	for _, def in WeaponData.List do
		Expect(def.Name ~= "" and def.Desc ~= "", def.Key)
		Expect(Rarity.Index[def.Rarity], def.Key .. " rarity")
		Expect(def.Base.Cooldown or def.Kind == "Allies", def.Key .. " base")
		if def.Evolution then
			evo += 1
			Eq(def.Rarity, "Mythic", def.Key .. " evolutions are mythic")
			Expect(WeaponData.ByKey[def.Evolution.From] and WeaponData.ByKey[def.Evolution.From].Evolution == nil, def.Key .. " from")
			Expect(UpgradeData.PassiveByKey[def.Evolution.With], def.Key .. " with")
		else
			base += 1
			categories[def.Category] = true
			for level = 2, def.MaxLevel do
				local l = def.Levels[level]
				Expect(l and type(l.Desc) == "string", def.Key .. " level " .. level)
			end
			Expect(def.Unlock.Default or def.Unlock.Fragments or def.Unlock.Achievement or def.Unlock.Secret, def.Key .. " unlock")
			if def.Unlock.Achievement then
				Expect(AchievementData.ByKey[def.Unlock.Achievement], def.Key .. " unlock achievement")
			end
		end
	end
	Expect(base >= 30, "abilities " .. base)
	Expect(evo >= 12, "evolutions " .. evo)
	for _, cat in WeaponData.Categories do
		Expect(categories[cat], "category " .. cat)
	end
	Expect(#WeaponData.List < 256, "ids fit in a byte")
end)

T("every ability kind has a simulation function", function()
	local CombatManager = R("ServerScriptService.Server.Sim.CombatManager")
	for _, def in WeaponData.List do
		Expect(CombatManager.Kinds[def.Kind], def.Key .. " kind " .. def.Kind)
	end
end)

T("15 heroes: models, start abilities, mechanics, unlocks", function()
	Expect(#HeroData.List >= 15, "heroes " .. #HeroData.List)
	local mechanics = {}
	for _, def in HeroData.List do
		Expect(HeroModels.Heroes[def.Key], def.Key .. " model")
		Expect(WeaponData.IsBase(def.StartWeapon), def.Key .. " start ability")
		Expect(Rarity.Index[def.Rarity], def.Key .. " rarity")
		Expect(not mechanics[def.Mechanic], def.Key .. " mechanic is unique")
		mechanics[def.Mechanic] = true
		Expect(def.Unlock.Default or def.Unlock.Fragments or def.Unlock.Achievement, def.Key .. " unlock")
		if def.Unlock.Achievement then
			Expect(AchievementData.ByKey[def.Unlock.Achievement], def.Key .. " unlock achievement")
		end
		for stat in def.Stats do
			Expect(Stats.Known[stat], def.Key .. " stat " .. stat)
		end
	end
	Expect(HeroData.ByKey[HeroData.Default].Unlock.Default)
end)

T("hero models: smooth shapes, few parts, restrained neon, limbs, own colours", function()
	local looks = {}
	for _, def in HeroData.List do
		local hero = HeroModels.Heroes[def.Key]
		local rounded, neon, limbs = 0, 0, {}
		for _, p in hero.Pieces do
			if p.Mesh == "Sphere" or p.Shape ~= nil then
				rounded += 1
			end
			if p.Role == "Glow" or (p.Material and p.Material.Name == "Neon") then
				neon += 1
			end
			if p.Limb then
				limbs[p.Limb] = true
			end
		end
		local n = #hero.Pieces
		Expect(rounded / n >= (if hero.Voxel then 0.4 else 0.6), string.format("%s rounded shapes %d/%d", def.Key, rounded, n))
		Expect(n <= 34, def.Key .. " few shapes: " .. n)
		Expect(neon <= 6, def.Key .. " neon only on energy parts: " .. neon)
		Expect(limbs.ArmL and limbs.ArmR, def.Key .. " arms swing")
		Expect(type(hero.Top) == "number" and hero.HatAt ~= nil, def.Key .. " top / hat spot")
		local p = hero.Palette.Primary
		local key = string.format("%d,%d,%d", p.R * 255, p.G * 255, p.B * 255)
		Expect(not looks[key], def.Key .. " has its own main colour")
		looks[key] = true
	end
	for name, hat in HeroModels.Hats do
		Expect(#hat <= 10, "hat " .. name .. " stays simple")
	end
end)

T("monetization: prices and ids untouched, SUPPORT is a donation, missing ids are listed", function()
	local M = R("ReplicatedStorage.Modules.MonetizationData")
	local prices = { VIPCosmetics = 249, CosmeticPass = 299, ExtraLoadout = 149, ExtraHeroSlot = 149, AfkCapacity = 99, Revive = 25, ExtraReroll = 10, ExtraChest = 29, CosmeticBoost = 19, AfkBoost = 39 }
	for key, price in prices do
		local def = M.PassByKey[key] or M.ProductByKey[key]
		Expect(def ~= nil and def.Price == price, key .. " price")
	end
	for _, key in { "Support1", "Support2", "Support3" } do
		local def = M.ProductByKey[key]
		Expect(def and def.Donation == true, key .. " is a donation")
		Expect(not M.Available(def, false) and M.Available(def, true), key .. ": live needs an id, Studio can test")
	end
	Expect(#M.Unconfigured() == #M.Passes + #M.Products, "every item without an id is reported")
end)

T("difficulty: 7 tiers, each harder and paying more, rules added step by step", function()
	Eq(DifficultyData.Count, 7, "tiers")
	for i, tier in DifficultyData.List do
		Eq(tier.Index, i, tier.Key .. " index")
		if i > 1 then
			local before = DifficultyData.List[i - 1]
			Expect(tier.EnemyHP > before.EnemyHP and tier.EnemyDamage > before.EnemyDamage and tier.BossHP > before.BossHP, tier.Key .. " harder")
			Expect(tier.Reward > before.Reward and tier.FirstClear.Coins > before.FirstClear.Coins, tier.Key .. " pays more")
			Expect(tier.Unlock and tier.Unlock.Tier == i - 1, tier.Key .. " opens from the tier before")
			for _, m in before.Mods do
				Expect(table.find(tier.Mods, m), tier.Key .. " keeps " .. m)
			end
		end
		for _, m in tier.Mods do
			Expect(DifficultyData.Modifiers[m], tier.Key .. " rule " .. m)
		end
	end
	Eq(#DifficultyData.List[1].Mods + #DifficultyData.List[2].Mods, 0, "the first tiers have no special rules")
	Eq(#DifficultyData.List[7].Mods, 8, "THE 67 has every rule")
end)

T("difficulty: the unlock chain and titles", function()
	local best = {}
	for i = 1, 7 do
		best[i] = { Time = 0, Bosses = 0, Wins = 0 }
	end
	Eq(DifficultyData.Unlocked(best), 1, "new")
	best[1].Bosses = 1
	Eq(DifficultyData.Unlocked(best), 2, "a boss on CALM")
	best[2].Time = 599
	Eq(DifficultyData.Unlocked(best), 2, "almost 10 minutes")
	best[2].Time = 600
	Eq(DifficultyData.Unlocked(best), 3, "10 minutes on HUNT")
	best[3].Wins = 1
	Eq(DifficultyData.Unlocked(best), 4, "won HORDE")
	best[5].Wins = 1
	Eq(DifficultyData.Unlocked(best), 4, "tiers open in order")
	Eq(DifficultyData.TitleFor(3), nil, "no title below NIGHTMARE")
	Eq(DifficultyData.TitleFor(5), "Inferno Walker", "title")
	Eq(DifficultyData.NewMods(5)[1], "Chaos", "new rules of INFERNO")
end)

T("difficulty: a run scales the horde, bosses and rules", function()
	local EM = R("ServerScriptService.Server.Sim.EnemyManager")
	local calm = Run.new({ Seed = 5, Difficulty = 1 })
	local top = Run.new({ Seed = 5, Difficulty = 7 })
	local classic = Run.new({ Seed = 5 })
	Eq(classic.Difficulty, 2, "the default is the classic tier")
	local a = EM.Spawn(calm, "Husk", 30, 0)
	local b = EM.Spawn(top, "Husk", 30, 0)
	local c = EM.Spawn(classic, "Husk", 30, 0)
	local tiers = DifficultyData.List
	Expect(tiers[1].EnemyHP < 1 and tiers[7].EnemyHP > 2, "CALM softer, THE 67 much tougher")
	Expect(math.abs(a.HP / c.HP - tiers[1].EnemyHP) < 1e-6, "CALM enemy health")
	Expect(math.abs(b.HP / c.HP - tiers[7].EnemyHP) < 1e-6, "THE 67 enemy health")
	Expect(b.Damage > c.Damage and a.Damage < c.Damage, "enemy damage")
	Expect(b.Speed > c.Speed and a.Speed == c.Speed, "FASTER HORDE only with the rule")
	Expect(top.Mods.Glitch and top.Mods.NoMercy and not calm.Mods.Glitch, "rules")
	Expect(top.Windup < 1 and calm.Windup == 1, "NO MERCY wind-ups")
	Expect(top.Stats.Luck > classic.Stats.Luck, "harder tiers: more luck")
	local boss = EM.Spawn(top, "TheGiant", 40, 0, { Force = true })
	local extra = boss.Def.Params.EnragePatterns and boss.Def.Params.EnragePatterns[1]
	if extra then
		Expect(table.find(boss.Patterns, extra), "BOSS RAGE adds " .. extra .. " from the start")
	end
	local calmBoss = EM.Spawn(calm, "TheGiant", 40, 0, { Force = true })
	Expect(math.abs(boss.MaxHP / calmBoss.MaxHP - tiers[7].BossHP / tiers[1].BossHP) < 1e-6, "boss health scales")
	Eq(tiers[2].Reward, 1, "HUNT pays like the classic game")
	-- a few minutes on the top tier stay error free (glitch, chaos, no mercy)
	top.Invulnerable = 1e9
	for _ = 1, 20 * 150 do
		top:Step(0.05)
		if top.Offer then
			top:Choose(1)
		end
	end
	Expect(top.Kills > 0 and not top.Ended, "THE 67 simulates")
end)

T("difficulty: old profiles keep what they could play", function()
	local old = Defaults.Reconcile({ Stats = { Bosses = 3, BestTime = 700, Wins = 1, Runs = 9 } })
	Eq(DifficultyData.Unlocked(old.Difficulty.Best), 3, "HUNT (bosses) and HORDE (10 minutes) open")
	Eq(old.Difficulty.Selected, 2, "they keep the classic tier selected")
	Eq(old.Stats.HighestWin, 2, "their win counts as a HUNT win")
	Eq(old.Difficulty.Cleared[2], true, "first clear already paid")
	local fresh = Defaults.New()
	Eq(fresh.Difficulty.Selected, 1, "new players start on CALM")
	Eq(DifficultyData.Unlocked(fresh.Difficulty.Best), 1, "only CALM open")
	local again = Defaults.Reconcile(fresh)
	Eq(#again.Difficulty.Best, 7, "reconcile keeps the table")
end)

T("passives / meta upgrades use known stats", function()
	for _, def in UpgradeData.Passives do
		for _, level in def.Levels do
			for stat in level.Stats or {} do
				Expect(Stats.Known[stat], def.Key .. " " .. stat)
			end
		end
		Expect(Rarity.Index[def.Rarity], def.Key .. " rarity")
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
		for key in entry.Pack or {} do
			Expect(EnemyData.ByKey[key], "pack " .. key)
		end
		if entry.Burst then
			Expect(EnemyData.ByKey[entry.Burst.Key], "burst")
		end
		Expect(entry.Boss == nil, "bosses come from BossData, not the wave timeline")
	end
	Expect(WaveData.HPScale(600) > WaveData.HPScale(60))
end)

T("run structure: 15 minutes, bosses at 3, 6, 9, 12, THE FINAL ONE at 15", function()
	local BossData = R("ReplicatedStorage.Modules.BossData")
	local times = {}
	for _, slot in BossData.Slots do
		table.insert(times, slot.At)
	end
	Eq(table.concat(times, ","), "180,360,540,720")
	Eq(BossData.Main.At, 900)
	Eq(GameConfig.Run.FinalBossAt, BossData.Main.At, "config agrees")
	Expect(GameConfig.Run.Length > BossData.Main.At, "time for the fight")
	-- the horde thins out around every boss so the walk to its lair stays readable
	for _, at in { 170, 350, 530, 710, 890 } do
		local _, entry = WaveData.EntryAt(at + 1)
		local _, before = WaveData.EntryAt(at - 1)
		Expect(entry.Rate < before.Rate, "calmer before the boss at " .. at)
	end
end)

T("8 rare 67 events", function()
	Expect(#WaveData.Events >= 8)
	for _, e in WaveData.Events do
		Expect(e.Weight > 0 and e.Duration > 0 and e.Title ~= "", e.Key)
	end
	local total = 0
	for _, e in WaveData.Events do
		total += e.Weight
	end
	Expect(WaveData.EventByKey.The67.Weight / total < 0.05, "THE 67 is very rare")
	Expect(WaveData.EventGap[1] >= 60, "67 events are rare")
end)

T("achievements, quests and weekly challenges are well formed", function()
	local keys = {}
	for _, def in AchievementData.List do
		Expect(not keys[def.Key], "duplicate " .. def.Key)
		keys[def.Key] = true
		Expect(def.Stat or def.Run or def.Flag, def.Key .. " condition")
		Expect(def.Coins > 0, def.Key .. " reward")
		if def.Stat then
			Expect(table.find(Defaults.StatKeys, def.Stat), def.Key .. " stat " .. def.Stat)
		end
	end
	for _, def in AchievementData.Quests do
		Expect(def.Goal > 0 and def.Coins > 0, def.Key)
	end
	for _, def in AchievementData.Weekly do
		Expect(def.Goal > 0 and def.Coins > 0 and (def.Fragments or 0) > 0, def.Key)
	end
	for _, key in AchievementData.Secrets do
		Expect(AchievementData.ByKey[key], "secret " .. key)
	end
end)

T("cosmetics: every item has a way to get it and a default per category", function()
	local ids = {}
	for _, def in CosmeticData.List do
		Expect(not ids[def.Id], "duplicate " .. def.Id)
		ids[def.Id] = true
		Expect(def.Default or def.Cost or def.Achievement or def.Pass or def.Level or def.Collection, def.Id)
		if def.Achievement then
			Expect(AchievementData.ByKey[def.Achievement], def.Id .. " achievement")
		end
		if def.Pass then
			Expect(MonetizationData.PassByKey[def.Pass], def.Id .. " pass")
		end
		if def.Category == "Hat" then
			Expect(HeroModels.Hats[def.Style], def.Id .. " hat model")
		elseif def.Category == "HeroSkin" and def.Style ~= "Default" then
			Expect(HeroModels.Skins[def.Style], def.Id .. " skin palette")
		end
	end
	for _, cat in CosmeticData.Categories do
		Expect(CosmeticData.DefaultOf[cat.Key], cat.Key .. " default")
		Expect(#CosmeticData.ByCategory[cat.Key] >= 4, cat.Key .. " has choices")
	end
	Expect(#CosmeticData.Categories >= 12)
end)

T("collection book covers everything", function()
	Expect(CollectionData.Total >= 100, "total " .. CollectionData.Total)
	local n, total = CollectionData.Count(Defaults.New())
	Expect(n == 3 and total == CollectionData.Total, "a new profile owns the 3 starter heroes " .. n)
end)

T("live events follow the calendar", function()
	-- 2026-09-26 was a Saturday, 2026-09-25 a Friday, 2026-09-23 a Wednesday
	local saturday = os.time({ year = 2026, month = 9, day = 26, hour = 12 })
	local mods = LiveEvents.Mods(saturday)
	Eq(mods.EventRate, 2, "67 WEEKEND")
	local friday = os.time({ year = 2026, month = 9, day = 25, hour = 12 })
	Expect(LiveEvents.Mods(friday).CoinBonus == 0.25, "gold rush")
	local wednesday = os.time({ year = 2026, month = 9, day = 23, hour = 12 })
	Eq(#LiveEvents.Active(wednesday), 0, "nothing mid-week")
end)

T("rarity: legendary is rare, luck helps", function()
	Expect(Rarity.WeightFor("Legendary", 1) < Rarity.WeightFor("Rare", 1) / 4)
	Expect(Rarity.WeightFor("Legendary", 3) > Rarity.WeightFor("Legendary", 1) * 2)
	Eq(Rarity.WeightFor("Mythic", 5), 0, "mythic cards are never random")
end)

T("monetization: no pay-to-win items", function()
	for _, def in MonetizationData.Passes do
		local desc = string.lower(def.Desc)
		Expect(not string.find(desc, "damage") and not string.find(desc, "coins"), def.Key)
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

T("ability stats scale with player stats", function()
	local base = Stats.Compute({})
	local strong = Stats.Compute({ { Might = 1, Area = 0.5, Amount = 1 } })
	local a = Stats.Weapon("PulseBlast", 1, base)
	local b = Stats.Weapon("PulseBlast", 1, strong)
	Expect(b.Damage == a.Damage * 2, "might")
	Expect(b.Amount == a.Amount + 1, "amount")
	local aura = Stats.Weapon("SigmaAura", 1, strong)
	Eq(aura.Amount or 1, 1, "NoAmount abilities ignore amount")
	local burn = Stats.Weapon("FireRing", 1, Stats.Compute({ { Burn = 0.35 } }))
	Expect(burn.Burn > Stats.Weapon("FireRing", 1, base).Burn, "burn mastery")
end)

---------------------------------------------------------------------------
Harness.Section("save data")
---------------------------------------------------------------------------
T("defaults are valid", function()
	local d = Defaults.New()
	Eq(d.Coins, 0)
	Eq(d.Fragments, 0)
	Expect(d.Heroes.Rookie and d.Heroes.Runner and d.Heroes.Tank and not d.Heroes.Samurai)
	Expect(d.Weapons.BasicBlaster and not d.Weapons.Blast67 and d.Weapons.OverdriveBlaster == nil)
	Eq(d.Selected, "Rookie")
	Eq(d.Cosmetics.Equipped.Hat, "Hat.None")
	Eq(d.Afk.SlotCount, 1)
end)

T("reconcile repairs garbage and migrates version 1", function()
	local d = Defaults.Reconcile({
		Coins = 0 / 0,
		BrainXP = 500,
		Selected = "Samurai", -- not unlocked
		Heroes = { Samurai = "yes", FakeGuy = true },
		Weapons = { Meteor = true, Nope = true, OverdriveBlaster = true },
		Meta = { Might = 99, Hacks = 5 },
		Stats = { Kills = math.huge, BestTime = "7" },
		Settings = { Sfx = "loud", Shake = false },
		Quests = { Day = 5, List = { { Key = "Kill300", Progress = 10 }, { Key = "Bogus" }, "x" } },
		Receipts = { "a", 5, "b" },
		StudioPasses = { VIPCosmetics = true, Hack = true },
		Skins = { Cone = true },
		EquippedSkin = "Cone",
		Cosmetics = { Owned = { ["Aura.Void"] = "yes" }, Equipped = { Aura = "Aura.Void" } },
		Afk = { Since = -5, SlotCount = 99, Slots = { "Rookie", "Samurai", 5 } },
		Loadouts = { { Hero = "Samurai", StartWeapon = "Nope" } },
		Extra = { junk = true },
	})
	Eq(d.Coins, 0, "nan coins")
	Eq(d.XP, 500, "Brain XP migrated")
	Eq(d.Selected, "Rookie", "locked selection")
	Expect(d.Heroes.Samurai == false and d.Heroes.FakeGuy == nil)
	Expect(d.Weapons.Meteor == true and d.Weapons.Nope == nil and d.Weapons.OverdriveBlaster == nil)
	Eq(d.Meta.Might, MetaData.ByKey.Might.MaxLevel, "meta clamped")
	Expect(d.Meta.Hacks == nil)
	Expect(d.Stats.Kills <= 1e12 and d.Stats.BestTime == 0)
	Expect(d.Settings.Sfx == true and d.Settings.Shake == false)
	Eq(#d.Quests.List, 1, "only valid quests")
	Eq(#d.Receipts, 2, "only string receipts")
	Expect(d.StudioPasses.VIPCosmetics == true and d.StudioPasses.Hack == nil)
	Expect(d.Cosmetics.Owned["Hat.Cone"] == true and d.Cosmetics.Equipped.Hat == "Hat.Cone", "v1 hats migrated")
	Expect(d.Cosmetics.Owned["Aura.Void"] == nil and d.Cosmetics.Equipped.Aura == "Aura.None", "unowned cosmetics dropped")
	Expect(d.Afk.Since == 0 and d.Afk.SlotCount == #GameConfig.Afk.SlotCosts and d.Afk.Slots[1] == "Rookie" and d.Afk.Slots[2] == "", "afk repaired")
	Expect(d.Loadouts[1].Hero == "Rookie" and d.Loadouts[1].StartWeapon == "", "loadout repaired")
	Expect(d.Extra == nil, "unknown keys dropped")
end)

T("reconcile is idempotent", function()
	local a = Defaults.Reconcile({ Coins = 50, Meta = { Might = 2 }, Fragments = 7 })
	local b = Defaults.Reconcile(a)
	Eq(b.Coins, 50)
	Eq(b.Fragments, 7)
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
				Expect(card.Title and card.Desc and card.Rarity, card.Id)
			end
			LevelUp.Apply(run, cards[run.Rng:NextInteger(1, #cards)])
		end
		Expect(#run.Weapons <= run.Stats.WeaponSlots, "slots respected")
	end
end)

T("THE LUCKY gets 4 cards from chests, 67 chests give 4", function()
	local run = Run.new({ Seed = 3, Hero = "Lucky", Unlocked = unlockedAll() })
	Eq(#LevelUp.Build(run, "Chest"), 4)
	local other = Run.new({ Seed = 3, Unlocked = unlockedAll() })
	Eq(#LevelUp.Build(other, "Chest"), 3)
	Eq(#LevelUp.Build(other, "Chest67"), 4)
end)

T("a ready evolution is always the first card", function()
	local run = Run.new({ Seed = 12, Unlocked = unlockedAll() })
	local w = run:GetWeapon("BasicBlaster")
	w.Level = w.Def.MaxLevel
	run.Passives.RapidFire = 1
	table.insert(run.PassiveOrder, "RapidFire")
	local cards = LevelUp.Build(run, "Level")
	Eq(cards[1].Type, "Evolution")
	Eq(cards[1].Rarity, "Mythic")
	LevelUp.Apply(run, cards[1])
	Expect(run:GetWeapon("OverdriveBlaster") ~= nil and run:GetWeapon("BasicBlaster") == nil, "evolved in place")
	Eq(run.Result.Evolutions[1], "OverdriveBlaster")
end)

T("secret passives only after their secret", function()
	local run = Run.new({ Seed = 13, Unlocked = unlockedAll() })
	for _ = 1, 200 do
		for _, card in LevelUp.Build(run, "Level") do
			Expect(card.Key ~= "TouchGrass", "secret offered")
		end
	end
end)

T("locked abilities are never offered", function()
	local run = Run.new({ Seed = 9, Unlocked = { BasicBlaster = true } })
	for _ = 1, 40 do
		for _, card in LevelUp.Build(run, "Level") do
			Expect(card.Type ~= "Weapon", "offered " .. card.Key)
		end
	end
end)

T("maxed build falls back to filler cards", function()
	local run = Run.new({ Seed = 4, Hero = "Goober", Unlocked = { PulseBlast = true } })
	run:GetWeapon("PulseBlast").Level = run:GetWeapon("PulseBlast").Def.MaxLevel
	for _, def in UpgradeData.Passives do
		run.Passives[def.Key] = def.MaxLevel
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

T("every hero survives the first minute headless", function()
	for _, def in HeroData.List do
		local run = Run.new({ Seed = 11, Hero = def.Key, Unlocked = unlockedAll() })
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

T("time can jump (debug) and the picked slot boss appears", function()
	local run = Run.new({ Seed = 31, Unlocked = unlockedAll(), BossPicks = { "TheGoober", "TheMachine", "JackpotJimmy", "TheVoid" } })
	run.Invulnerable = 1e9
	run.Time = 352
	for _ = 1, 10 * 20 do
		Bot.Step(run, 1 / 20, 1)
	end
	local enc = run.Map.Encounters[1]
	Expect(enc and enc.Def.Key == "TheMachine" and enc.Slot == 2, "slot 2 boss")
	Eq(#run.Map.Encounters, 1, "the skipped slot 1 boss never came")
end)

T("every enemy behaviour and every boss runs without errors", function()
	local EnemyManager = R("ServerScriptService.Server.Sim.EnemyManager")
	local WaveManager = R("ServerScriptService.Server.Sim.WaveManager")
	for _, def in EnemyData.List do
		local run = Run.new({ Seed = 50 + def.Id, Unlocked = unlockedAll() })
		run.Invulnerable = 1e9
		EnemyManager.Spawn(run, def.Key, run.PX + 12, run.PZ, { Force = true })
		for _ = 1, 15 * 20 do
			Bot.Step(run, 1 / 20, 1)
			if run.Steps % 2 == 0 then
				run:Flush()
				run:TakeEvents()
			end
		end
	end
	local run = Run.new({ Seed = 77, Unlocked = unlockedAll() })
	run.Invulnerable = 1e9
	for _, e in WaveData.Events do
		WaveManager.TriggerEvent(run, e.Key)
		for _ = 1, 5 * 20 do
			Bot.Step(run, 1 / 20, 1)
		end
		Expect(run.Result.EventsSeen[e.Key], e.Key)
	end
end)

T("party followers get the leader's events only", function()
	local follower = Run.new({ Seed = 88, Follower = true, Unlocked = unlockedAll() })
	for _ = 1, 200 * 20 do
		follower:Step(1 / 20)
		if follower.Offer then
			follower:Choose(1)
		end
		if follower.Dead or follower.Ended then
			break
		end
	end
	Eq(follower.Result.Events67, 0, "no own events")
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
Harness.Section("67 town")
---------------------------------------------------------------------------
local ArenaData = R("ReplicatedStorage.Modules.ArenaData")
local BossData = R("ReplicatedStorage.Modules.BossData")
local ItemData = R("ReplicatedStorage.Modules.ItemData")
local LootData = R("ReplicatedStorage.Modules.LootData")
local SynergyData = R("ReplicatedStorage.Modules.SynergyData")

T("the zones tile the map (a pinwheel around the square)", function()
	local seen = {}
	for x = -238, 238, 7 do
		for z = -238, 238, 7 do
			local zone = ArenaData.ZoneAt(x, z)
			seen[zone.Key] = true
			local inside = 0
			for _, other in ArenaData.Zones do
				if ArenaData.Inside(other.Rect, x, z) then
					inside += 1
				end
			end
			Eq(inside, 1, string.format("exactly one zone at %d,%d", x, z))
		end
	end
	for _, zone in ArenaData.Zones do
		Expect(seen[zone.Key], zone.Key .. " reachable")
		Expect(zone.Stars >= 0 and zone.Stars <= 4 and zone.XP > 0 and zone.HP > 0, zone.Key)
	end
	Eq(ArenaData.ZoneAt(0, 0).Key, "Square", "start in the square")
	Expect(ArenaData.ByKey.Rift.Locked == true, "the rift starts sealed")
end)

T("lairs, vaults and spots sit in their zones; gates on the rift's edge", function()
	for _, lair in ArenaData.Lairs do
		Eq(ArenaData.ZoneAt(lair.X, lair.Z).Key, lair.Zone, lair.Key)
		Expect(BossData.SlotOfZone(lair.Zone), lair.Key .. " hosts a boss slot")
	end
	for _, v in ArenaData.Vaults do
		Eq(ArenaData.ZoneAt(v.X, v.Z).Key, v.Zone, v.Key)
	end
	for _, s in ArenaData.Spots do
		Expect(ArenaData.ZoneAt(s[1], s[2]).Key ~= "Square", "a 67 spot outside the square")
	end
	local rift = ArenaData.ByKey.Rift.Rect
	for _, g in ArenaData.RiftGates do
		Expect((g.Axis == "X" and g.Z == rift.MaxZ) or (g.Axis == "Z" and g.X == rift.MaxX), g.Key)
	end
	for key, s in ArenaData.RunSecrets do
		Expect(AchievementData.ByKey[key] and table.find(AchievementData.Secrets, key), key .. " is an account secret too")
		Expect(s.Item == nil or ItemData.ByKey[s.Item], key .. " item")
		Expect(s.Loot == nil or LootData.Sources[s.Loot], key .. " loot source")
	end
end)

T("bosses: 4 slots (3:00 / 6:00 / 9:00 / 12:00, zones by danger) + THE FINAL ONE at 15:00", function()
	local MiniBosses = R("ServerScriptService.Server.Sim.MiniBosses")
	local zones = { "Gardens", "Lot", "Strip", "Rift" }
	Eq(#BossData.Slots, 4, "four slots")
	local lastHP = 0
	for i, slot in BossData.Slots do
		Eq(slot.Index, i, "index")
		Eq(slot.At, i * 180, "slot " .. i .. " time")
		Eq(slot.Zone, zones[i], "slot " .. i .. " zone")
		Eq(ArenaData.ByKey[slot.Zone].Stars, i, "boss " .. i .. " lives in the " .. i .. "-star zone")
		Expect(ArenaData.LairOfZone[slot.Zone], "slot " .. i .. " lair")
		Expect(#slot.Pool >= 3 and slot.Damage > 0 and #slot.Tests > 3, "slot " .. i)
		local lo = math.huge
		for _, key in slot.Pool do
			local def = BossData.ByKey[key]
			Expect(def and def.Slot == i, key .. " in slot " .. i)
			lo = math.min(lo, def.HP * #def.Bodies)
		end
		Expect(lo > lastHP, "slot " .. i .. " bosses are tougher than the slot before")
		lastHP = lo
	end
	local main = BossData.Main
	Eq(main.At, 900, "15:00")
	Expect(main.X == 0 and main.Z == 0 and main.ArenaR >= 30, "the arena is the centre of the map")
	Eq(ArenaData.ZoneAt(main.X, main.Z).Key, "Square", "in 67 SQUARE")
	Expect(BossData.ByKey[main.Key].Slot == 5 and BossData.ByKey[main.Key].HP > lastHP, "the main boss is the toughest")
	-- every boss has the whole design sheet
	local fields = { "Title", "Hint", "Concept", "Silhouette", "Movement", "Basic", "Secondary", "Special", "AoE", "Telegraphs", "Death" }
	for _, def in BossData.List do
		for _, field in fields do
			Expect(type(def[field]) == "string" and #def[field] > 3, def.Key .. " " .. field)
		end
		Expect(def.HP > 0 and def.XP >= 0 and def.Coins >= 0, def.Key .. " numbers")
		Expect(#def.Phases >= 1, def.Key .. " phases")
		for _, ph in def.Phases do
			Expect(ph.At > 0 and ph.At < 1 and #ph.Name > 2 and #ph.Text > 5, def.Key .. " phase")
		end
		Expect(def.WeakPoint and def.WeakPoint.Mult > 1 and def.WeakPoint.Time > 0 and #def.WeakPoint.Text > 2, def.Key .. " weak point")
		local relic = ItemData.ByKey[def.Relic]
		Expect(relic and relic.Type == "BossRelic" and relic.Boss == def.Key, def.Key .. " has its relic")
		for _, body in def.Bodies do
			local e = EnemyData.ByKey[body]
			Expect(e and e.Params.Title, body .. " body")
			Expect(e.Behavior == "Boss" or MiniBosses.AI[body], body .. " fights")
		end
	end
end)

-- a run that plays itself with god mode, with helpers to fast-forward
local function townRun(seed: number, opts: { [string]: any }?)
	local o = { Seed = seed, Unlocked = unlockedAll() }
	for k, v in opts or {} do
		o[k] = v
	end
	local run = Run.new(o)
	run.Invulnerable = 1e9
	return run
end
local function steps(run, seconds: number, px: number?, pz: number?, events: { any }?)
	for _ = 1, math.floor(seconds * 20 + 0.5) do
		if run.Offer then
			run:Choose(1)
		end
		if px and pz then
			run:SetPlayer(px, pz)
		end
		run:Step(1 / 20)
		if run.Steps % 2 == 0 then
			run:Flush()
			for _, ev in run:TakeEvents() do
				if events then
					table.insert(events, { Time = run.Time, Name = ev.Name, P = ev.Payload })
				end
			end
		end
	end
end
local function allUnlocks(): { [string]: boolean }
	local out = {}
	for _, def in ItemData.List do
		out[def.Key] = true
	end
	return out
end

T("the boss timeline: each boss once, on time, in its zone; THE FINAL ONE in the centre", function()
	local run = townRun(611, { BossPicks = { "TheGoober", "Cartzilla", "TheGlitch", "TheVoid" } })
	local events = {}
	-- fast-forward to just before each boss (the horde keeps running)
	for i, slot in BossData.Slots do
		run.Time = slot.At - 15
		steps(run, 20, 0, 0, events)
		local enc = run.Map.Encounters[#run.Map.Encounters]
		Expect(enc and enc.Slot == i and enc.Stage == "Fight", "boss " .. i .. " is out")
	end
	run.Time = BossData.Main.At - 15
	steps(run, 16, 30, 0, events)
	local warns, spawns = {}, {}
	for _, ev in events do
		if ev.Name == "MiniBoss" and ev.P.Phase == "Warn" then
			table.insert(warns, ev)
		elseif ev.Name == "MiniBoss" and ev.P.Phase == "Spawn" then
			table.insert(spawns, ev)
		end
	end
	Eq(#warns, 5, "five warnings")
	Eq(#spawns, 5, "five bosses, each once")
	for i, ev in spawns do
		local slot = BossData.Slots[i]
		local at = if slot then slot.At else BossData.Main.At
		Expect(math.abs(warns[i].Time - (at - BossData.WarnLead)) <= 0.11, "warning " .. i .. " at " .. warns[i].Time)
		Expect(ev.Time >= at and ev.Time - at <= 0.11, "boss " .. i .. " on time: " .. ev.Time)
		Eq(ev.P.Slot, i, "slot order")
		if slot then
			Eq(ArenaData.ZoneAt(ev.P.X, ev.P.Z).Key, slot.Zone, "boss " .. i .. " in its zone")
			Eq(ev.P.Key, run.BossPlan[i], "the planned boss")
		else
			Expect(ev.P.Main and ev.P.X == 0 and ev.P.Z == 0, "THE FINAL ONE exactly in the centre")
		end
	end
	-- bosses nobody fought left when the next one was announced (no loot)
	local left = 0
	for _, ev in events do
		if ev.Name == "MiniBoss" and ev.P.Phase == "Left" then
			left += 1
		end
	end
	Eq(left, 4, "the four unfought bosses left")
	Eq(run.BossNext, 5, "no boss is left to come")
	local main = run.Map.Encounters[1]
	Expect(main and main.Main and #run.Map.Encounters == 1, "only THE FINAL ONE is out")
	-- the top boss bar is THE FINAL ONE's
	Expect(run.Boss and run.Boss.Key == "TheFinalOne", "main boss bar")
end)

T("a boss fight: warning at its lair, engage, weak point, loot on the map, pickup", function()
	local EnemyManager = R("ServerScriptService.Server.Sim.EnemyManager")
	local BossDirector = R("ServerScriptService.Server.Sim.BossDirector")
	local run = townRun(601)
	steps(run, 1)
	Expect(BossDirector.Force(run, 1, "BigQuack", EnemyManager), "announced")
	local enc = run.Map.Encounters[1]
	Expect(enc and enc.Stage == "Warn" and enc.Lair.Key == "DuckPond", "warned at its lair")
	steps(run, 3.2)
	local quack = enc.Bodies[1]
	Expect(quack and quack.Alive and quack.IsBoss, "arrived")
	Expect((quack.X - enc.X) ^ 2 + (quack.Z - enc.Z) ^ 2 < 1, "at the lair")
	Expect(math.abs(quack.MaxHP - BossData.ByKey.BigQuack.HP) < 1, "its HP from BossData")
	-- far away it stays home; close, it fights (and its attacks are telegraphed)
	steps(run, 2, 0, 0)
	Expect(not quack.Engaged, "not engaged from far away")
	steps(run, 6, enc.X + 10, enc.Z - 20)
	Expect(quack.Engaged, "engaged when close")
	-- the weak point: exposed after its attack, takes more damage
	local MiniBosses = R("ServerScriptService.Server.Sim.MiniBosses")
	MiniBosses.Expose(run, quack, "Flop")
	Expect(quack.ExposedUntil and quack.ExposedUntil > run.Time, "exposed")
	-- kill it: the loot lies on the map, walk over it
	local loot = #run.Loot
	EnemyManager.Damage(run, quack, quack.HP + 1, 0, 0, 0, 0)
	Eq(run.Result.BossesBeaten, 1, "counted")
	Eq(run.Result.BossSlots[1], 1, "slot 1")
	Eq(#run.Map.Encounters, 0, "encounter over")
	Expect(#run.Loot > loot, "an item on the ground")
	local l = run.Loot[#run.Loot]
	steps(run, 0.2, l.X, l.Z)
	Expect(run.Items[l.Key] and run.Items[l.Key] >= 1, "picked up")
	local n = 0
	for _, other in run.Loot do
		if other.Id == l.Id then
			n += 1
		end
	end
	Eq(n, 0, "gone from the ground")
end)

T("boss relics drop from their boss only once unlocked; locked ones say so", function()
	local EnemyManager = R("ServerScriptService.Server.Sim.EnemyManager")
	local BossDirector = R("ServerScriptService.Server.Sim.BossDirector")
	for _, unlocked in { false, true } do
		local run = townRun(612, { ItemUnlocks = if unlocked then { QuackCore = true } else {} })
		local events = {}
		BossDirector.Force(run, 1, "BigQuack", EnemyManager)
		steps(run, 3.2)
		local quack = run.Map.Encounters[1].Bodies[1]
		EnemyManager.Damage(run, quack, quack.HP + 1, 0, 0, 0, 0)
		steps(run, 0.2, 0, 0, events)
		local relic, hint = false, false
		for _, l in run.Loot do
			relic = relic or l.Key == "QuackCore"
		end
		for _, ev in events do
			hint = hint or (ev.Name == "LockedRelic" and ev.P.Key == "QuackCore")
		end
		Eq(relic, unlocked, "relic on the ground")
		Eq(hint, not unlocked, "locked relic hint")
	end
	-- random loot never rolls a boss relic, locked premium items stay out of the pool
	local Items = R("ServerScriptService.Server.Sim.Items")
	local run = townRun(613)
	for _ = 1, 400 do
		local key = Items.Roll(run, "Boss4")
		local def = key and ItemData.ByKey[key]
		Expect(def and def.Type == "Base" and not def.Secret, "base items only: " .. tostring(key))
	end
	local rich = townRun(614, { ItemUnlocks = allUnlocks() })
	local premium = false
	for _ = 1, 400 do
		local def = ItemData.ByKey[Items.Roll(rich, "Boss4")]
		premium = premium or def.Type == "Premium"
		Expect(def.Type ~= "BossRelic", "relics only from their boss")
	end
	Expect(premium, "unlocked premium items can drop")
end)

T("SIX & SEVEN revive each other unless killed together", function()
	local EnemyManager = R("ServerScriptService.Server.Sim.EnemyManager")
	local BossDirector = R("ServerScriptService.Server.Sim.BossDirector")
	local run = townRun(602)
	run.Map.RiftOpen = true
	BossDirector.Force(run, 4, "Twins", EnemyManager)
	steps(run, 3.2)
	local enc = run.Map.Encounters[1]
	local six, seven = enc.Bodies[1], enc.Bodies[2]
	Expect(six.Key == "Six" and seven.Key == "Seven", "two bodies")
	EnemyManager.Damage(run, six, six.HP + 1, 0, 0, 0, 0)
	Expect(enc.Revive and enc.Revive.Key == "Six", "SEVEN starts reviving SIX")
	Expect(seven.ExposedUntil and seven.ExposedUntil > run.Time, "alone, SEVEN is exposed")
	steps(run, 7)
	local back = false
	for _, e in enc.Bodies do
		if e.Key == "Six" and e.Alive then
			back = e.HP < e.MaxHP * 0.6
		end
	end
	Expect(back, "SIX came back at half HP")
	-- together: both down inside the revive time
	local loot = #run.Loot
	for _, e in table.clone(enc.Bodies) do
		if e.Alive then
			EnemyManager.Damage(run, e, e.HP + 1, 0, 0, 0, 0)
		end
	end
	Eq(run.Result.BossesBeaten, 1, "defeated together")
	Expect(#run.Loot >= loot + 2, "boss 4 drops two items")
end)

T("TICK TOCK escapes 67 seconds after the fight starts", function()
	local EnemyManager = R("ServerScriptService.Server.Sim.EnemyManager")
	local BossDirector = R("ServerScriptService.Server.Sim.BossDirector")
	local run = townRun(603)
	BossDirector.Force(run, 2, "TickTock", EnemyManager)
	steps(run, 3.2)
	local enc = run.Map.Encounters[1]
	Expect(enc and not enc.AlarmAt, "no timer before you come")
	steps(run, 1, enc.X + 12, enc.Z)
	Expect(enc.AlarmAt and math.abs(enc.AlarmAt - run.Time - 66) < 1.2, "a 67 second timer")
	local loot = #run.Loot
	steps(run, 68, 0, 0)
	Eq(#run.Map.Encounters, 0, "gone")
	Eq(run.Result.BossesBeaten, 0, "not defeated")
	Eq(#run.Loot, loot, "no loot")
end)

T("JACKPOT JIMMY tilts: shielded until its coin stacks break", function()
	local EnemyManager = R("ServerScriptService.Server.Sim.EnemyManager")
	local BossDirector = R("ServerScriptService.Server.Sim.BossDirector")
	local run = townRun(604)
	BossDirector.Force(run, 3, "JackpotJimmy", EnemyManager)
	steps(run, 3.2)
	local jimmy = run.Map.Encounters[1].Bodies[1]
	EnemyManager.Damage(run, jimmy, jimmy.HP * 0.6, 0, 0, 0, 0)
	steps(run, 0.2, jimmy.X, jimmy.Z + 20)
	Expect(jimmy.Shielded and #jimmy.Pylons == 3, "tilted: shield + 3 coin stacks")
	local hp = jimmy.HP
	EnemyManager.Damage(run, jimmy, 1000, 0, 0, 0, 0)
	Eq(jimmy.HP, hp, "no damage while shielded")
	for _, py in jimmy.Pylons do
		EnemyManager.Damage(run, py, py.HP + 1, 0, 0, 0, 0)
	end
	steps(run, 0.2, jimmy.X, jimmy.Z + 20)
	Expect(not jimmy.Shielded, "shield down")
end)

T("THE FINAL ONE: arena seal, phases, 67 FRAGMENT, victory", function()
	local EnemyManager = R("ServerScriptService.Server.Sim.EnemyManager")
	local BossDirector = R("ServerScriptService.Server.Sim.BossDirector")
	local run = townRun(615, { ItemUnlocks = { Fragment67 = true } })
	BossDirector.Force(run, 1, "BigQuack", EnemyManager) -- a lair boss out at the same time
	Expect(BossDirector.ForceMain(run), "comes")
	Expect(not BossDirector.ForceMain(run), "only once")
	steps(run, 3.2, 60, 0)
	local enc = nil
	for _, e in run.Map.Encounters do
		if e.Main then
			enc = e
		end
	end
	local boss = enc.Bodies[1]
	Expect(boss and boss.X == 0 and boss.Z == 0, "spawned exactly in the centre")
	Expect(not run.Map.ArenaSealed, "open until you walk in")
	steps(run, 0.5, 10, 0)
	Expect(run.Map.ArenaSealed and run.Map.ArenaSealed.R == BossData.Main.ArenaR, "sealed")
	local Items = R("ServerScriptService.Server.Sim.Items")
	Expect(Items.Blocked(run, BossData.Main.ArenaR + 5, 0), "nobody leaves the ring")
	steps(run, 1, 10, 0)
	local quack = nil
	for _, other in run.Map.Encounters do
		if other.Def.Key == "BigQuack" then
			quack = other.Bodies[1]
		end
	end
	Expect(quack and math.sqrt(quack.X ^ 2 + quack.Z ^ 2) > 100, "the seal keeps other bosses at their lairs")
	-- phase 2: announced, the fragment breaks off into the arena
	EnemyManager.Damage(run, boss, boss.MaxHP * 0.4, 0, 0, 0, 0)
	steps(run, 0.2, 10, 0)
	Expect(boss.Phase >= 2, "phase 2")
	local fragment = nil
	for _, l in run.Loot do
		if l.Key == "Fragment67" then
			fragment = l
		end
	end
	Expect(fragment, "the 67 FRAGMENT broke off")
	local r = math.sqrt(fragment.X ^ 2 + fragment.Z ^ 2)
	Expect(r < BossData.Main.ArenaR, "inside the arena")
	EnemyManager.Damage(run, boss, boss.HP + 1, 0, 0, 0, 0)
	Expect(run.Result.MainBoss and run.VictoryAt, "victory")
	Expect(not run.Map.ArenaSealed, "the seal breaks")
	steps(run, 4, 10, 0)
	Expect(run.Ended and run.Victory, "the run is won")
end)

T("items: 40+, levels 2-5 with mechanics, prices by class, a relic per boss", function()
	local Stats = R("ReplicatedStorage.Modules.Stats")
	Expect(#ItemData.List >= 40, "items " .. #ItemData.List)
	local base, premium, relics = 0, 0, 0
	for id, def in ItemData.List do
		Eq(def.Id, id, def.Key .. " id")
		Expect(#def.Name > 2 and #def.Desc > 5 and #def.Flavor > 3, def.Key .. " text")
		Expect(Rarity.Colors[def.Rarity], def.Key .. " rarity")
		Expect((def.MaxLevel >= 2 or def.Secret) and def.MaxLevel <= 5, def.Key .. " levels")
		Eq(def.StackBehavior, "Level", def.Key .. " stacks by level")
		Expect(def.Symbol and (def.Effect or def.Levels[1].Stats), def.Key .. " does something")
		local mechanic = false
		for _, l in def.Levels do
			Expect(#l.Desc > 3, def.Key .. " level text")
			mechanic = mechanic or l.New ~= nil
			for stat in l.Stats or {} do
				Expect(Stats.Known[stat], def.Key .. " stat " .. stat)
			end
		end
		Expect(mechanic or def.MaxLevel <= 2 or def.Secret, def.Key .. " unlocks a mechanic at a high level")
		if def.Type == "Base" then
			base += 1
			Expect(def.Price == nil, def.Key .. " is free")
		else
			Expect(ItemData.NeedsUnlock(def), def.Key .. " needs an unlock")
			local class = if def.Type == "BossRelic" then (if def.Rarity == "Mythic" then "ExtremelyRare" else "BossRelic") else def.Rarity
			local range = LootData.PriceRange[class]
			Expect(range and def.Price >= range[1] and def.Price <= range[2], def.Key .. " price " .. tostring(def.Price))
			if def.Type == "Premium" then
				premium += 1
			else
				relics += 1
				Expect(BossData.ByKey[def.Boss] and BossData.ByKey[def.Boss].Relic == def.Key, def.Key .. " boss")
			end
		end
	end
	Expect(base >= 20 and premium >= 10, "base " .. base .. ", premium " .. premium)
	Eq(relics, #BossData.List, "a relic for every boss")
	Eq(ItemData.ByKey.Fragment67.Boss, "TheFinalOne", "the main boss drops the 67 FRAGMENT")
	for _, key in { "MagneticBolt", "RedButton", "Fang", "Compass", "RustyToken", "BlackWire" } do
		Eq(ItemData.ByKey[key] and ItemData.ByKey[key].Type, "Base", key)
	end
	for _, key in { "BloodEngine", "VoidMirror", "SecondShadow", "Predator", "TimeFracture", "DeathMark", "KingOfMovement", "SoulCollector" } do
		Eq(ItemData.ByKey[key] and ItemData.ByKey[key].Type, "Premium", key)
	end
	-- loot rarity grows elite -> boss 1 -> ... -> boss 4
	local function rareShare(name: string): number
		local w = LootData.Sources[name].Weights
		return (w.Epic + w.Legendary) / (w.Common + w.Rare + w.Epic + w.Legendary)
	end
	local last = -1
	for _, name in { "Elite", "Boss1", "Boss2", "Boss3", "Boss4" } do
		Expect(rareShare(name) > last, name .. " rarer than the one before")
		last = rareShare(name)
	end
end)

T("items level up I -> II -> III on the map, a maxed one pays coins, nothing twice", function()
	local Items = R("ServerScriptService.Server.Sim.Items")
	local run = townRun(605)
	local magnet = run.Stats.PickupRange
	local events = {}
	for level = 1, 3 do
		Items.Drop(run, "MagneticBolt", run.PX + 10, run.PZ)
		steps(run, 0.2, run.PX + 10, run.PZ, events)
		steps(run, 0.2, 0, 0, events)
		Eq(run.Items.MagneticBolt, level, "level " .. level)
	end
	Expect(run.Stats.PickupRange > magnet, "stats")
	Eq(#run.ItemOrder, 1, "one item, three levels")
	local levels = {}
	for _, ev in events do
		if ev.Name == "Item" then
			table.insert(levels, ev.P.Old .. ">" .. ev.P.Level)
			if ev.P.Level == 3 then
				Expect(ev.P.New, "level III unlocks its mechanic")
			end
		end
	end
	Eq(table.concat(levels, " "), "0>1 1>2 2>3", "ITEM ACQUIRED: old -> new")
	local coins = run.Coins
	Items.Gain(run, "MagneticBolt")
	Eq(run.Items.MagneticBolt, 3, "max level")
	Expect(run.Coins >= coins + LootData.MaxedCoins, "coins instead")
	-- the same drop can be taken once only, the ground holds a limited number
	Items.Drop(run, "Fang", 50, 50)
	local id = run.Loot[#run.Loot].Id
	steps(run, 0.2, 50, 50)
	steps(run, 0.2, 50, 50)
	Eq(run.Items.Fang, 1, "taken once")
	for i = 1, LootData.MaxOnGround + 5 do
		Items.Drop(run, "Fang", -100 - i * 3, 100)
	end
	Expect(#run.Loot <= LootData.MaxOnGround, "at most " .. LootData.MaxOnGround .. " on the ground")
	for _, l in run.Loot do
		Expect(l.Id ~= id, "the taken one is gone")
	end
	-- rolls never offer more levels than an item has (counting what lies on the ground)
	local fresh = townRun(606)
	for _ = 1, 60 do
		local key = Items.Roll(fresh, "Vault")
		if key then
			Items.Drop(fresh, key, 30, 30)
		end
	end
	local count = {}
	for _, l in fresh.Loot do
		count[l.Key] = (count[l.Key] or 0) + 1
	end
	for key, n in count do
		Expect(n <= ItemData.ByKey[key].MaxLevel, key .. " x" .. n)
	end
end)

T("items change the build: dash, revive, stats", function()
	local Items = R("ServerScriptService.Server.Sim.Items")
	local run = townRun(607)
	Expect(not run:Dash(1, 0), "no dash without the skates")
	Items.Gain(run, "RocketSkates")
	local x0 = run.PX
	Expect(run:Dash(1, 0), "dash")
	Expect(run.PX > x0 + 5 and run.TeleportTo ~= nil and run.Invulnerable > 0, "moved, untouchable")
	local revives = run.Revives
	Items.Gain(run, "GoldenSnack")
	Expect(run.Revives >= revives, "revive items")
	local speed = run.Stats.WalkSpeed
	Items.Gain(run, "Espresso67")
	Expect(run.Stats.WalkSpeed >= speed, "speed item")
end)

T("synergies switch on when their build is complete", function()
	local Perks = R("ServerScriptService.Server.Sim.Perks")
	Expect(#SynergyData.List >= 15, "synergies " .. #SynergyData.List)
	for _, syn in SynergyData.List do
		Expect(#syn.Name > 3 and #syn.Desc > 10 and #syn.Needs >= 2, syn.Key)
		for _, need in syn.Needs do
			local function check(n)
				if n.Upgrade then
					local def = UpgradeData.PassiveByKey[n.Upgrade]
					Expect(def and (n.Level or 1) <= def.MaxLevel, syn.Key .. " upgrade " .. n.Upgrade)
				elseif n.Item then
					local def = ItemData.ByKey[n.Item]
					Expect(def and (n.Level or 1) <= def.MaxLevel, syn.Key .. " item " .. n.Item)
				elseif n.Ability then
					for _, key in n.Ability do
						Expect(WeaponData.ByKey[key], syn.Key .. " ability " .. key)
					end
				elseif n.Any then
					for _, m in n.Any do
						check(m)
					end
				else
					Expect(n.Dash, syn.Key .. " need")
				end
			end
			check(need)
		end
	end
	-- BULLET HELL: ricochet + multishot + penetration + split
	local run = townRun(616)
	local events = {}
	for key, level in { Ricochet = 2, DoubleShot = 1, Penetration = 2, Split = 1 } do
		run.Passives[key] = level
		table.insert(run.PassiveOrder, key)
		Expect(not run.Synergies.BulletHell, "not before the last piece")
		Perks.Refresh(run)
		run:RefreshStats()
	end
	Expect(run.Synergies.BulletHell, "BULLET HELL on")
	steps(run, 0.2, 0, 0, events)
	local seen = false
	for _, ev in events do
		seen = seen or (ev.Name == "Synergy" and ev.P.Key == "BulletHell")
	end
	Expect(seen, "announced")
end)

T("level ups: 3 cards, never impossible, never past max level", function()
	for seed = 1, 12 do
		local run = Run.new({ Seed = 700 + seed, Unlocked = unlockedAll() })
		for _ = 1, 60 do
			local cards = LevelUp.Build(run, "Level")
			Eq(#cards, GameConfig.LevelUp.Choices, "three cards")
			local ids = {}
			for _, card in cards do
				Expect(not ids[card.Id], "no duplicate card")
				ids[card.Id] = true
				if card.Type == "Passive" then
					local def = UpgradeData.PassiveByKey[card.Key]
					Expect(card.Level <= def.MaxLevel and card.Level == (run.Passives[card.Key] or 0) + 1, card.Key .. " level")
					Expect(LevelUp.RequirementsMet(run, def), card.Key .. " requirements")
					Expect(card.Change and card.Category and card.MaxLevel == def.MaxLevel, card.Key .. " card text")
				elseif card.Type == "ItemLevel" then
					Expect((run.Items[card.Key] or 0) >= 1 and card.Level <= ItemData.ByKey[card.Key].MaxLevel, card.Key .. " item level")
				end
			end
			run.Offer = { Cards = cards, Kind = "Level" }
			LevelUp.Apply(run, cards[run.Rng:NextInteger(1, #cards)])
			run.Offer = nil
		end
		for key, level in run.Passives do
			local def = UpgradeData.PassiveByKey[key]
			Expect(def and level <= def.MaxLevel, key .. " maxed at most")
		end
	end
	-- projectile upgrades need a projectile ability, dash upgrades need a dash
	local run = Run.new({ Seed = 720, Hero = "Goober", Unlocked = { PulseBlast = true } })
	for _ = 1, 100 do
		for _, card in LevelUp.Build(run, "Level") do
			local def = UpgradeData.PassiveByKey[card.Key]
			if def and def.Requires then
				Expect(LevelUp.RequirementsMet(run, def), card.Key .. " offered without its requirement")
				Expect(not def.Requires.Dash, card.Key .. " needs a dash")
			end
		end
	end
end)

T("elites: rare, capped, never in the square or a lair; they pay", function()
	local Elites = R("ServerScriptService.Server.Sim.Elites")
	local EnemyManager = R("ServerScriptService.Server.Sim.EnemyManager")
	local run = townRun(617)
	local events = {}
	run.Time = 195
	local maxAlive = 0
	for _ = 1, 30 do
		steps(run, 10, -150, 20, events)
		local alive = 0
		for _, e in run.Elites do
			if e.Alive then
				alive += 1
			end
		end
		maxAlive = math.max(maxAlive, alive)
	end
	local spawns = 0
	for _, ev in events do
		if ev.Name == "Elite" and ev.P.Phase == "Spawn" then
			spawns += 1
			Expect(ev.P.Zone ~= "Square", "not in the square")
			Expect(#ev.P.Affixes >= 1 and #ev.P.Name > 6, "named, with affixes")
		end
	end
	Expect(spawns >= 2 and spawns <= 10, "rare: " .. spawns .. " in 5 minutes")
	Expect(maxAlive <= GameConfig.Elite.MaxLate, "capped")
	Expect(not Elites.Allowed(run, 0, 0), "square")
	local lair = ArenaData.Lairs[1]
	Expect(not Elites.Allowed(run, lair.X, lair.Z), "lair")
	-- one elite: tougher, and a kill pays XP, coins, maybe an item
	local e = Elites.Spawn(run, "Husk", -150, 40, { "Armored" })
	Expect(e and e.Elite and e.ArmorCut and e.MaxHP > EnemyData.ByKey.Husk.HP * 4, "tough")
	local coins, elites = run.Coins, run.Result.Elites or 0
	EnemyManager.Damage(run, e, e.HP * 10, 0, 0, 0, 0)
	Expect(not e.Alive and run.Coins > coins, "coins")
	Eq(run.Result.Elites, elites + 1, "counted")
end)

T("CHIPS: ~100 for a good run, nothing for a quick quit", function()
	local good = LootData.ChipsFor(900, { 1, 2, 3, 4 }, true, 8, 1)
	Expect(good >= 90 and good <= 140, "a full run " .. good)
	Eq(LootData.ChipsFor(45, {}, false, 0, 1), 0, "a quit")
	local mid = LootData.ChipsFor(600, { 1, 2 }, false, 3, 1)
	Expect(mid > 20 and mid < good, "half a run " .. mid)
	Expect(LootData.ChipsFor(900, { 1, 2, 3, 4 }, true, 8, 2) > good, "harder tiers pay more")
	-- the cheapest premium item takes a few good runs, the 67 FRAGMENT many
	local cheapest = math.huge
	for _, def in ItemData.List do
		if def.Price then
			cheapest = math.min(cheapest, def.Price)
		end
	end
	Expect(cheapest >= good * 2 and cheapest <= good * 5, "cheapest unlock " .. cheapest)
	Expect(ItemData.ByKey.Fragment67.Price >= good * 30, "the 67 FRAGMENT is a long goal")
end)

T("the director: zones scale the horde, the rift opens, vaults, rush", function()
	local ArenaDirector = R("ServerScriptService.Server.Sim.ArenaDirector")
	local run = townRun(608)
	Expect(ArenaDirector.SpawnBlocked(run, -100, -150), "sealed rift: no spawns inside")
	Expect(ArenaDirector.XPMult(run, 200, -100) > ArenaDirector.XPMult(run, 0, 0), "the strip pays more than the square")
	run.Time = ArenaData.RiftOpensAt - 0.5
	steps(run, 1)
	Expect(run.Map.RiftOpen and not ArenaDirector.SpawnBlocked(run, -100, -150), "the rift opens")
	-- the square pays less after a while
	Expect(ArenaDirector.XPMult(run, 0, 0) < 1, "picked clean")
	-- a 67 RUSH and a vault
	run.Map.HotAt, run.Map.VaultAt, run.Map.QuietUntil = 0, 0, 0
	steps(run, 0.5)
	Expect(run.Map.Hot ~= nil, "a rush zone")
	local zone = ArenaData.ByKey[run.Map.Hot.Zone]
	local r = zone.Rect
	Expect(ArenaDirector.XPMult(run, (r.MinX + r.MaxX) / 2, (r.MinZ + r.MaxZ) / 2) > zone.XP, "the rush pays more")
	local awake = nil
	for i, v in run.Map.Vaults do
		if v.State == 1 then
			awake = i
		end
	end
	Expect(awake, "a vault woke up")
	local v = ArenaData.Vaults[awake]
	local loot = #run.Loot
	steps(run, ArenaData.VaultTime + 0.5, v.X, v.Z)
	Eq(run.Result.Vaults, 1, "cracked open")
	Expect(#run.Loot > loot, "an item popped out")
end)

T("secrets of 67 TOWN pay once per run", function()
	local run = townRun(609)
	Expect(run:EnterSecret("Backrooms"), "found")
	Expect(not run:EnterSecret("Backrooms"), "only once")
	Eq(run.Loot[1] and run.Loot[1].Key, "SuspiciousRock", "the suspicious rock")
	Expect(run.Result.Flags.Backrooms, "flag")
	Expect(not run:EnterSecret("TouchGrass"), "lobby secrets pay nothing in a run")
end)

T("the profile keeps CHIPS and item unlocks (and drops unknown keys)", function()
	local raw = Defaults.New()
	raw.Chips = 1234
	raw.ItemUnlocks = { BloodEngine = true, MagneticBolt = true, Nope = true }
	local clean = Defaults.Reconcile(raw)
	Eq(clean.Chips, 1234, "chips")
	Expect(clean.ItemUnlocks.BloodEngine, "premium unlock kept")
	Expect(clean.ItemUnlocks.MagneticBolt == nil and clean.ItemUnlocks.Nope == nil, "only unlockable items")
	Eq(Defaults.Reconcile({ Chips = -5 }).Chips, 0, "no negative chips")
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
