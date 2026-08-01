local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local networkingServer = require(Shared.Networking.networkingServer)
local PlayerData = require(Shared.PlayerData).server
local Parts = require(Shared.Configs.Parts)

local Generator = Random.new()

type Result = { Variant: string, Component: string }

local function Pick(Entries: { [string]: { Value: number, Rarity: number } }): string
	local Total = 0
	local Last: string? = nil
	for Name, Entry in Entries do
		Total += Entry.Rarity
		Last = Name
	end

	if not Last then
		error("No entries to roll from")
	end

	local Roll = Generator:NextNumber() * Total
	for Name, Entry in Entries do
		Roll -= Entry.Rarity
		if Roll <= 0 then
			return Name
		end
	end

	--> Floating point drift can leave Roll a hair above zero after the last subtraction
	return Last :: string
end

local RollingService = {}

function RollingService:Init()
	networkingServer.Roll.On(function(Player): { Player: any, Results: { [number]: Result } }
		local Data = PlayerData[Player]

		local RollCount = Data.Upgrades.RollsUnlocked()

		local Results = {}
		for Slot = 0, RollCount - 1 do
			Results[Slot] = {
				Variant = Pick(Parts.Variants),
				Component = Pick(Parts.BaseValues),
			}
		end

		return { Player = Player, Results = Results }
	end)
end

return RollingService
