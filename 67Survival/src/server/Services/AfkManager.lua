--[[
	AfkManager - the AFK CAMP: heroes you are not playing rest at the camp and collect a
	small amount of coins, XP and fragments while you are away.

	  * capped: rewards stop growing after GameConfig.Afk.CapacityMinutes (2 h; 4 h with the
	    AFK Capacity pass), so the camp is a "come back later" bonus, never a farm
	  * slots: 1 free, 2 more for coins, +1 with the Extra AFK Hero Slot pass
	  * AFK Boost product: x2 rewards for 4 hours
	  * active play always gives much more (a 10 minute run ~ several hours of camp)

	Time is real (unix) time: the camp keeps counting while the player is offline.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Modules")

local Net = require(Shared.Net)
local GameConfig = require(Shared.GameConfig)
local MetaData = require(Shared.MetaData)
local HeroData = require(Shared.HeroData)

local Guard = require(script.Parent.Parent.Util.Guard)

local AfkManager = {}

local A = GameConfig.Afk

function AfkManager:Init(services)
	self.Services = services
end

function AfkManager:MaxSlots(session): number
	local extra = if self.Services.MonetizationManager:HasPass(session.Player, "ExtraHeroSlot") then 1 else 0
	return session.Data.Afk.SlotCount + extra
end

function AfkManager:CapacityMinutes(session): number
	local extra = if self.Services.MonetizationManager:HasPass(session.Player, "AfkCapacity") then A.CapacityPassMinutes else 0
	return A.CapacityMinutes + extra
end

local function heroesInCamp(afk, maxSlots: number): number
	local n = 0
	for i = 1, maxSlots do
		if afk.Slots[i] and afk.Slots[i] ~= "" then
			n += 1
		end
	end
	return n
end

--[[
	What the camp holds right now: coins, xp, fragments, accrued minutes (capped).
	Boosted minutes (AFK Boost) count double.
]]
function AfkManager:Pending(session, now: number?): (number, number, number, number)
	local afk = session.Data.Afk
	local t = now or os.time()
	if afk.Since <= 0 then
		return 0, 0, 0, 0
	end
	local heroes = heroesInCamp(afk, self:MaxSlots(session))
	if heroes == 0 then
		return 0, 0, 0, 0
	end
	local cap = self:CapacityMinutes(session) * 60
	local stop = math.min(t, afk.Since + cap)
	local seconds = math.max(0, stop - afk.Since)
	local boosted = math.max(0, math.min(stop, afk.BoostUntil) - afk.Since)
	local minutes = (seconds + boosted * (A.BoostMult - 1)) / 60
	local level = MetaData.Level(session.Data.XP)
	local levelMult = 1 + math.min(2, level * A.LevelBonus)
	local heroMinutes = minutes * heroes
	local coins = math.floor(heroMinutes * A.CoinsPerMinute * levelMult)
	local xp = math.floor(heroMinutes * A.XPPerMinute * levelMult)
	local fragments = math.floor(heroMinutes / A.FragmentMinutes)
	return coins, xp, fragments, seconds / 60
end

function AfkManager:Snapshot(session)
	local afk = session.Data.Afk
	local coins, xp, fragments, minutes = self:Pending(session)
	local maxSlots = self:MaxSlots(session)
	local slots = {}
	for i = 1, maxSlots do
		slots[i] = afk.Slots[i] or ""
	end
	local now = os.time()
	return {
		Slots = slots,
		MaxSlots = maxSlots,
		NextSlotCost = A.SlotCosts[afk.SlotCount + 1],
		Coins = coins,
		XP = xp,
		Fragments = fragments,
		Minutes = math.floor(minutes),
		CapMinutes = self:CapacityMinutes(session),
		Full = minutes >= self:CapacityMinutes(session) - 0.01,
		BoostLeft = math.max(0, afk.BoostUntil - now),
		Heroes = heroesInCamp(afk, maxSlots),
	}
end

function AfkManager:Claim(player: Player, quiet: boolean?)
	local session = self.Services.PlayerManager:Get(player)
	if not session then
		return
	end
	local afk = session.Data.Afk
	local coins, xp, fragments = self:Pending(session)
	local RM = self.Services.RewardManager
	local PM = self.Services.PlayerManager
	if coins + xp + fragments <= 0 then
		if not quiet then
			PM:Notify(player, "Nothing to claim yet. Your heroes are resting.", "Error")
		end
		return
	end
	RM:GiveCoins(session, coins)
	RM:GiveFragments(session, fragments)
	session.Data.XP += xp
	afk.Since = os.time()
	if not quiet then
		local text = string.format("AFK Camp: +%d coins, +%d XP", coins, xp) .. (if fragments > 0 then string.format(", +%d fragments", fragments) else "")
		PM:Notify(player, text, "Reward")
	end
	RM:CheckAchievements(session)
	PM:Sync(player)
end

function AfkManager:SetSlot(player: Player, index: number, heroKey: string)
	local session = self.Services.PlayerManager:Get(player)
	if not session then
		return
	end
	local afk = session.Data.Afk
	if index < 1 or index > self:MaxSlots(session) then
		return
	end
	if heroKey ~= "" and not (HeroData.ByKey[heroKey] and session.Data.Heroes[heroKey]) then
		return
	end
	-- the same hero can't rest in two slots
	for i, key in afk.Slots do
		if key == heroKey and heroKey ~= "" and i ~= index then
			afk.Slots[i] = ""
		end
	end
	-- the camp changes: bank what was earned with the old heroes first
	self:Claim(player, true)
	afk.Slots[index] = heroKey
	if afk.Since <= 0 or heroesInCamp(afk, self:MaxSlots(session)) == 0 then
		afk.Since = os.time()
	end
	self.Services.PlayerManager:Sync(player)
end

function AfkManager:BuySlot(player: Player)
	local session = self.Services.PlayerManager:Get(player)
	if not session then
		return
	end
	local afk = session.Data.Afk
	local cost = A.SlotCosts[afk.SlotCount + 1]
	local PM = self.Services.PlayerManager
	if not cost then
		PM:Notify(player, "All camp slots are open", "Error")
		return
	end
	if session.Data.Coins < cost then
		PM:Notify(player, "Not enough coins", "Error")
		return
	end
	session.Data.Coins -= cost
	afk.SlotCount += 1
	PM:Notify(player, "New AFK Camp slot!", "Success")
	PM:Sync(player)
end

-- AFK Boost product
function AfkManager:Boost(session, minutes: number)
	local afk = session.Data.Afk
	local now = os.time()
	afk.BoostUntil = math.max(now, afk.BoostUntil) + minutes * 60
end

function AfkManager:Start()
	Guard.Connect(Net.Event("AfkClaim"), { Rate = 1, Burst = 3 }, function(player)
		self:Claim(player)
	end)
	Guard.Connect(Net.Event("AfkSetSlot"), { Rate = 3, Burst = 6 }, function(player, index, key)
		local i = Guard.Int(index, 1, 8)
		if i and Guard.Str(key, 32) then
			self:SetSlot(player, i, key)
		end
	end)
	Guard.Connect(Net.Event("AfkBuySlot"), { Rate = 1, Burst = 2 }, function(player)
		self:BuySlot(player)
	end)
end

return AfkManager
