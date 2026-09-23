local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

local Store = require(Shared.Utilities.Store)

--> Counts, for every player, how many of the others in the server are their Roblox friends, and
--> publishes it on the Player for Store.FriendMultiplier. Asked once per pair, when the second of
--> the two joins, and forgotten when either leaves. Nothing the client says is involved.

local FriendService = {
	Name = "FriendService",

	--> who is friends with whom, both ways round, among the players here
	Friends = {} :: { [Player]: { [Player]: boolean } },
}

function FriendService:_Publish(Player: Player)
	local Count = 0

	for Other in self.Friends[Player] or {} do
		if Other.Parent then
			Count += 1
		end
	end

	Player:SetAttribute(Store.FriendsAttribute, Count)
end

function FriendService:_Link(Player: Player, Other: Player)
	local Mine = self.Friends[Player]
	local Theirs = self.Friends[Other]

	if not Mine or not Theirs then
		return
	end

	Mine[Other] = true
	Theirs[Player] = true

	self:_Publish(Player)
	self:_Publish(Other)
end

function FriendService:_HandlePlayer(Player: Player)
	self.Friends[Player] = {}
	Player:SetAttribute(Store.FriendsAttribute, 0)

	for _, Other in Players:GetPlayers() do
		if Other == Player then
			continue
		end

		--> a web call per pair, so each one is asked on its own and a slow answer holds up nobody.
		--> A failed call counts as not friends: the boost is a bonus, and it is asked again on the
		--> next join of either of them
		task.spawn(function()
			local Ok, IsFriend = pcall(Player.IsFriendsWithAsync, Player, Other.UserId)

			if not Ok then
				warn(`[Friends] could not ask whether {Player.Name} and {Other.Name} are friends: {IsFriend}`)
				return
			end

			if IsFriend then
				self:_Link(Player, Other)
			end
		end)
	end
end

function FriendService:Init()
	for _, Player in Players:GetPlayers() do
		self:_HandlePlayer(Player)
	end

	Players.PlayerAdded:Connect(function(Player: Player)
		self:_HandlePlayer(Player)
	end)

	Players.PlayerRemoving:Connect(function(Player: Player)
		local Mine = self.Friends[Player]

		self.Friends[Player] = nil

		for Other in Mine or {} do
			local Theirs = self.Friends[Other]

			if Theirs then
				Theirs[Player] = nil
				self:_Publish(Other)
			end
		end
	end)
end

return FriendService
