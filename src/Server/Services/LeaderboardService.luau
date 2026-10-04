local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage.Shared

local NetworkingServer = require(Shared.Networking.networkingServer)
local PlayerData = require(Shared.PlayerData).server

--> The two global boards by the road: cash earned and time played, across every server. Each
--> player's numbers go up to an OrderedDataStore every couple of minutes and on the way out, and
--> the top hundred of each come back down every few minutes and go to every client. Nothing the
--> client says is involved; it only draws what it is sent.

type Board = "Cash" | "Playtime"
type Entry = { UserId: number, Name: string, Value: number }
type Standings = { Board: Board, Entries: { Entry } }

local Boards: { Board } = { "Cash", "Playtime" }

--> Studio writes to boards of its own, so testing never puts anyone on the live ones.
local StorePrefix = if RunService:IsStudio() then "Dev" else "Prod"
local StoreVersion = 1

--> How often each player's numbers are written, and how often the boards are read back. A write
--> is two requests a player and a read two a server, far inside the budget either way.
local WriteInterval = 120
local ReadInterval = 300
local BoardSize = 100

--> how often time in the server is added to the save
local PlaytimeInterval = 30

--> Cash runs past what an OrderedDataStore can hold, which is a whole number under 2^63, and the
--> suffixes in Format go far beyond that. Kept as its log instead, which orders the same way and
--> stays a whole number well inside a double: twelve decimal places of log10 come back within a
--> few billionths of a percent, far finer than the board's 1.2M-style figures can show.
local LogScale = 1e12

local function Encode(Board: Board, Value: number): number
	if Board == "Cash" then
		return math.floor(math.log10(1 + math.max(Value, 0)) * LogScale)
	end

	return math.floor(math.max(Value, 0))
end

local function Decode(Board: Board, Stored: number): number
	if Board == "Cash" then
		return math.floor(10 ^ (Stored / LogScale) - 1 + 0.5)
	end

	return Stored
end

local function Read(Board: Board, Data: any): number
	return if Board == "Cash" then Data.TotalCashEarned() else Data.Playtime()
end

local LeaderboardService = {
	Name = "LeaderboardService",

	Stores = {} :: { [Board]: OrderedDataStore },

	--> what each board looked like last time it was read, for anyone who asks before the next
	Latest = {} :: { [Board]: Standings },

	--> display names already looked up, by user id, so a read only asks about newcomers
	Names = {} :: { [number]: string },

	--> when each player's time in the server was last added to the save
	Counted = {} :: { [Player]: number },
}

--> The time since the last count, into the save. Run on a timer and once more on the way out.
function LeaderboardService:_Count(Player: Player, Data: any)
	local Last = self.Counted[Player]

	if not Last then
		return
	end

	local Now = os.clock()
	self.Counted[Player] = Now

	Data.Playtime(function(Current: number)
		return Current + (Now - Last)
	end)
end

function LeaderboardService:_Write(UserId: number, Board: Board, Value: number)
	local Ok, Error = pcall(function()
		self.Stores[Board]:SetAsync(tostring(UserId), Encode(Board, Value))
	end)

	if not Ok then
		warn(`[Leaderboards] could not write {Board} for {UserId}: {Error}`)
	end
end

function LeaderboardService:_WritePlayer(Player: Player)
	local Data = PlayerData[Player]

	if not Data then
		return
	end

	for _, Board in Boards do
		self:_Write(Player.UserId, Board, Read(Board, Data))
	end
end

--> Display names for every id not already known, in one request. One that fails leaves the ids
--> nameless for this read and they are asked about again on the next.
function LeaderboardService:_Name(UserIds: { number })
	local Missing = {}

	for _, UserId in UserIds do
		if not self.Names[UserId] then
			table.insert(Missing, UserId)
		end
	end

	if #Missing == 0 then
		return
	end

	local Ok, Infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(Missing)
	end)

	if not Ok then
		warn(`[Leaderboards] could not look up {#Missing} names: {Infos}`)
		return
	end

	for _, Info in Infos do
		self.Names[Info.Id] = Info.DisplayName
	end
end

function LeaderboardService:_ReadBoard(Board: Board): Standings?
	local Ok, Page = pcall(function()
		return self.Stores[Board]:GetSortedAsync(false, BoardSize):GetCurrentPage()
	end)

	if not Ok then
		warn(`[Leaderboards] could not read {Board}: {Page}`)
		return nil
	end

	local UserIds = {}

	for _, Row in Page do
		local UserId = tonumber(Row.key)

		if UserId then
			table.insert(UserIds, UserId)
		end
	end

	self:_Name(UserIds)

	local Entries: { Entry } = {}

	for _, Row in Page do
		local UserId = tonumber(Row.key)

		if not UserId then
			continue
		end

		table.insert(Entries, {
			UserId = UserId,
			Name = string.sub(self.Names[UserId] or "", 1, 40),
			Value = Decode(Board, Row.value),
		})
	end

	return { Board = Board, Entries = Entries }
end

function LeaderboardService:Refresh()
	for _, Board in Boards do
		local Standings = self:_ReadBoard(Board)

		if not Standings then
			continue
		end

		self.Latest[Board] = Standings
		NetworkingServer.Leaderboards.Update.FireAll(Standings)
	end
end

function LeaderboardService:_HandlePlayer(Player: Player)
	task.spawn(function()
		PlayerData.Service:waitForData(Player)

		if not Player.Parent then
			return
		end

		self.Counted[Player] = os.clock()
	end)
end

function LeaderboardService:Init()
	for _, Board in Boards do
		self.Stores[Board] = DataStoreService:GetOrderedDataStore(`Leaderboard{Board}{StorePrefix}{StoreVersion}`)
	end

	NetworkingServer.Leaderboards.Get.On(function(_Player: Player): { Standings }
		local All = {}

		for _, Board in Boards do
			if self.Latest[Board] then
				table.insert(All, self.Latest[Board])
			end
		end

		return All
	end)

	--> The last of the time goes into the raw save just before it is written for good, and the final
	--> numbers go up to the boards from the same copy, since the live one is already on its way out.
	PlayerData.Service:addPlayerRemovingCallback(function(Player: Player, Raw: any)
		local Last = self.Counted[Player]
		self.Counted[Player] = nil

		if not Last then
			return
		end

		Raw.Playtime += os.clock() - Last

		local UserId = Player.UserId
		local Cash = Raw.TotalCashEarned
		local Playtime = Raw.Playtime

		task.spawn(function()
			self:_Write(UserId, "Cash", Cash)
			self:_Write(UserId, "Playtime", Playtime)
		end)
	end)

	for _, Player in Players:GetPlayers() do
		self:_HandlePlayer(Player)
	end

	Players.PlayerAdded:Connect(function(Player: Player)
		self:_HandlePlayer(Player)
	end)
end

function LeaderboardService:Start()
	task.spawn(function()
		while true do
			task.wait(PlaytimeInterval)

			for Player in self.Counted do
				local Data = PlayerData[Player]

				if Data then
					self:_Count(Player, Data)
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(WriteInterval)

			for Player in self.Counted do
				self:_WritePlayer(Player)
			end
		end
	end)

	task.spawn(function()
		while true do
			self:Refresh()
			task.wait(ReadInterval)
		end
	end)
end

return LeaderboardService
