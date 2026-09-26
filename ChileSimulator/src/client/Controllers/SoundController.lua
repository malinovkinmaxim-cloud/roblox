--[[
	SoundController - all sounds use sound files shipped with the Roblox client
	(rbxasset://sounds/...), so nothing can be moderated, go private or fail to load.

	Rare events sound MUCH bigger than a tap: they are built as layered arpeggios from the
	same samples (pitch = musical interval), e.g. Secret pet = 8-note rising run + whoosh.
	A small pool per sound lets fast taps overlap without cutting each other off.
]]

local SoundService = game:GetService("SoundService")

local SoundController = {}

local FILES = {
	Click = "rbxasset://sounds/clickfast.wav",
	Ping = "rbxasset://sounds/electronicpingshort.wav",
	Swoosh = "rbxasset://sounds/swoosh.wav",
	Button = "rbxasset://sounds/button.wav",
	Snap = "rbxasset://sounds/snap.mp3",
	Thump = "rbxasset://sounds/action_jump_land.mp3",
	Hop = "rbxasset://sounds/action_jump.mp3",
}

local POOL = 5

-- semitone -> playback speed
local function st(n: number): number
	return 2 ^ (n / 12)
end

-- name -> list of { File, Speed, Volume, Delay }
local CUES = {
	Tap = { { "Click", 1, 0.35 } },
	TapBig = { { "Click", 1, 0.35 }, { "Hop", 1.5, 0.18 } },
	TapHuge = { { "Click", 0.9, 0.4 }, { "Swoosh", 1.9, 0.25 } },
	Click = { { "Button", 1.1, 0.25 } },
	Error = { { "Button", 0.6, 0.3 } },
	Upgrade = { { "Ping", st(0), 0.35 }, { "Ping", st(7), 0.3, 0.07 } },
	Growth = { { "Ping", st(5), 0.3 } },
	BigGrowth = { { "Ping", st(0), 0.45 }, { "Ping", st(4), 0.45, 0.09 }, { "Ping", st(7), 0.45, 0.18 }, { "Ping", st(12), 0.5, 0.27 }, { "Swoosh", 1.2, 0.3, 0.27 } },
	NewZone = { { "Swoosh", 0.8, 0.4 }, { "Ping", st(0), 0.5, 0.1 }, { "Ping", st(4), 0.5, 0.2 }, { "Ping", st(7), 0.5, 0.3 }, { "Ping", st(11), 0.5, 0.4 }, { "Ping", st(12), 0.55, 0.5 } },
	Shrink = { { "Swoosh", 0.45, 0.55 }, { "Ping", st(12), 0.3 }, { "Ping", st(7), 0.3, 0.08 }, { "Ping", st(0), 0.3, 0.16 }, { "Ping", st(-5), 0.3, 0.24 } },
	Boom = { { "Thump", 0.45, 0.8 }, { "Snap", 0.6, 0.5 }, { "Swoosh", 1.4, 0.4 } },
	Rebirth = { { "Ping", st(0), 0.5 }, { "Ping", st(4), 0.5, 0.08 }, { "Ping", st(7), 0.5, 0.16 }, { "Ping", st(12), 0.55, 0.24 }, { "Ping", st(16), 0.55, 0.32 }, { "Ping", st(19), 0.6, 0.4 }, { "Ping", st(24), 0.6, 0.48 } },
	Reward = { { "Ping", st(7), 0.4 }, { "Ping", st(12), 0.4, 0.08 } },
	Achievement = { { "Ping", st(0), 0.45 }, { "Ping", st(7), 0.45, 0.1 }, { "Ping", st(12), 0.5, 0.2 } },
	Chest = { { "Ping", st(12), 0.4 }, { "Ping", st(16), 0.4, 0.06 }, { "Ping", st(19), 0.4, 0.12 } },
	Event = { { "Swoosh", 0.7, 0.5 }, { "Ping", st(-5), 0.45, 0.05 }, { "Ping", st(0), 0.45, 0.15 }, { "Ping", st(-5), 0.45, 0.25 }, { "Ping", st(0), 0.5, 0.35 } },
	EggShake = { { "Snap", 1.4, 0.25 } },
	EggCrack = { { "Snap", 0.8, 0.5 }, { "Swoosh", 1.5, 0.3 } },
	PetCommon = { { "Ping", st(7), 0.35 } },
	PetRare = { { "Ping", st(4), 0.4 }, { "Ping", st(11), 0.4, 0.08 } },
	PetLegendary = { { "Swoosh", 1, 0.4 }, { "Ping", st(0), 0.5 }, { "Ping", st(4), 0.5, 0.08 }, { "Ping", st(7), 0.5, 0.16 }, { "Ping", st(12), 0.55, 0.24 }, { "Ping", st(16), 0.55, 0.32 } },
	PetSecret = {
		{ "Thump", 0.5, 0.7 },
		{ "Swoosh", 0.6, 0.6 },
		{ "Ping", st(-12), 0.55, 0.1 },
		{ "Ping", st(-5), 0.55, 0.18 },
		{ "Ping", st(0), 0.55, 0.26 },
		{ "Ping", st(3), 0.55, 0.34 },
		{ "Ping", st(7), 0.6, 0.42 },
		{ "Ping", st(12), 0.6, 0.5 },
		{ "Ping", st(15), 0.6, 0.58 },
		{ "Ping", st(19), 0.65, 0.66 },
		{ "Swoosh", 1.6, 0.5, 0.66 },
	},
	Teleport = { { "Swoosh", 1.2, 0.4 } },
}

function SoundController:Init(controllers)
	self.Controllers = controllers
	self.Pools = {}
	self.Index = {}
	local folder = Instance.new("Folder")
	folder.Name = "ChileSounds"
	folder.Parent = SoundService
	for name, id in FILES do
		local pool = {}
		for i = 1, POOL do
			local sound = Instance.new("Sound")
			sound.Name = name .. i
			sound.SoundId = id
			sound.Parent = folder
			pool[i] = sound
		end
		self.Pools[name] = pool
		self.Index[name] = 1
	end
end

function SoundController:Start() end

function SoundController:Enabled(): boolean
	return self.Controllers.ClientData:Setting("Sfx")
end

function SoundController:PlayFile(file: string, speed: number, volume: number)
	local pool = self.Pools[file]
	if not pool then
		return
	end
	local i = self.Index[file]
	self.Index[file] = i % #pool + 1
	local sound = pool[i]
	sound.PlaybackSpeed = speed
	sound.Volume = volume
	sound.TimePosition = 0
	sound:Play()
end

-- Play a cue. pitch multiplies every layer (used for tap pitch variation).
function SoundController:Play(name: string, pitch: number?)
	if not self:Enabled() then
		return
	end
	local cue = CUES[name]
	if not cue then
		return
	end
	local p = pitch or 1
	for _, layer in cue do
		local file, speed, volume, delay = layer[1], layer[2], layer[3], layer[4]
		if delay and delay > 0 then
			task.delay(delay, function()
				self:PlayFile(file, speed * p, volume)
			end)
		else
			self:PlayFile(file, speed * p, volume)
		end
	end
end

return SoundController
