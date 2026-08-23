local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Server = script.Parent.Parent

local Kmdr = require(Shared.Packages.Kmdr)
local ConsoleTypes = require(Shared.Console.Types)
local PlotService = require(Server.Services.PlotService)
local DeskPlacements = require(Shared.Utilities.DeskPlacements)
local DeskData = require(Shared.Utilities.DeskData)
local PlayerData = require(Shared.PlayerData).server
local Rolling = require(Shared.Utilities.Rolling)
local Parts = require(Shared.Configs.Parts)

local Types = Kmdr.types

--> The roll packet is a u8(1..17) both ways, so anything outside that fails validation on send
local MinimumRolls, MaximumRolls = 1, 17

local Rarest = nil :: string?
for Name, Entry in Parts.Variants do
	if not Rarest or Entry.Rarity < Parts.Variants[Rarest].Rarity then
		Rarest = Name
	end
end

local function GiveCash(Data: any, Amount: number): string
	local New = Data.Cash(function(Current: number)
		return math.max(Current + Amount, 0)
	end)

	return `{New} cash`
end

local function GiveLuck(Data: any, Amount: number): string
	local Old = Data.Luck()
	local New = Data.Luck(function(Current: number)
		return math.max(Current + Amount, 0)
	end)

	--> Luck 0 leaves the rare end with no weight at all, which has no "1 in N" to print
	local Chance = Rolling.Chances(Parts.Variants, New)[Rarest]
	local Odds = if Chance > 0 then `1 in {math.floor(1 / Chance + 0.5)}` else "never"

	return `luck {Old} -> {New} ({Rarest} {Odds})`
end

local function SetRolls(Data: any, Amount: number): string
	if Amount < MinimumRolls or Amount > MaximumRolls then
		return `rolls must be {MinimumRolls} to {MaximumRolls}, the packet carries no more`
	end

	Data.RerollPads(math.floor(Amount))

	return `{math.floor(Amount)} reroll pads`
end

local function UnlockFloors(Data: any, Player: Player, Amount: number): string
	local Plot = PlotService:GetPlot(Player)
	local Floor = math.floor(Amount)

	if not Plot then
		return "no plot"
	end

	if Floor < 1 or DeskPlacements.GetCount(Plot, Floor) == 0 then
		return `floor {Floor} has no desk placements in the plot`
	end

	local Existing = {}
	for _, Unlocked in DeskData.GetFloors(Data) do
		Existing[Unlocked] = true
	end

	--> Everything up to the one asked for, so a plot cannot end up with floor 3 and no floor 2
	local Opened = {}

	for Index = 1, Floor do
		if not Existing[Index] and DeskPlacements.GetCount(Plot, Index) > 0 then
			DeskData.Unlock(Data, Index)
			table.insert(Opened, Index)
		end
	end

	if #Opened == 0 then
		return `already had every floor up to {Floor}`
	end

	return `unlocked floor {table.concat(Opened, ", ")}`
end

local Definition = Kmdr.defineCommand({
	name = "give",
	description = "Grants a stat to players. cash and luck add on top of what they have and take away "
		.. "when negative; rolls sets how many reroll pads are unlocked outright; floor unlocks every "
		.. "floor up to the number given.",
	group = "admin",
	args = {
		Stat = ConsoleTypes.Stat("cash, luck, rolls or floor"),
		Targets = Types.players("Who to give it to"),
		Amount = Types.number("How much. Added for cash and luck, set outright for rolls and floor"),
	},
})

return Kmdr.implement(Definition, function(_Context, Args)
	local Lines = {}

	for _, Target in Args.Targets do
		local Data = PlayerData[Target]

		if not Data then
			table.insert(Lines, `{Target.Name}: no loaded data.`)
			continue
		end

		local Result = if Args.Stat == "cash"
			then GiveCash(Data, Args.Amount)
			elseif Args.Stat == "luck" then GiveLuck(Data, Args.Amount)
			elseif Args.Stat == "rolls" then SetRolls(Data, Args.Amount)
			else UnlockFloors(Data, Target, Args.Amount)

		table.insert(Lines, `{Target.Name}: {Result}.`)
	end

	return table.concat(Lines, "\n")
end)
