--> What each node in the tree actually does. Configs.Upgrades owns where a node sits, what it is
--> called and what it costs -- that file is rewritten wholesale by the tree editor plugin, so
--> nothing that is not layout may live in it. This is the other half: same ids, keyed to the
--> effect they run.

--> An effect runs exactly once, on the server, the moment the node is bought, and every one of
--> them writes into saved data. Nothing replays them on join: the save already holds the result,
--> so rejoining with Cash IV owned reads a 3.75x multiplier rather than multiplying again.
--> That also means a definition may never be written as "recompute from the owned set" -- it is a
--> one time nudge to a number, and changing an amount here only affects purchases made after it.

--> A node with no definition is still buyable and still saves; it just does nothing yet, which is
--> what a placeholder in the tree should do rather than erroring on press.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Upgrades = require(Shared.Configs.Upgrades)

export type Context = {
	Player: Player,
	--> the player's PlayerData value, so an effect writes straight into the save
	Data: any,
	Id: string,
}

export type Definition = {
	--> one line of plain english for tooltips and the editor; nothing renders it yet
	Effect: string,
	OnPurchase: (Context) -> (),
}

--> Roll slots are 0-16 over the wire, so seventeen pads is the ceiling however many are bought.
local MaxPads = 17

local function AddLuck(Amount: number)
	return function(Context: Context)
		Context.Data.Luck(function(Current: number)
			return Current + Amount
		end)
	end
end

local function AddPads(Amount: number)
	return function(Context: Context)
		Context.Data.RerollPads(function(Current: number)
			return math.min(Current + Amount, MaxPads)
		end)
	end
end

--> Multipliers are added to rather than multiplied together: four cash nodes at +0.25 each land on
--> 2x, which is a curve that stays readable next to the prices in the tree.
local function AddMultiplier(Name: string, Amount: number)
	return function(Context: Context)
		Context.Data.Multipliers[Name](function(Current: number)
			return Current + Amount
		end)
	end
end

local function AddDefense(Amount: number)
	return function(Context: Context)
		Context.Data.Defense(function(Current: number)
			return Current + Amount
		end)
	end
end

local Definitions: { [string]: Definition } = {
	--> Cash: scales everything the plot pays out, applied in RevenueService.
	CashI = { Effect = "+25% cash from desks", OnPurchase = AddMultiplier("Cash", 0.25) },
	CashII = { Effect = "+50% cash from desks", OnPurchase = AddMultiplier("Cash", 0.5) },
	CashIII = { Effect = "+100% cash from desks", OnPurchase = AddMultiplier("Cash", 1) },
	CashIV = { Effect = "+200% cash from desks", OnPurchase = AddMultiplier("Cash", 2) },

	--> Luck: the same number every roll in the game reads, so this moves parts, desks and hires.
	LuckyI = { Effect = "+0.25 luck", OnPurchase = AddLuck(0.25) },
	LuckyII = { Effect = "+0.5 luck", OnPurchase = AddLuck(0.5) },
	LuckyIII = { Effect = "+1 luck", OnPurchase = AddLuck(1) },
	LuckyIV = { Effect = "+2 luck", OnPurchase = AddLuck(2) },
	LuckyV = { Effect = "+4 luck", OnPurchase = AddLuck(4) },
	Luckiest = { Effect = "+10 luck", OnPurchase = AddLuck(10) },
	LegendaryChances = { Effect = "+1.5 luck", OnPurchase = AddLuck(1.5) },
	MythicChances = { Effect = "+3 luck", OnPurchase = AddLuck(3) },
	GodlyChances = { Effect = "+8 luck", OnPurchase = AddLuck(8) },

	--> Employees: how fast a bought hire walks to the desk it was bought for.
	FasterEmployees = { Effect = "Employees walk 15% faster", OnPurchase = AddMultiplier("EmployeeSpeed", 0.15) },
	FasterEmployeesII = { Effect = "Employees walk 25% faster", OnPurchase = AddMultiplier("EmployeeSpeed", 0.25) },
	--> Faster Employees III
	NewNode2 = { Effect = "Employees walk 35% faster", OnPurchase = AddMultiplier("EmployeeSpeed", 0.35) },

	--> Rolling: how quickly the spin resolves, and how many pads it spins across.
	SmartRoller = { Effect = "Rolls spin 15% faster", OnPurchase = AddMultiplier("RollSpeed", 0.15) },
	FasterRolls = { Effect = "Rolls spin 20% faster", OnPurchase = AddMultiplier("RollSpeed", 0.2) },
	FasterRollsPlus = { Effect = "Rolls spin 30% faster", OnPurchase = AddMultiplier("RollSpeed", 0.3) },
	--> Fastest Rolls
	NewNode5 = { Effect = "Rolls spin 50% faster", OnPurchase = AddMultiplier("RollSpeed", 0.5) },
	--> Master Rolling
	MegaRoller = { Effect = "Rolls spin 25% faster", OnPurchase = AddMultiplier("RollSpeed", 0.25) },

	--> More Rollers
	HypeRoller = { Effect = "+2 roll pads", OnPurchase = AddPads(2) },
	--> Even More Rollers
	NewNode6 = { Effect = "+2 roll pads", OnPurchase = AddPads(2) },
	--> Super Many Rollers
	GigaRoller = { Effect = "+2 roll pads", OnPurchase = AddPads(2) },
	--> Final Roller
	NewNode8 = { Effect = "+2 roll pads", OnPurchase = AddPads(2) },

	--> Defense: the purple branch. Stealing is not built yet, so this only banks the level for
	--> BaseLockingService to read once it is.
	NewNode = { Effect = "+1 base defense", OnPurchase = AddDefense(1) },
	NewNode3 = { Effect = "+2 base defense", OnPurchase = AddDefense(2) },
	NewNode4 = { Effect = "+3 base defense", OnPurchase = AddDefense(3) },
}

--> Loud at require time rather than on a press months later: a node renamed in the editor leaves
--> its definition pointing at nothing, and the upgrade silently stops doing anything.
for Id in Definitions do
	if not Upgrades.List[Id] then
		warn(`[Upgrades] "{Id}" has an effect but is not a node in Configs.Upgrades`)
	end
end

return Definitions
