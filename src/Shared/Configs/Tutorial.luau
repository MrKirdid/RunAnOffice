local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local DeskData = require(Shared.Utilities.DeskData)

--> Every step of the tutorial, in the order it is played. The server owns where a player is in it:
--> each step names what the save looks like once it is done, and the moment the save satisfies
--> that the step is over. Text is what the bar at the top of the screen types out and Detail is
--> the line under it that says why. Module is the file under Shared.Tutorial.Stages that draws
--> the step on the client, and defaults to the step's Name.

export type Stage = {
	Name: string,
	Module: string?,
	Text: string,
	Detail: string?,
	Check: (Data: any) -> boolean,
}

--> The three parts the first desk is handed out with. The commonest variant there is, so the first
--> roll is a step up from every one of them.
local StarterVariant = "Mossy"

--> Whether any desk the player owns passes Test, given the parts and the seat on it.
local function AnyDesk(Data: any, Test: (any) -> boolean): boolean
	for _, Floor in DeskData.GetFloors(Data) do
		for _, Slot in DeskData.GetSlots(Data, Floor) do
			local Desk = DeskData.Get(Data, Floor, Slot)
			local Components = Desk and Desk()

			if type(Components) == "table" and Test(Components) then
				return true
			end
		end
	end

	return false
end

--> A part on the desk that is not one it started with.
local function HasBetterPart(Components: any): boolean
	for _, Name in { "Computer", "Keyboard", "Monitor" } do
		local Variant = Components[Name]

		if DeskData.IsPart(Variant) and Variant ~= StarterVariant then
			return true
		end
	end

	return false
end

--> A slot on the desk with no part on it yet: the gift over it has not been opened.
local function IsMissingPart(Components: any): boolean
	for _, Name in { "Computer", "Keyboard", "Monitor" } do
		if not DeskData.IsPart(Components[Name]) then
			return true
		end
	end

	return false
end

local function CountDesks(Data: any): number
	local Count = 0

	for _, Floor in DeskData.GetFloors(Data) do
		Count += #DeskData.GetSlots(Data, Floor)
	end

	return Count
end

local Stages: { Stage } = {
	{
		Name = "Roll",
		Text = "Press the roll button",
		Detail = "Rolling gives you parts. Rarer parts earn more cash",
		Check = function(Data: any): boolean
			return Data.TutorialRolled() == true
		end,
	},
	{
		Name = "PickUp",
		Text = "Pick up the part you just rolled",
		Detail = "Hold E on it. The green one is rarer than anything on your desk",
		Check = function(Data: any): boolean
			return Data.TutorialRolled() == true and Data.Holding().Component ~= nil
		end,
	},
	{
		Name = "Replace",
		Text = "Swap it onto your desk",
		Detail = "A desk earns off its three parts every second. Better parts, more cash",
		Check = function(Data: any): boolean
			return AnyDesk(Data, HasBetterPart)
		end,
	},
	{
		Name = "Hire",
		Text = "Hire an employee from the street",
		Detail = "Nobody at the desk means nobody typing. Employees turn parts into cash",
		Check = function(Data: any): boolean
			return Data.TutorialHires() >= 1
		end,
	},
	{
		Name = "BuyDesk",
		Text = "Buy a second desk at the board",
		Detail = "Every desk is one more employee earning for you",
		Check = function(Data: any): boolean
			return CountDesks(Data) >= 2
		end,
	},
	{
		Name = "OpenGifts",
		Text = "Open the gifts on your new desk",
		Detail = "Every gift is a free part. A desk missing one earns nothing",
		Check = function(Data: any): boolean
			return CountDesks(Data) >= 2 and not AnyDesk(Data, IsMissingPart)
		end,
	},
	{
		Name = "HireAgain",
		Module = "Hire",
		Text = "Hire someone for the new desk",
		Detail = "Cheaper employees earn less, but they are still earning",
		Check = function(Data: any): boolean
			return Data.TutorialHires() >= 2
		end,
	},
	{
		Name = "LockBase",
		Text = "Press the lock button by your door",
		Detail = "Keeps thieves out for a minute. Open bases can be robbed, yours and theirs",
		Check = function(Data: any): boolean
			return Data.TutorialLocked() == true
		end,
	},
	{
		Name = "Upgrades",
		Text = "Open Upgrades and buy your first one",
		Detail = "Upgrades boost everything you own. This first one is free",
		Check = function(Data: any): boolean
			return next(Data.Upgrades.Owned()) ~= nil
		end,
	},
}

local Tutorial = {
	Stages = Stages,
	StarterVariant = StarterVariant,

	--> What the first roll puts on the first pad, whatever the dice said: about one in eight, which
	--> is enough of a step up from the starter parts for the swap to mean something.
	FirstRollVariant = "Tree",

	--> A few presses of the roll button, once the tutorial is over and the player is rolling on their
	--> own, are rolled at many times their luck: not a guaranteed anything, just a press where the
	--> rare end of the table is close enough to touch. At 100x, about one press in six lands a
	--> Legendary somewhere on the nine pads and about one in two an Epic. Counted by press, ever.
	LuckyPresses = { [6] = true, [11] = true },
	LuckyMultiplier = 100,

	--> How long after the client comes up before the first step is shown. Just long enough for the
	--> plot to be there under the player.
	IntroDelay = 2,

	--> What the bar says once the last step is done, and how many fireworks go up with it.
	FinishText = "Tutorial done",
	Fireworks = 7,

	--> Frames of the hud put away for the length of the tutorial, from Root: everything that is
	--> not needed to get through it. Named by path so a hud cloned again on respawn is found again.
	HiddenBars = { "SideBar", "TopBar", "RewardBar" },

	--> What the bar says when a purchase is turned down, for the reasons a player can act on.
	Notices = {
		NoCash = "Not enough cash",
		NoSeat = "No free desk",
		NoAffordable = "Nobody affordable on the street right now",

		--> the good news, kept to a line
		DeskBought = "Desk bought",
	},
}

--> The index of a step by name, or nil for a name that is not a step.
function Tutorial.IndexOf(Name: string): number?
	for Index, Stage in Stages do
		if Stage.Name == Name then
			return Index
		end
	end

	return nil
end

--> Whether a save is on the named step right now.
function Tutorial.IsOn(Data: any, Name: string): boolean
	return Data.TutorialStage() == Tutorial.IndexOf(Name)
end

return Tutorial
