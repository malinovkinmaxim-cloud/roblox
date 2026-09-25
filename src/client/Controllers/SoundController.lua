--[[
	SoundController - simple local UI / feedback sounds (built-in engine sounds only,
	so nothing can be moderated or fail to load for copyright reasons).
]]

local SoundService = game:GetService("SoundService")

local SoundController = {}

local SOUNDS = {
	Click = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.4 },
	Checkpoint = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Speed = 1.1 },
	Death = { Id = "rbxasset://sounds/uuhhh.mp3", Volume = 0.5 },
	Reveal = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.7, Speed = 0.8 },
	Finish = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8, Speed = 0.75 },
	Coin = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.45, Speed = 1.6 },
	Toast = { Id = "rbxasset://sounds/button.wav", Volume = 0.3 },
	Launch = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.6, Speed = 1.3 },
	Freeze = { Id = "rbxasset://sounds/snap.mp3", Volume = 0.6 },
}

function SoundController:Init(controllers)
	self.Controllers = controllers
	self.Sounds = {}
	local folder = Instance.new("Folder")
	folder.Name = "DoppelSounds"
	folder.Parent = SoundService
	for name, info in SOUNDS do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = info.Id
		sound.Volume = info.Volume or 0.5
		sound.PlaybackSpeed = info.Speed or 1
		sound.Parent = folder
		self.Sounds[name] = sound
	end
end

function SoundController:Enabled(): boolean
	local profile = self.Controllers.ClientState.Profile
	return not (profile and profile.Settings and profile.Settings.Sfx == false)
end

function SoundController:Play(name: string)
	if not self:Enabled() then
		return
	end
	local sound = self.Sounds[name]
	if sound then
		sound:Play()
	end
end

function SoundController:Get(name: string): Sound?
	return self.Sounds[name]
end

return SoundController
