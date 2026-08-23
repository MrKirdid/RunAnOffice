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

local Types = Kmdr.types

--> Picks the slot to fill and says why it could not, so the caller gets a reason per player
--> instead of one silent failure for the whole command.
local function ResolveSlot(Data: any, Plot: Model, Floor: number?, Slot: number?): (number?, number?, string?)
	if not Floor then
		local NextFloor, NextSlot = DeskData.GetNextAvailable(Data, Plot)

		if not NextFloor or not NextSlot then
			return nil, nil, "every unlocked floor is full"
		end

		return NextFloor, NextSlot
	end

	local Count = DeskPlacements.GetCount(Plot, Floor)

	if Count == 0 then
		return nil, nil, `floor {Floor} has no desk placements`
	end

	if Slot then
		if Slot < 1 or Slot > Count then
			return nil, nil, `floor {Floor} only has slots 1 to {Count}`
		end

		if DeskData.Get(Data, Floor, Slot) then
			return nil, nil, `floor {Floor} slot {Slot} is taken, remove it first`
		end

		return Floor, Slot
	end

	local Taken = DeskData.GetTaken(Data, Floor)

	for Index = 1, Count do
		if not Taken[Index] then
			return Floor, Index
		end
	end

	return nil, nil, `floor {Floor} is full`
end

local Definition = Kmdr.defineCommand({
	name = "desk",
	description = "give drops a desk into a plot, rolling its three parts like a purchase unless a "
		.. "variant is named, and taking the next free slot unless a floor and slot are. remove clears "
		.. "one slot, freeing it to be bought again. Leave floor and slot out to let it pick.",
	group = "admin",
	args = {
		Action = ConsoleTypes.DeskAction("give a desk or remove one"),
		Targets = Types.players("Whose plot to work on"),
		Floor = Types.integer("Which floor. Picked for you when left out"):optional(),
		Slot = Types.integer("Which desk slot on that floor. Picked for you when left out"):optional(),
		Variant = ConsoleTypes.Variant("give only: force all three parts to this variant"):optional(),
	},
})

return Kmdr.implement(Definition, function(_Context, Args)
	local Lines = {}

	for _, Target in Args.Targets do
		local Data = PlayerData[Target]
		local Plot = PlotService:GetPlot(Target)

		if not Data then
			table.insert(Lines, `{Target.Name}: no loaded data.`)
			continue
		end

		if not Plot then
			table.insert(Lines, `{Target.Name}: no plot.`)
			continue
		end

		if Args.Action == "remove" then
			if not Args.Floor or not Args.Slot then
				table.insert(Lines, `{Target.Name}: remove needs both a floor and a slot.`)
				continue
			end

			local Desk = DeskData.Get(Data, Args.Floor, Args.Slot)

			if not Desk then
				table.insert(Lines, `{Target.Name}: floor {Args.Floor} slot {Args.Slot} is already empty.`)
				continue
			end

			--> Clearing the key replicates as a removal, which is what tears down the model
			Desk(nil)

			table.insert(Lines, `{Target.Name}: cleared floor {Args.Floor} slot {Args.Slot}.`)
			continue
		end

		local Floor, Slot, Reason = ResolveSlot(Data, Plot, Args.Floor, Args.Slot)

		if not Floor or not Slot then
			table.insert(Lines, `{Target.Name}: {Reason}.`)
			continue
		end

		--> No variant named means it rolls exactly like a purchase would, luck and all
		local Desk = if Args.Variant
			then { Computer = Args.Variant, Keyboard = Args.Variant, Monitor = Args.Variant }
			else Rolling.RollDesk(Data.Luck())

		--> Writing the key replicates, which is what tells the client to spawn and roll it
		DeskData.Unlock(Data, Floor).Desks[Slot](Desk)

		table.insert(Lines, `{Target.Name}: floor {Floor} slot {Slot} - {Desk.Computer}/{Desk.Keyboard}/{Desk.Monitor}`)
	end

	return table.concat(Lines, "\n")
end)
