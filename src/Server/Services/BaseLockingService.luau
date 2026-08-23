local Players = game:GetService("Players")
local BaseLockingService = {}

local BaseStates = {} :: { [Player]: number? }
function BaseLockingService:HandlePlayer(Player: Player)
	-- ...

	local Test = "test"

	-- ...
end

function BaseLockingService:Init()
	for _, Player in Players:GetPlayers() do
		self:HandlePlayer(Player)
	end

	Players.PlayerAdded:Connect(function(Player)
		self:HandlePlayer(Player)
	end)
end

return BaseLockingService
