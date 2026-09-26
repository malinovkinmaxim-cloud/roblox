--[[
	Offline test suite (run from ChileSimulator/):   lune run tests/run.luau

	Everything that can be verified without the Roblox engine:
	  - safe numbers + formatting (no nan/inf, suffixes, lengths)
	  - body shape: monotonic growth, thinner when taller, never an invisible line
	  - formulas: upgrade sequences, costs, rebirth multipliers, leaderboard encoding
	  - data: defaults, reconcile of corrupted saves
	  - ANTI-CHEAT: tap spam, huge tap counts, NaN/inf/strings, rebirth without height,
	    buying without coins, hatching locked eggs, claiming rewards twice
	  - rewards: daily streak, quests, playtime, achievements
	  - balance: first upgrade / first rebirth arrive in the intended time
]]

local process = require("@lune/process")
local H = require("./harness")
local Test, Expect, Eq, Near = H.Test, H.Expect, H.Eq, H.Near

local Num = H.Require("ReplicatedStorage.Shared.Util.Num")
local Format = H.Require("ReplicatedStorage.Shared.Util.Format")
local BodyShape = H.Require("ReplicatedStorage.Shared.BodyShape")
local Formulas = H.Require("ReplicatedStorage.Shared.Formulas")
local Config = H.Require("ReplicatedStorage.Shared.Config")
local PetConfig = H.Require("ReplicatedStorage.Shared.PetConfig")
local ZoneConfig = H.Require("ReplicatedStorage.Shared.ZoneConfig")
local RewardConfig = H.Require("ReplicatedStorage.Shared.RewardConfig")
local ShopConfig = H.Require("ReplicatedStorage.Shared.ShopConfig")
local BoostConfig = H.Require("ReplicatedStorage.Shared.BoostConfig")
local CosmeticConfig = H.Require("ReplicatedStorage.Shared.CosmeticConfig")
local EventConfig = H.Require("ReplicatedStorage.Shared.EventConfig")

local Defaults = H.Require("ServerScriptService.Server.Logic.Defaults")
local Session = H.Require("ServerScriptService.Server.Logic.Session")
local Growth = H.Require("ServerScriptService.Server.Logic.Growth")
local Pets = H.Require("ServerScriptService.Server.Logic.Pets")
local Boosts = H.Require("ServerScriptService.Server.Logic.Boosts")
local Rewards = H.Require("ServerScriptService.Server.Logic.Rewards")
local Mults = H.Require("ServerScriptService.Server.Logic.Mults")

local NOW = 1_780_000_000 -- a fixed unix time

local function newSession(clock: number?)
	return Session.new(1, "Tester", Defaults.New(), clock or 0)
end

local function world(event)
	return { Now = NOW, Event = event }
end

local function isSane(x): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

---------------------------------------------------------------------------
H.Section("numbers & formatting")
---------------------------------------------------------------------------
Test("Num.Sanitize removes nan / inf", function()
	Eq(Num.Sanitize(0 / 0), 0)
	Eq(Num.Sanitize(math.huge), Num.MAX)
	Eq(Num.Sanitize(-math.huge), -Num.MAX)
	Eq(Num.Sanitize("12"), 0)
	Eq(Num.NonNeg(-5), 0)
	Eq(Num.Mul(math.huge, 0), 0)
	Expect(isSane(Num.Mul(1e300, 1e300)))
end)

Test("Format.Number suffixes", function()
	Eq(Format.Number(0), "0")
	Eq(Format.Number(999), "999")
	Eq(Format.Number(1000), "1K")
	Eq(Format.Number(1250), "1.25K")
	Eq(Format.Number(12500), "12.5K")
	Eq(Format.Number(999999), "999K")
	Eq(Format.Number(1e6), "1M")
	Eq(Format.Number(1e9), "1B")
	Eq(Format.Number(1e12), "1T")
	Eq(Format.Number(1e15), "1Qa")
	Eq(Format.Number(1e18), "1Qi")
	Eq(Format.Number(2.5e21), "2.5Sx")
	Eq(Format.Number(1e33), "1Dc")
	Eq(Format.Number(1.5e200), "1.5e200")
	Eq(Format.Number(0 / 0), "0")
	Eq(Format.Number(math.huge), "1e300")
end)

Test("every power of ten formats without nan/inf", function()
	for e = 0, 300 do
		local s = Format.Number(10 ^ e)
		Expect(not string.find(s, "nan") and not string.find(s, "inf"), s)
		local s2 = Format.Number(9.999 * 10 ^ e)
		Expect(not string.find(s2, "nan") and not string.find(s2, "inf"), s2)
	end
end)

Test("Format.Length / Gain (height is in cm)", function()
	Eq(Format.Length(1), "0.01 m")
	Eq(Format.Length(2), "0.02 m")
	Eq(Format.Length(150), "1.50 m")
	Eq(Format.Length(12345), "123.4 m")
	Eq(Format.Length(1e5), "1K m")
	Eq(Format.Length(1e8), "1M m")
	Eq(Format.Gain(1), "+1 cm")
	Eq(Format.Gain(12), "+12 cm")
	Eq(Format.Gain(1.5), "+1.5 cm")
	Eq(Format.Gain(250), "+2.50 m")
	Eq(Format.Time(125), "2:05")
	Eq(Format.Time(3725), "1:02:05")
	Eq(Format.Mult(2), "x2")
	Eq(Format.Mult(1.25), "x1.25")
	Eq(Format.Mult(2500), "x2.5K")
	Eq(Format.Commas(1234567), "1,234,567")
end)

---------------------------------------------------------------------------
H.Section("body shape (the core visual)")
---------------------------------------------------------------------------
Test("starts as a flat cutlet", function()
	local s = BodyShape.FromHeight(Config.START_HEIGHT)
	Expect(s.Width > s.Body * 3, "start body must be much wider than tall")
	Expect(s.Head >= 1, "head stays readable")
end)

Test("normal proportions around 10 m", function()
	local s = BodyShape.FromHeight(1000)
	Near(s.Body, 4, 0.01)
	Near(s.Width, 2, 0.01)
end)

Test("taller every tap: body height strictly grows, relative width shrinks", function()
	local prevBody, prevAspect = 0, 0
	for i = 0, 700 do
		local cm = 10 ^ (i / 20)
		local s = BodyShape.FromHeight(cm)
		Expect(s.Body > prevBody or s.Body == BodyShape.KEYS[#BodyShape.KEYS].B, "body shrank at " .. cm)
		local aspect = s.Body / s.Width
		Expect(aspect >= prevAspect - 1e-9, "aspect decreased at " .. cm)
		prevBody, prevAspect = s.Body, aspect
	end
end)

Test("never becomes an invisible line", function()
	for _, cm in { 1e6, 1e12, 1e20, 1e40, 1e80, 1e200, Num.MAX } do
		local s = BodyShape.FromHeight(cm)
		Expect(s.Body / s.Width <= BodyShape.MAX_ASPECT + 1e-6, "aspect too big at " .. cm)
		Expect(s.Width >= BodyShape.MIN_WIDTH, "too thin")
		Expect(s.Head >= 1, "head vanished")
		Expect(s.Total < 2048, "part size limit")
		Expect(isSane(s.Total))
	end
end)

Test("hands never reach through the floor, arms are not flippers", function()
	for i = 0, 600 do
		local s = BodyShape.FromHeight(10 ^ (i / 20))
		local shoulder = s.Legs + s.Torso - s.ArmWidth * 0.35
		Expect(shoulder - s.ArmLength >= 0.04, "hand below ground at 10^" .. (i / 20))
		Expect(s.ArmWidth <= s.LimbWidth + 1e-9, "arm wider than a leg")
	end
end)

Test("each early tap is visibly taller", function()
	local a = BodyShape.FromHeight(1).Body
	local b = BodyShape.FromHeight(2).Body
	Expect(b / a > 1.15, "second tap should grow the body > 15%")
end)

Test("squash & stretch keeps the head and changes width", function()
	local normal = BodyShape.FromHeight(1e4)
	local stretched = BodyShape.FromHeight(1e4, 1.3)
	Expect(stretched.Body > normal.Body)
	Expect(stretched.Width < normal.Width)
	local squashed = BodyShape.FromHeight(1e4, 0.75)
	Expect(squashed.Width > normal.Width)
end)

---------------------------------------------------------------------------
H.Section("formulas")
---------------------------------------------------------------------------
Test("tap power sequence x1 x2 x5 x10 x25 x50 x100 x250 x500 x1K", function()
	local expected = { 1, 2, 5, 10, 25, 50, 100, 250, 500, 1000, 2500 }
	for level, value in expected do
		Near(Formulas.TapPower(level), value, 1e-9, "level " .. level)
	end
end)

Test("upgrade costs grow and stay finite up to max level", function()
	local prev = 0
	for level = 1, Config.Upgrades.TapPower.MaxLevel - 1 do
		local cost = Formulas.TapCost(level)
		Expect(cost and isSane(cost) and cost > prev, "tap cost " .. level)
		prev = cost
	end
	Eq(Formulas.TapCost(Config.Upgrades.TapPower.MaxLevel), nil)
	prev = 0
	for level = 0, Config.Upgrades.AutoGrow.MaxLevel - 1 do
		local cost = Formulas.AutoCost(level)
		Expect(cost and isSane(cost) and cost > prev, "auto cost " .. level)
		prev = cost
	end
end)

Test("rebirth multiplier R1 x2, R2 x3, R3 x5, R10 x21, R100 x1101", function()
	Eq(Formulas.RebirthMultiplier(0), 1)
	Eq(Formulas.RebirthMultiplier(1), 2)
	Eq(Formulas.RebirthMultiplier(2), 3)
	Eq(Formulas.RebirthMultiplier(3), 5)
	Eq(Formulas.RebirthMultiplier(10), 21)
	Eq(Formulas.RebirthMultiplier(100), 1101)
end)

Test("rebirth cost: 100 m first, exponential, finite", function()
	Eq(Formulas.RebirthCost(0), 10000)
	local prev = 0
	for r = 0, 500 do
		local c = Formulas.RebirthCost(r)
		Expect(isSane(c) and c >= prev, "rebirth cost " .. r)
		prev = c
	end
end)

Test("coins never nan for extreme inputs", function()
	local m = Formulas.Multipliers({ Rebirths = 1e9, ZoneIndex = 7, PetMult = 1e200, BoostHeight = 1e200, BoostCoins = 1e200, EventHeight = 100, EventCoins = 5, Passes = { VIP = true, Growth2x = true, Coins2x = true }, Gem = { TapBonus = 50 } })
	Expect(isSane(Formulas.TapGain(150, m)))
	Expect(isSane(Formulas.TapCoins(150, m, Num.MAX)))
	Expect(isSane(Formulas.AutoGain(150, m)))
	Expect(isSane(Formulas.AutoCoins(150, m, Num.MAX)))
end)

Test("pet multipliers stack additively", function()
	Near(Formulas.PetMultiplier({ 5, 5, 5 }), 13, 1e-9)
	Near(Formulas.PetMultiplier({}), 1, 1e-9)
end)

Test("leaderboard height encoding round-trips and keeps order", function()
	local prev = -1
	for e = 0, 300, 7 do
		local cm = 3.7 * 10 ^ e
		if cm <= Num.MAX then
			local v = Formulas.EncodeHeight(cm)
			Expect(v > prev and v == math.floor(v) and v < 2 ^ 53, "encode " .. e)
			prev = v
			local back = Formulas.DecodeHeight(v)
			Expect(math.abs(back / cm - 1) < 1e-6, "decode " .. e)
		end
	end
end)

Test("zones unlock at 10 m, 100 m, 1K, 10K, 1M, 1B", function()
	Eq(ZoneConfig.HighestUnlocked(1), 1)
	Eq(ZoneConfig.HighestUnlocked(999), 1)
	Eq(ZoneConfig.HighestUnlocked(1000), 2)
	Eq(ZoneConfig.HighestUnlocked(1e4), 3)
	Eq(ZoneConfig.HighestUnlocked(1e5), 4)
	Eq(ZoneConfig.HighestUnlocked(1e6), 5)
	Eq(ZoneConfig.HighestUnlocked(1e8), 6)
	Eq(ZoneConfig.HighestUnlocked(1e11), 7)
	Eq(ZoneConfig.IndexFromX(0), 1)
	Eq(ZoneConfig.IndexFromX(ZoneConfig.CenterX(3)), 3)
	Eq(ZoneConfig.IndexFromX(1e9), #ZoneConfig.Zones)
end)

---------------------------------------------------------------------------
H.Section("config integrity")
---------------------------------------------------------------------------
Test("every egg pet exists, secret is ultra rare", function()
	for _, egg in PetConfig.Eggs do
		local total, secret = 0, 0
		for _, entry in egg.Pets do
			Expect(PetConfig.Pets[entry.Id], "missing pet " .. entry.Id)
			total += entry.Weight
			if PetConfig.Pets[entry.Id].Rarity == "Secret" then
				secret += entry.Weight
			end
		end
		Expect(secret / total < 0.0001, egg.Id .. " secret chance too high")
		Expect(ZoneConfig.Zones[egg.Zone], "egg zone")
	end
end)

Test("rewards reference real boosts / rarities", function()
	local function check(reward)
		if reward.Kind == nil then
			for _, r in reward do
				check(r)
			end
		elseif reward.Kind == "Boost" then
			Expect(BoostConfig.Boosts[reward.Id], "boost " .. tostring(reward.Id))
		elseif reward.Kind == "Pet" and reward.Rarity then
			Expect(PetConfig.Rarities[reward.Rarity], "rarity")
		end
	end
	for _, d in RewardConfig.Daily do
		check(d.Reward)
	end
	for _, p in RewardConfig.Playtime do
		check(p.Reward)
	end
	for _, q in RewardConfig.Quests do
		check(q.Reward)
	end
	for _, c in RewardConfig.Chest.Table do
		check(c.Reward)
	end
	for _, product in ShopConfig.Products do
		if product.Grant.Kind ~= "Rebirth" then
			check(product.Grant)
		end
	end
	for _, a in RewardConfig.Achievements do
		if a.Boost then
			Expect(BoostConfig.Boosts[a.Boost], "achievement boost")
		end
	end
	Eq(#RewardConfig.Daily, 7)
	Eq(#RewardConfig.Quests, 3)
end)

Test("cosmetics reference real passes", function()
	for _, kind in { CosmeticConfig.Trails, CosmeticConfig.Auras } do
		for id, def in kind do
			Expect(def.Price or (def.Pass and ShopConfig.Passes[def.Pass]), "cosmetic " .. id)
		end
	end
	for _, id in EventConfig.Order do
		Expect(EventConfig.Events[id], "event " .. id)
	end
end)

---------------------------------------------------------------------------
H.Section("save data")
---------------------------------------------------------------------------
Test("reconcile of nil / garbage gives defaults", function()
	local d = Defaults.Reconcile(nil)
	Eq(d.Height, Config.START_HEIGHT)
	d = Defaults.Reconcile({ Height = "lots", Coins = 0 / 0, Gems = math.huge, Rebirths = -4, TapLevel = 1e9, Pets = { a = { Id = "NotAPet" } } })
	Eq(d.Height, Config.START_HEIGHT)
	Eq(d.Coins, 0)
	Eq(d.Gems, Num.MAX)
	Eq(d.Rebirths, 0)
	Eq(d.TapLevel, Config.Upgrades.TapPower.MaxLevel)
	Eq(next(d.Pets), nil)
end)

Test("reconcile keeps valid progress", function()
	local d = Defaults.New()
	d.Height = 12345
	d.BestHeight = 99999
	d.Coins = 777
	d.Rebirths = 3
	d.Pets["7"] = { Id = "Unicorn", E = true }
	d.NextPetUid = 2
	d.Trails.Owned.Fire = true
	d.Trails.Equipped = "Fire"
	d.Boosts.Active.Height2x = 100
	local r = Defaults.Reconcile(d)
	Eq(r.Height, 12345)
	Eq(r.BestHeight, 99999)
	Eq(r.Coins, 777)
	Eq(r.Rebirths, 3)
	Eq(r.Pets["7"].Id, "Unicorn")
	Eq(r.NextPetUid, 8, "uid counter must be past existing uids")
	Eq(r.Trails.Equipped, "Fire")
	Eq(r.Boosts.Active.Height2x, 100)
end)

---------------------------------------------------------------------------
H.Section("anti-cheat: taps")
---------------------------------------------------------------------------
Test("a tap grows you and pays coins", function()
	local s = newSession()
	local accepted, gain, coins = Growth.Tap(s, 1, world(), 0)
	Eq(accepted, 1)
	Eq(gain, 1)
	Expect(coins > 0)
	Eq(s.Data.Height, Config.START_HEIGHT + 1)
	Eq(s.Data.Taps, 1)
end)

Test("exploit: +1,000,000,000 in one remote is capped to MaxBatch and the bucket", function()
	local s = newSession()
	local accepted = Growth.Tap(s, 1e9, world(), 0)
	Expect(accepted <= Config.Tap.MaxBatch, "accepted " .. accepted)
	Expect(s.Data.Height <= Config.START_HEIGHT + Config.Tap.MaxBatch)
end)

Test("exploit: nan / inf / negative / fractional / string / table counts are rejected", function()
	local s = newSession()
	for _, bad in { 0 / 0, math.huge, -math.huge, -5, 0, 1.5, "10", { 1 }, nil, true } do
		local accepted = Growth.Tap(s, bad, world(), 0)
		Eq(accepted, 0, "value " .. tostring(bad))
	end
	Eq(s.Data.Height, Config.START_HEIGHT)
	Expect((s.Flags.BadTap or 0) >= 9)
end)

Test("exploit: spamming the remote 10,000 times in one second", function()
	local s = newSession()
	local total = 0
	for _ = 1, 10000 do
		total += Growth.Tap(s, Config.Tap.MaxBatch, world(), 0.5)
	end
	Expect(total <= Config.Tap.Burst + Config.Tap.MaxPerSecond, "accepted " .. total)
end)

Test("sustained rate is capped at MaxPerSecond", function()
	local s = newSession()
	local total = 0
	for tick = 1, 600 do -- 60 seconds, 10 remotes per second each claiming MaxBatch
		total += Growth.Tap(s, Config.Tap.MaxBatch, world(), tick / 10)
	end
	Expect(total <= Config.Tap.Burst + Config.Tap.MaxPerSecond * 60 + 1, "accepted " .. total)
	Expect(total >= Config.Tap.MaxPerSecond * 59, "legit fast tapping must still work: " .. total)
end)

Test("a normal human (8 taps/s) never loses a tap", function()
	local s = newSession()
	local total = 0
	for i = 1, 80 do -- 8 taps per second for 10 s, flushed every 0.125 s
		total += Growth.Tap(s, 1, world(), i * 0.125)
	end
	Eq(total, 80)
end)

Test("auto tap shares the tap limit", function()
	local s = newSession()
	s.Passes.AutoTap = true
	local manual = 0
	for i = 1, 100 do
		manual += Growth.Tap(s, Config.Tap.MaxBatch, world(), i / 10)
		if i % 10 == 0 then
			Growth.Tick(s, 1, world(), i / 10)
		end
	end
	Expect(s.Data.Taps <= Config.Tap.Burst + Config.Tap.MaxPerSecond * 10 + 1, "taps " .. s.Data.Taps)
end)

---------------------------------------------------------------------------
H.Section("anti-cheat: economy")
---------------------------------------------------------------------------
Test("cannot buy upgrades without coins / unknown upgrades", function()
	local s = newSession()
	local ok = Growth.BuyUpgrade(s, "TapPower")
	Eq(ok, false)
	Eq(s.Data.TapLevel, 1)
	Eq((Growth.BuyUpgrade(s, "Height")), false)
	Eq((Growth.BuyUpgrade(s, nil)), false)
	s.Data.Coins = Formulas.TapCost(1)
	Eq((Growth.BuyUpgrade(s, "TapPower")), true)
	Eq(s.Data.TapLevel, 2)
	Eq(s.Data.Coins, 0)
end)

Test("cannot rebirth without height; rebirth resets height and multiplies growth", function()
	local s = newSession()
	Eq((Growth.Rebirth(s, world())), false)
	Eq(s.Data.Rebirths, 0)
	s.Data.Height = Formulas.RebirthCost(0)
	s.Data.BestHeight = s.Data.Height
	s.Data.Coins = 500
	s.Data.TapLevel = 3
	Eq((Growth.Rebirth(s, world())), true)
	Eq(s.Data.Rebirths, 1)
	Eq(s.Data.Height, Config.START_HEIGHT)
	Eq(s.Data.Coins, 500, "coins are kept")
	Eq(s.Data.TapLevel, 3, "upgrades are kept")
	Expect(s.Data.Gems >= Config.Rebirth.GemsBase)
	local _, gain = Growth.Tap(s, 1, world(), 0)
	Near(gain, Formulas.TapPower(3) * 2, 1e-9, "x2 after first rebirth")
	-- a rebirth broadcast effect was queued
	local found = false
	for _, out in s.Out do
		if out.Name == "Rebirth" and out.Broadcast then
			found = true
		end
	end
	Expect(found, "rebirth effect")
end)

Test("gem upgrades need gems", function()
	local s = newSession()
	Eq((Growth.BuyGemUpgrade(s, "TapBonus")), false)
	Eq((Growth.BuyGemUpgrade(s, "Nope")), false)
	s.Data.Gems = 1000
	Eq((Growth.BuyGemUpgrade(s, "TapBonus")), true)
	Eq(s.Data.Gem.TapBonus, 1)
end)

---------------------------------------------------------------------------
H.Section("pets")
---------------------------------------------------------------------------
Test("hatch costs coins, respects locks and storage", function()
	local s = newSession()
	local rng = H.Random.new(42)
	local res, err = Pets.Hatch(s, "Basic", 1, rng)
	Eq(res, nil, "no coins")
	s.Data.Coins = 1e6
	res = Pets.Hatch(s, "Basic", 3, rng)
	Expect(res and #res == 3, err)
	Eq(s.Data.Coins, 1e6 - 300)
	Eq(Pets.Count(s), 3)
	Eq(#Pets.EquippedList(s), 3, "auto-equip")
	res, err = Pets.Hatch(s, "Galaxy", 1, rng)
	Eq(res, nil, "galaxy egg is locked")
	res = Pets.Hatch(s, "Basic", 99, rng)
	Eq(res, nil, "bad count")
	res = Pets.Hatch(s, "Basic", 0 / 0, rng)
	Eq(res, nil, "nan count")
	s.Data.Coins = 1e12
	for _ = 1, 20 do
		Pets.Hatch(s, "Basic", 3, rng)
	end
	Expect(Pets.Count(s) <= Pets.Capacity(s), "storage cap")
end)

Test("equip limit and equip best", function()
	local s = newSession()
	for _, id in { "Doggy", "Kitty", "Bunny", "Piggy", "GoldenChick" } do
		Pets.Give(s, id)
	end
	Eq(#Pets.EquippedList(s), 3)
	Pets.EquipBest(s)
	local mult = Pets.Multiplier(s)
	Near(mult, 1 + (5 - 1) + (2 - 1) + (1.5 - 1), 1e-9)
	local uid = Pets.EquippedList(s)[1]
	Eq((Pets.Equip(s, uid, false)), true)
	Eq(#Pets.EquippedList(s), 2)
	Eq((Pets.Delete(s, "nope")), false)
end)

Test("roll distribution roughly matches weights", function()
	local egg = PetConfig.GetEgg("Basic")
	local rng = H.Random.new(7)
	local counts = {}
	local n = 200000
	for _ = 1, n do
		local id = PetConfig.Roll(egg, rng:NextNumber())
		counts[id] = (counts[id] or 0) + 1
	end
	Near((counts.Doggy or 0) / n, 0.42, 0.01, "doggy")
	Near((counts.GoldenChick or 0) / n, 0.014, 0.002, "legendary")
end)

---------------------------------------------------------------------------
H.Section("boosts, rewards, quests, achievements")
---------------------------------------------------------------------------
Test("boosts: inventory, activation, stacking time, multiplier, expiry", function()
	local s = newSession()
	Eq((Boosts.Activate(s, "Height2x")), false)
	Boosts.Add(s, "Height2x", 2)
	Eq((Boosts.Activate(s, "Height2x")), true)
	Eq((Boosts.Activate(s, "Height2x")), true)
	Eq(s.Data.Boosts.Active.Height2x, 2 * BoostConfig.Boosts.Height2x.Duration)
	local h = Boosts.Multipliers(s)
	Eq(h, 2)
	local _, gain = Growth.Tap(s, 1, world(), 0)
	Eq(gain, 2)
	Boosts.Tick(s, 1e6)
	Eq(s.Data.Boosts.Active.Height2x, nil)
end)

Test("daily streak: claim once a day, continue, reset after a missed day", function()
	local s = newSession()
	local rng = H.Random.new(1)
	local w = world()
	Expect(Rewards.ClaimDaily(s, w, rng))
	Eq(s.Data.Daily.Streak, 1)
	Eq(Rewards.ClaimDaily(s, w, rng), nil, "twice in one day")
	Expect(Rewards.ClaimDaily(s, { Now = NOW + 86400 }, rng))
	Eq(s.Data.Daily.Streak, 2)
	Expect(Rewards.ClaimDaily(s, { Now = NOW + 86400 * 4 }, rng))
	Eq(s.Data.Daily.Streak, 1, "missed days reset the streak")
	-- day 7 then wraps to day 1
	s.Data.Daily.Streak = 6
	s.Data.Daily.LastDay = Rewards.DayIndex(NOW + 86400 * 4)
	local status = Rewards.DailyStatus(s, NOW + 86400 * 5)
	Eq(status.Day, 7)
	s.Data.Daily.Streak = 7
	s.Data.Daily.LastDay = Rewards.DayIndex(NOW + 86400 * 5)
	status = Rewards.DailyStatus(s, NOW + 86400 * 6)
	Eq(status.Day, 1)
end)

Test("playtime gifts need real session time", function()
	local s = newSession(100)
	local rng = H.Random.new(1)
	Eq(Rewards.ClaimPlaytime(s, 1, 100 + 60, world(), rng), nil)
	Expect(Rewards.ClaimPlaytime(s, 1, 100 + 5 * 60, world(), rng))
	Eq(Rewards.ClaimPlaytime(s, 1, 100 + 6 * 60, world(), rng), nil, "twice")
	Eq(Rewards.ClaimPlaytime(s, 99, 1e9, world(), rng), nil, "bad index")
end)

Test("quests track taps and reset daily", function()
	local s = newSession()
	local rng = H.Random.new(1)
	Eq(Rewards.ClaimQuest(s, "Taps", world(), rng), nil)
	for i = 1, 200 do
		Growth.Tap(s, 5, world(), i) -- 1000 taps
	end
	Expect(Rewards.ClaimQuest(s, "Taps", world(), rng))
	Eq(Rewards.ClaimQuest(s, "Taps", world(), rng), nil, "twice")
	Rewards.EnsureQuestDay(s, NOW + 86400)
	Eq(s.Data.Quests.Progress.Taps, 0)
end)

Test("achievements unlock once and pay gems", function()
	local s = newSession()
	s.Data.BestHeight = 100 * 100
	Rewards.CheckAchievements(s)
	Expect(s.Data.Achievements.H1 and s.Data.Achievements.H10 and s.Data.Achievements.H100)
	local gems = s.Data.Gems
	Rewards.CheckAchievements(s)
	Eq(s.Data.Gems, gems, "no double pay")
end)

Test("milestones and zone unlocks are announced once", function()
	local s = newSession()
	Growth.AddHeight(s, 2000, world())
	local zone, milestone = 0, 0
	for _, out in Session.TakeOut(s) do
		if out.Name == "ZoneUnlocked" then
			zone += 1
		end
		if out.Milestone then
			milestone += 1
		end
	end
	Eq(zone, 1, "Normal World unlocked")
	Eq(milestone, 1, "grew out of the grass")
	Growth.AddHeight(s, 1, world())
	Eq(#s.Out, 0)
end)

Test("coin rewards scale with progress and ignore temporary boosts", function()
	local s = newSession()
	local rng = H.Random.new(1)
	Rewards.Grant(s, { Kind = "Coins", Taps = 100 }, world(), rng)
	local early = s.Data.Coins
	local s2 = newSession()
	s2.Data.TapLevel = 20
	s2.Data.Rebirths = 10
	Rewards.Grant(s2, { Kind = "Coins", Taps = 100 }, world(), rng)
	Expect(s2.Data.Coins > early * 100)
	local s3 = newSession()
	Boosts.Add(s3, "SuperGrowth", 1)
	Boosts.Activate(s3, "SuperGrowth")
	Rewards.Grant(s3, { Kind = "Coins", Taps = 100 }, world(EventConfig.Events.GoldenMinute), rng)
	Eq(s3.Data.Coins, early, "boosts/events must not inflate rewards")
end)

Test("event multipliers apply to taps", function()
	local s = newSession()
	local _, gain = Growth.Tap(s, 1, world(EventConfig.Events.MegaGrowth), 0)
	Eq(gain, 10)
	local s2 = newSession()
	Growth.Tap(s2, 1, world(EventConfig.Events.DoubleTap), 0)
	Eq(s2.Data.Taps, 2)
	Expect(s2.EventTapped)
end)

Test("zone multiplier only counts through the verified zone index", function()
	local s = newSession()
	s.ZoneIndex = 3
	local rates = Mults.Rates(s, world())
	Near(rates.Zone, ZoneConfig.Zones[3].Multiplier, 1e-9)
end)

---------------------------------------------------------------------------
H.Section("balance")
---------------------------------------------------------------------------
_G.BALANCE_QUIET = true
local Sim = require("./balance")
Test("first minutes: upgrade < 15 s, 10 m < 90 s, first rebirth 2-5 min", function()
	local r = Sim.Run(6, 30, false)
	Expect(r.FirstUpgrade and r.FirstUpgrade <= 15, "first upgrade at " .. tostring(r.FirstUpgrade))
	Expect(r.Reach[10] and r.Reach[10] <= 90, "10 m at " .. tostring(r.Reach[10]))
	Expect(r.FirstRebirth and r.FirstRebirth >= 120 and r.FirstRebirth <= 300, "rebirth at " .. tostring(r.FirstRebirth))
	Expect(r.Reach[1e3] and r.Reach[1e3] <= 15 * 60, "1K m at " .. tostring(r.Reach[1e3]))
end)

if not H.Finish() then
	process.exit(1)
end
