local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local PlayerData = require(Shared.PlayerData).server
local TutorialConfigs = require(Shared.Configs.Tutorial)

local Stages = TutorialConfigs.Stages

--> Where every player is in the tutorial. The stage lives in the save and nothing but this writes
--> it: each step names what the save looks like once it is done, and the moment it does the step
--> is over. Nothing is taken from the client at all; the services that do the buying and rolling
--> write the flags the steps read.

local TutorialService = {
	Name = "TutorialService",
}

--> One past the last stage is done; anything else outside the list is a save from a build with a
--> different number of steps, and is pulled back onto it.
function TutorialService:Clamp(Stage: number): number
	return math.clamp(math.floor(Stage), 1, #Stages + 1)
end

function TutorialService:IsCompleted(Data: any): boolean
	return Data.TutorialStage() > #Stages
end

--> Walks the player forward through every step the save already satisfies. Run on join, so a
--> save from before the tutorial existed lands on the first step it has not done, and again on
--> every change, so a step is over the moment it is.
function TutorialService:Sweep(Data: any)
	while true do
		local Index = self:Clamp(Data.TutorialStage())
		local Stage = Stages[Index]

		if Index ~= Data.TutorialStage() then
			Data.TutorialStage(Index)
		end

		if not Stage or not Stage.Check(Data) then
			return
		end

		Data.TutorialStage(Index + 1)
	end
end

--> For the console: puts a player on a step. The save is swept straight after, so a step it
--> already satisfies is passed again at once; resetting the data is how a whole replay is had.
function TutorialService:SetStage(Player: Player, Stage: number): number?
	local Data = PlayerData[Player]

	if not Data then
		return nil
	end

	Data.TutorialStage(self:Clamp(Stage))
	self:Sweep(Data)

	return Data.TutorialStage()
end

function TutorialService:Init()
	local function HandlePlayer(Player: Player)
		local Data = PlayerData.Service:waitForData(Player)

		self:Sweep(Data)

		--> Bound to the root, which fires for anything underneath it, the stage itself included:
		--> that pass finds nothing left to do and returns. Deferred rather than run in the callback:
		--> a write made inside one is replicated before the write that fired it, so a sweep that
		--> advanced two steps in a row reached the client with the older step last.
		Data.Changed(function()
			task.defer(function()
				self:Sweep(Data)
			end)
		end)
	end

	for _, Player in Players:GetPlayers() do
		task.spawn(HandlePlayer, Player)
	end

	Players.PlayerAdded:Connect(HandlePlayer)
end

return TutorialService
