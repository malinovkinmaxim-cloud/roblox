--[[
	SoundController - every sound is built from files shipped with the Roblox client
	(rbxasset://sounds/...), so nothing can be moderated, go private or fail to load.

	A cue is a list of layers { file, playback speed, volume, delay }. Pitch = musical interval,
	so the same few samples make pickups, arpeggios, sirens and big booms. Frequent cues (hits,
	kills, XP) are rate-limited so a horde never becomes noise; meme sounds are rare cues.
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
	Oof = "rbxasset://sounds/uuhhh.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
}

local POOL = 6

local function st(n: number): number
	return 2 ^ (n / 12)
end

-- name -> { { file, speed, volume, delay? } }, MinGap (seconds between plays)
local CUES = {
	Click = { { "Button", 1.1, 0.25 } },
	Error = { { "Button", 0.6, 0.3 } },
	Hit = { { "Click", 1.3, 0.12 } },
	Kill = { { "Snap", 1.2, 0.18 } },
	XP = { { "Ping", st(12), 0.08 } },
	Coin = { { "Ping", st(19), 0.18 }, { "Ping", st(24), 0.14, 0.05 } },
	Heal = { { "Ping", st(7), 0.25 }, { "Ping", st(12), 0.2, 0.06 } },
	Hurt = { { "Thump", 0.7, 0.45 }, { "Click", 0.5, 0.25 } },
	LevelUp = { { "Ping", st(0), 0.4 }, { "Ping", st(4), 0.4, 0.07 }, { "Ping", st(7), 0.4, 0.14 }, { "Ping", st(12), 0.45, 0.21 }, { "Swoosh", 1.3, 0.3, 0.21 } },
	Pick = { { "Ping", st(7), 0.35 }, { "Ping", st(12), 0.3, 0.06 } },
	Rare = { { "Swoosh", 0.8, 0.4 }, { "Ping", st(0), 0.45 }, { "Ping", st(4), 0.45, 0.08 }, { "Ping", st(7), 0.45, 0.16 }, { "Ping", st(12), 0.5, 0.24 }, { "Ping", st(16), 0.5, 0.32 }, { "Ping", st(19), 0.55, 0.4 } },
	CardHover = { { "Click", 1.6, 0.12 } },
	Reroll = { { "Swoosh", 1.6, 0.35 } },
	-- weapons
	Blast = { { "Click", 0.9, 0.1 } },
	Hammer = { { "Thump", 0.5, 0.6 }, { "Ping", st(24), 0.25, 0.02 } },
	Beam = { { "Swoosh", 1.8, 0.25 } },
	Zap = { { "Snap", 1.8, 0.25 }, { "Click", 2, 0.12 } },
	Slam = { { "Thump", 0.35, 0.8 }, { "Snap", 0.5, 0.5 } },
	Boom = { { "Thump", 0.4, 0.7 }, { "Snap", 0.6, 0.45 }, { "Swoosh", 1.3, 0.3 } },
	Blast67 = { { "Thump", 0.3, 0.8 }, { "Ping", st(-5), 0.4 }, { "Ping", st(0), 0.4, 0.12 } },
	Freeze = { { "Ping", st(24), 0.3 }, { "Swoosh", 2, 0.25 } },
	VineBoom = { { "Thump", 0.25, 1 }, { "Snap", 0.35, 0.7 } },
	-- moments
	Banner = { { "Swoosh", 0.9, 0.35 } },
	Siren = { { "Ping", st(0), 0.45 }, { "Ping", st(6), 0.45, 0.25 }, { "Ping", st(0), 0.45, 0.5 }, { "Ping", st(6), 0.45, 0.75 }, { "Ping", st(0), 0.5, 1.0 }, { "Ping", st(6), 0.5, 1.25 } },
	BossSpawn = { { "Thump", 0.25, 1 }, { "Snap", 0.4, 0.6 }, { "Swoosh", 0.5, 0.5 } },
	BossDeath = { { "Thump", 0.3, 1 }, { "Snap", 0.45, 0.7 }, { "Ping", st(0), 0.5, 0.3 }, { "Ping", st(7), 0.5, 0.4 }, { "Ping", st(12), 0.55, 0.5 }, { "Ping", st(19), 0.55, 0.6 } },
	Event = { { "Swoosh", 0.7, 0.5 }, { "Ping", st(-5), 0.45, 0.05 }, { "Ping", st(0), 0.45, 0.15 }, { "Ping", st(-5), 0.45, 0.25 }, { "Ping", st(0), 0.5, 0.35 } },
	Six = { { "Thump", 0.3, 0.9 }, { "Ping", st(-3), 0.5 } },
	Seven = { { "Thump", 0.28, 0.9 }, { "Ping", st(4), 0.5 } },
	SixSeven = { { "Thump", 0.22, 1 }, { "Snap", 0.3, 0.8 }, { "Oof", 1.6, 0.5, 0.05 }, { "Ping", st(12), 0.5, 0.1 } },
	Secret = { { "Swoosh", 0.6, 0.5 }, { "Ping", st(12), 0.5, 0.1 }, { "Ping", st(11), 0.5, 0.2 }, { "Ping", st(7), 0.5, 0.3 }, { "Ping", st(24), 0.55, 0.45 } },
	Goofy = { { "Oof", 1.8, 0.45 }, { "Hop", 1.4, 0.3, 0.1 } },
	Death = { { "Oof", 1, 0.8 }, { "Thump", 0.4, 0.6 } },
	Revive = { { "Swoosh", 0.8, 0.5 }, { "Ping", st(0), 0.5 }, { "Ping", st(7), 0.5, 0.1 }, { "Ping", st(12), 0.55, 0.2 } },
	Victory = { { "Ping", st(0), 0.5 }, { "Ping", st(4), 0.5, 0.12 }, { "Ping", st(7), 0.5, 0.24 }, { "Ping", st(12), 0.55, 0.36 }, { "Ping", st(7), 0.5, 0.52 }, { "Ping", st(12), 0.55, 0.64 }, { "Ping", st(16), 0.6, 0.76 }, { "Ping", st(24), 0.65, 0.9 } },
	RunOver = { { "Ping", st(7), 0.4 }, { "Ping", st(3), 0.4, 0.2 }, { "Ping", st(0), 0.45, 0.4 }, { "Thump", 0.5, 0.5, 0.4 } },
	Nuke = { { "Thump", 0.2, 1 }, { "Snap", 0.25, 0.9 }, { "Swoosh", 0.4, 0.7 } },
	Chest = { { "Ping", st(12), 0.4 }, { "Ping", st(16), 0.4, 0.06 }, { "Ping", st(19), 0.4, 0.12 } },
	Beat = { { "Thump", 0.55, 0.35 } },
	Splash = { { "Splash", 1.2, 0.35 } },
}

local MIN_GAP = { Hit = 0.05, Kill = 0.04, XP = 0.035, Blast = 0.08, Zap = 0.08, Coin = 0.05, CardHover = 0.05 }

function SoundController:Init(controllers)
	self.Controllers = controllers
	self.Pools = {}
	self.Index = {}
	self.LastPlay = {}
	local folder = Instance.new("Folder")
	folder.Name = "BrainrotSounds"
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

-- Play a cue. pitch multiplies every layer.
function SoundController:Play(name: string, pitch: number?, volume: number?)
	if not self:Enabled() then
		return
	end
	local cue = CUES[name]
	if not cue then
		return
	end
	local gap = MIN_GAP[name]
	if gap then
		local now = os.clock()
		if now - (self.LastPlay[name] or 0) < gap then
			return
		end
		self.LastPlay[name] = now
	end
	local p = pitch or 1
	local v = volume or 1
	for _, layer in cue do
		local delay = layer[4]
		if delay and delay > 0 then
			task.delay(delay, function()
				self:PlayFile(layer[1], layer[2] * p, layer[3] * v)
			end)
		else
			self:PlayFile(layer[1], layer[2] * p, layer[3] * v)
		end
	end
end

return SoundController
