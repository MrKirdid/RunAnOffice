local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Format = require(Shared.Utilities.Format)
local NetworkingClient = require(Shared.Networking.networkingClient)

--> The two boards by the road. Each Leaderboard model in Map.Fcts says which it is in its Board
--> attribute and carries a SurfaceGui built in the place, with one Row to copy per entry. The
--> numbers are LeaderboardService's; this only draws what it is sent.

local FctsPath = { "Map", "Fcts" }
local ModelName = "Leaderboard"
local BoardAttribute = "Board"
local GuiName = "Board"

--> how long the gui's pieces get to replicate in before the board is given up on
local PartsTimeout = 10

local Gold = Color3.fromRGB(255, 205, 60)
local Silver = Color3.fromRGB(215, 220, 235)
local Bronze = Color3.fromRGB(230, 150, 90)
local RankColors = { Gold, Silver, Bronze }

local EmptyText = "No one yet"

type Kind = "Cash" | "Playtime"
type Standings = { Board: Kind, Entries: { { UserId: number, Name: string, Value: number } } }

type Board = {
	Gui: SurfaceGui,
	List: ScrollingFrame,
	Row: Frame,
	Status: TextLabel,
	Rows: { Frame },
}

local LocalPlayer = Players.LocalPlayer

local LeaderboardController = {
	Name = "LeaderboardController",

	Boards = {} :: { [Kind]: Board },

	--> what the server last sent for each board, kept for a board that turns up after it did
	Latest = {} :: { [Kind]: Standings },
}

local function FormatTime(Seconds: number): string
	local Minutes = math.floor(Seconds / 60)
	local Hours = math.floor(Minutes / 60)

	if Hours >= 1 then
		return `{Hours}h {Minutes % 60}m`
	end

	return `{Minutes}m`
end

function LeaderboardController:_Draw(Kind: Kind)
	local Board = self.Boards[Kind]
	local Standings = self.Latest[Kind]

	if not Board or not Standings then
		return
	end

	for Index, Entry in Standings.Entries do
		local Row = Board.Rows[Index]

		if not Row then
			Row = Board.Row:Clone()
			Row.Name = tostring(Index)
			Row.LayoutOrder = Index
			Row.Visible = true
			Row.Parent = Board.List

			Board.Rows[Index] = Row
		end

		local Rank = Row:FindFirstChild("Rank") :: TextLabel
		local Avatar = Row:FindFirstChild("Avatar") :: ImageLabel
		local Name = Row:FindFirstChild("PlayerName") :: TextLabel
		local Value = Row:FindFirstChild("Value") :: TextLabel

		Rank.Text = tostring(Index)
		Rank.TextColor3 = RankColors[Index] or Color3.new(1, 1, 1)
		Avatar.Image = `rbxthumb://type=AvatarHeadShot&id={Entry.UserId}&w=150&h=150`

		--> a name the server could not look up this time is filled in on the next read
		Name.Text = if Entry.Name ~= "" then Entry.Name else "..."
		Value.Text = if Kind == "Cash" then Format.Cash(Entry.Value) else FormatTime(Entry.Value)
	end

	for Index = #Board.Rows, #Standings.Entries + 1, -1 do
		Board.Rows[Index]:Destroy()
		Board.Rows[Index] = nil
	end

	Board.Status.Text = EmptyText
	Board.Status.Visible = #Standings.Entries == 0
end

--> Moved into PlayerGui and pointed back at its part, because a SurfaceGui only takes input from
--> there, and a list that does not scroll shows ten of the hundred.
function LeaderboardController:_Bind(Gui: SurfaceGui)
	local Model = Gui:FindFirstAncestor(ModelName)
	local Attribute = Model and Model:GetAttribute(BoardAttribute)
	local Kind: Kind = if Attribute == "Playtime" then "Playtime" else "Cash"
	local Screen = Gui.Parent

	if (Attribute ~= "Cash" and Attribute ~= "Playtime") or not Screen or not Screen:IsA("BasePart") then
		warn(`[Leaderboards] {Gui:GetFullName()} is not on a part of a {ModelName} with a {BoardAttribute} attribute`)
		return
	end

	local Panel = Gui:WaitForChild("Panel", PartsTimeout)
	local List = Panel and Panel:WaitForChild("List", PartsTimeout)
	local Row = List and List:WaitForChild("Row", PartsTimeout)
	local Status = Panel and Panel:WaitForChild("Status", PartsTimeout)

	if not List or not Row or not Status then
		warn(`[Leaderboards] the {Kind} board is missing its Panel.List.Row or Panel.Status`)
		return
	end

	--> a board streamed in again comes with a fresh gui; the one moved out before it is stale
	local Old = self.Boards[Kind]

	if Old then
		Old.Gui:Destroy()
	end

	Gui.Adornee = Screen
	Gui.ResetOnSpawn = false
	Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	self.Boards[Kind] = {
		Gui = Gui,
		List = List :: ScrollingFrame,
		Row = Row :: Frame,
		Status = Status :: TextLabel,
		Rows = {},
	}

	self:_Draw(Kind)
end

function LeaderboardController:_Take(Standings: Standings)
	self.Latest[Standings.Board] = Standings
	self:_Draw(Standings.Board)
end

function LeaderboardController:Init()
	NetworkingClient.Leaderboards.Update.On(function(Standings: Standings)
		self:_Take(Standings)
	end)
end

function LeaderboardController:Start()
	local Fcts: Instance = workspace

	for _, Step in FctsPath do
		Fcts = Fcts:WaitForChild(Step)
	end

	local function Consider(Object: Instance)
		if Object.Name == GuiName and Object:IsA("SurfaceGui") and Object:FindFirstAncestor(ModelName) then
			task.spawn(function()
				self:_Bind(Object)
			end)
		end
	end

	for _, Object in Fcts:GetDescendants() do
		Consider(Object)
	end

	Fcts.DescendantAdded:Connect(Consider)

	NetworkingClient.Leaderboards.Get.Invoke():andThen(function(All: { Standings })
		for _, Standings in All do
			self:_Take(Standings)
		end
	end)
end

return LeaderboardController
