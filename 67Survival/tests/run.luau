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
		for stat in def.Stats do
			Expect(Stats.Known[stat], def.Key .. " " .. stat)
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
		if type(entry.Boss) == "string" then
			Expect(EnemyData.IsBoss(entry.Boss), "boss")
		elseif entry.Boss then
			Expect(EnemyData.BossSlots[entry.Boss], "boss slot")
		end
	end
	Expect(WaveData.HPScale(600) > WaveData.HPScale(60))
end)

T("run structure: bosses at 3, 6, 9 minutes, final at 12", function()
	local bosses = {}
	for _, entry in WaveData.Timeline do
		if entry.Boss then
			bosses[entry.At] = entry.Boss
		end
	end
	Eq(bosses[180], 1)
	Eq(bosses[360], 2)
	Eq(bosses[540], 3)
	Eq(bosses[720], "TheFinalOne")
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
		run.Passives[def.Key] = def.MaxStacks
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
	local run = Run.new({ Seed = 31, Unlocked = unlockedAll(), BossPicks = { "TheGoober", "TheMachine", "TheVoid" } })
	run.Time = 358
	for _ = 1, 8 * 20 do
		Bot.Step(run, 1 / 20, 1)
	end
	Expect(run.Boss and run.Boss.Key == "TheMachine", "slot 2 boss")
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
local RelicData = R("ReplicatedStorage.Modules.RelicData")
local MiniBossData = R("ReplicatedStorage.Modules.MiniBossData")

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
		Expect(MiniBossData.ByZone[lair.Zone], lair.Key .. " has a mini-boss")
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
		Expect(s.Relic == nil or RelicData.ByKey[s.Relic], key .. " relic")
	end
end)

T("20+ relics with rarity, a description and a known effect", function()
	local Relics = R("ServerScriptService.Server.Sim.Relics")
	local known = { Slow = true, Chain = true, DashCharge = true, Category = true, Dash = true, Explode = true, Champion = true, Thorns = true, Trail = true, Momentum = true, Crown = true, Freeze = true, Dice = true }
	local keys, rarities = {}, {}
	Expect(#RelicData.List >= 20, "relics " .. #RelicData.List)
	for id, def in RelicData.List do
		Expect(not keys[def.Key], "unique " .. def.Key)
		keys[def.Key] = true
		Eq(def.Id, id, def.Key .. " id")
		Expect(Rarity.Colors[def.Rarity], def.Key .. " rarity")
		rarities[def.Rarity] = true
		Expect(#def.Desc > 5 and #def.Flavor > 3 and #def.Name > 2, def.Key .. " text")
		Expect(def.MaxStacks >= 1, def.Key .. " stacks")
		Expect(def.Stats or def.Effect, def.Key .. " does something")
		if def.Stats then
			for stat in def.Stats do
				Expect(Stats.Known[stat], def.Key .. " stat " .. stat)
			end
		end
		if def.Effect then
			Expect(known[def.Effect], def.Key .. " effect " .. def.Effect)
		end
		if def.Requires then
			Expect(RelicData.ByKey[def.Requires], def.Key .. " requires")
		end
	end
	for _, r in { "Common", "Rare", "Epic", "Legendary", "Secret" } do
		Expect(rarities[r], "a " .. r .. " relic")
	end
	for tier = 0, 4 do
		local w = RelicData.TierWeights[tier]
		Expect(w and (w.Common + w.Rare + w.Epic + w.Legendary) > 0, "tier " .. tier)
	end
	Expect(Relics.Roll ~= nil and Relics.Gain ~= nil, "relic module")
end)

T("mini-bosses: bodies are champions with a fight each", function()
	local MiniBosses = R("ServerScriptService.Server.Sim.MiniBosses")
	Expect(#MiniBossData.List >= 5, "mini-bosses")
	for _, def in MiniBossData.List do
		Expect(#def.Hint > 5 and def.Relics >= 1 and def.Cooldown > 0, def.Key)
		Expect(def.Zone == nil or ArenaData.LairOfZone[def.Zone], def.Key .. " lair")
		for _, body in def.Bodies do
			local e = EnemyData.ByKey[body]
			Expect(e and e.Champion == true and e.Behavior == "Champion", body .. " is a champion")
			Expect(MiniBosses.AI[body], body .. " fights")
			Expect(e.Params.Title, body .. " title")
		end
	end
end)

-- a run that plays itself with god mode, with helpers to fast-forward
local function townRun(seed: number)
	local run = Run.new({ Seed = seed, Unlocked = unlockedAll() })
	run.Invulnerable = 1e9
	return run
end
local function steps(run, seconds: number, px: number?, pz: number?)
	for _ = 1, math.floor(seconds * 20) do
		if run.Offer then
			run:Choose(1)
		end
		if px and pz then
			run:SetPlayer(px, pz)
		end
		run:Step(1 / 20)
		if run.Steps % 2 == 0 then
			run:Flush()
			run:TakeEvents()
		end
	end
end

T("a mini-boss: warning, lair, fight, relic loot, pickup", function()
	local ArenaDirector = R("ServerScriptService.Server.Sim.ArenaDirector")
	local run = townRun(601)
	steps(run, 1)
	Expect(ArenaDirector.Summon(run, "Test", false, "BigQuack", true), "summoned")
	local enc = run.Map.Encounters[1]
	Expect(enc and enc.Stage == "Warn" and enc.Lair.Key == "DuckPond", "warned at its lair")
	steps(run, 3.2)
	local quack = enc.Bodies[1]
	Expect(quack and quack.Alive and quack.IsBoss and quack.Def.Champion, "arrived")
	Expect((quack.X - enc.X) ^ 2 + (quack.Z - enc.Z) ^ 2 < 1, "at the lair")
	-- far away it stays home; close, it fights (and its attacks are telegraphed)
	steps(run, 2, 0, 0)
	Expect(not quack.Engaged, "not engaged from far away")
	steps(run, 6, enc.X + 10, enc.Z - 20)
	Expect(quack.Engaged, "engaged when close")
	Expect(run.Result.Flags ~= nil, "flags")
	-- kill it: a relic drops, walk over it
	local EnemyManager = R("ServerScriptService.Server.Sim.EnemyManager")
	EnemyManager.Damage(run, quack, quack.HP + 1, 0, 0, 0, 0)
	Eq(run.Result.MiniBosses, 1, "counted")
	Eq(#run.Map.Encounters, 0, "encounter over")
	Expect(#run.Loot >= 1, "relic loot on the ground")
	local l = run.Loot[1]
	steps(run, 0.2, l.X, l.Z)
	Expect(#run.RelicOrder >= 1 and run.Relics[l.Key] == 1, "picked up")
	Expect((run.Map.Rest.BigQuack or 0) > run.Time, "rests before coming back")
end)

T("SIX & SEVEN revive each other unless killed together", function()
	local ArenaDirector = R("ServerScriptService.Server.Sim.ArenaDirector")
	local EnemyManager = R("ServerScriptService.Server.Sim.EnemyManager")
	local run = townRun(602)
	ArenaDirector.Summon(run, "Test", false, "Twins", true)
	steps(run, 3.2)
	local enc = run.Map.Encounters[1]
	local six, seven = enc.Bodies[1], enc.Bodies[2]
	Expect(six.Key == "Six" and seven.Key == "Seven", "two bodies")
	EnemyManager.Damage(run, six, six.HP + 1, 0, 0, 0, 0)
	Expect(enc.Revive and enc.Revive.Key == "Six", "SEVEN starts reviving SIX")
	steps(run, 7)
	local back = false
	for _, e in enc.Bodies do
		if e.Key == "Six" and e.Alive then
			back = e.HP < e.MaxHP * 0.6
		end
	end
	Expect(back, "SIX came back at half HP")
	-- together: both down inside 6.7 s
	for _, e in table.clone(enc.Bodies) do
		if e.Alive then
			EnemyManager.Damage(run, e, e.HP + 1, 0, 0, 0, 0)
		end
	end
	Eq(run.Result.MiniBosses, 1, "defeated together")
	Expect(#run.Loot >= 2, "two relics")
end)

T("TICK TOCK escapes when its 67 seconds run out", function()
	local ArenaDirector = R("ServerScriptService.Server.Sim.ArenaDirector")
	local run = townRun(603)
	ArenaDirector.Summon(run, "Test", false, "TickTock", true)
	steps(run, 3.2)
	local enc = run.Map.Encounters[1]
	Expect(enc and enc.AlarmAt and math.abs(enc.AlarmAt - run.Time - 67) < 0.2, "a 67 second timer")
	steps(run, 68, 0, 0)
	Eq(#run.Map.Encounters, 0, "gone")
	Eq(run.Result.MiniBosses, 0, "not defeated")
	Eq(#run.Loot, 0, "no loot")
end)

T("JACKPOT JIMMY tilts: shielded until its coin stacks break", function()
	local ArenaDirector = R("ServerScriptService.Server.Sim.ArenaDirector")
	local EnemyManager = R("ServerScriptService.Server.Sim.EnemyManager")
	local run = townRun(604)
	ArenaDirector.Summon(run, "Test", false, "JackpotJimmy", true)
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

T("relics change the build: stats, ability buffs, dash, on-kill blasts", function()
	local Relics = R("ServerScriptService.Server.Sim.Relics")
	local run = townRun(605)
	local speed, might = run.Stats.WalkSpeed, run.Stats.Might
	Relics.Gain(run, "Sneakers")
	Relics.Gain(run, "ProteinBar")
	Expect(run.Stats.WalkSpeed > speed and run.Stats.Might > might, "stats")
	local w = run.Weapons[1]
	local dmg = w.S.Damage
	Relics.Gain(run, "SlingshotScope")
	if w.Def.Category == "PROJECTILE" then
		Expect(w.S.Damage > dmg * 1.2, "PROJECTILE buff")
	end
	local amount = w.S.Amount
	Relics.Gain(run, "ThirdArm")
	Eq(w.S.Amount, amount + 1, "+1 projectile")
	-- stacks cap: a maxed relic turns into coins
	local coins = run.Coins
	Relics.Gain(run, "ThirdArm")
	Eq(run.Relics.ThirdArm, 1, "max stacks")
	Expect(run.Coins > coins, "coins instead")
	-- the dash: needs the skates, stops at walls, spends a charge, recharges
	Expect(not run:Dash(1, 0), "no dash without skates")
	Relics.Gain(run, "RocketSkates")
	local x0 = run.PX
	Expect(run:Dash(1, 0), "dash")
	Expect(run.PX > x0 + 5 and run.TeleportTo ~= nil and run.Invulnerable > 0, "moved, untouchable")
	Expect(not run:Dash(1, 0), "no charge left")
	steps(run, 3.5)
	Eq(run.DashState.Charges, 1, "recharged")
	Relics.Gain(run, "SpareSkate")
	Eq(run.DashState.Max, 2, "extra charge")
	-- a revive from the golden snack
	local revives = run.Revives
	Relics.Gain(run, "GoldenSnack")
	Eq(run.Revives, revives + 1, "revive")
	-- the roll never gives what is maxed or needs a missing relic
	local fresh = townRun(606)
	for _ = 1, 300 do
		local key = Relics.Roll(fresh, 4)
		Expect(key and not RelicData.ByKey[key].Secret, "a relic")
		Expect(RelicData.ByKey[key].Requires == nil, "no spare skate without skates")
	end
end)

T("the director: zones scale the horde, the rift opens, vaults, rush, threat", function()
	local ArenaDirector = R("ServerScriptService.Server.Sim.ArenaDirector")
	local run = townRun(607)
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
	steps(run, ArenaData.VaultTime + 0.5, v.X, v.Z)
	Eq(run.Result.Vaults, 1, "cracked open")
	Expect(#run.Loot >= 1, "a relic popped out")
	-- threat: kills in a zone wake its mini-boss
	local EnemyManager = R("ServerScriptService.Server.Sim.EnemyManager")
	-- a clean slate: nobody out, no lure due
	for _, enc in table.clone(run.Map.Encounters) do
		for _, e in enc.Bodies do
			EnemyManager.Despawn(run, e)
		end
	end
	table.clear(run.Map.Encounters)
	run.Map.LevelLured[10], run.Map.LevelLured[20] = true, true
	run.Map.LureAt = run.Time + 999
	run.Map.Rest = {}
	local gardens = ArenaData.ByKey.Gardens
	for _ = 1, gardens.Threat do
		local e = EnemyManager.Spawn(run, "Goober", -120, 20, { Force = true })
		EnemyManager.Damage(run, e, e.HP + 1, 0, 0, 0, 0)
	end
	run.Boss = nil
	run.Wave.PendingBoss = nil
	run.Map.QuietUntil = 0
	steps(run, 0.2, -120, 20)
	local woke = false
	for _, enc in run.Map.Encounters do
		if enc.Def.Key == "BigQuack" and enc.Reason == "Threat" then
			woke = true
		end
	end
	Expect(woke, "the gardens woke THE BIG QUACK")
end)

T("secrets of 67 TOWN pay once per run", function()
	local run = townRun(608)
	Expect(run:EnterSecret("Backrooms"), "found")
	Expect(not run:EnterSecret("Backrooms"), "only once")
	Eq(run.Loot[1] and run.Loot[1].Key, "SuspiciousRock", "the suspicious rock")
	Expect(run.Result.Flags.Backrooms, "flag")
	Expect(not run:EnterSecret("TouchGrass"), "lobby secrets pay nothing in a run")
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
