--[[
	The world half of an employee: the rig sat in a desk's chair, and the card over its head.

	The model is parented into the desk it is sat at rather than a container of its own, so a desk
	being torn down takes its employee with it and there is no second thing to keep in step. A
	component reroll only rebuilds the desk's Components folder, so the employee survives one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local DeskController = require(Shared.Controllers.DeskController)
local Employees = require(Shared.Configs.Employees)
local Offsets = require(Shared.Configs.Offsets)
local Rarities = require(Shared.Configs.Rarities)
local PlayerData = require(Shared.PlayerData).client
local Rolling = require(Shared.Utilities.Rolling)

local ModelName = "Employee"

--> How long a freshly written employee will wait on the desk model to replicate before it gives
--> up. Hiring only ever targets a desk the player already owns, so this is a join race and not
--> a missing desk, and it resolves within a frame or two of DeskController building the plot.
local DeskTimeout = 10

local EmployeeController = {
	Seated = {} :: { [string]: Model },
}

--> Off the plain table, never the player's luck, or a luck potion would quietly rename
--> everything they own. Summed once because the table never changes at runtime.
local BaseOdds = Rolling.Chances(Employees)

local function Commas(Amount: number): string
	local Text = tostring(math.floor(Amount))
	local Done

	repeat
		Text, Done = Text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until Done == 0

	return Text
end

local function GetOdds(Type: string): number
	local Chance = BaseOdds[Type]

	return if Chance and Chance > 0 then 1 / Chance else math.huge
end

local function Describe(Model: Model, Employee: any)
	local Config = Employees[Employee.Type]
	local Head = Model:FindFirstChild("Head")

	if not Config or not (Head and Head:IsA("BasePart")) then
		return
	end

	local Odds = GetOdds(Employee.Type)
	local TierName, TierColor = Rarities.Of(Odds)

	local Display = Assets.UI.EmployeeDisplay:Clone()
	Display.Adornee = Head

	local function Set(Name: string, Text: string, Color: Color3?)
		local Label = Display:FindFirstChild(Name, true)

		if Label and Label:IsA("TextLabel") then
			Label.Text = Text

			if Color then
				Label.TextColor3 = Color
			end
		end
	end

	Set("NameLabel", Employee.Name)
	Set("RarityLabel", TierName, TierColor)
	Set("MultiplierLabel", string.format("%gx", Config.Value))
	Set("CostLabel", "$" .. Commas(Config.Cost))

	Display.Parent = Model
end

local function Animate(Model: Model)
	local Controller = Model:FindFirstChildOfClass("AnimationController")
	local Animator = Controller and Controller:FindFirstChildOfClass("Animator")
	local Animation = Assets.Animations.Employee:FindFirstChild("Typing")

	if not Animator or not Animation then
		return
	end

	local Track = Animator:LoadAnimation(Animation)
	Track.Looped = true
	Track:Play()
end

--> The desk model is built by DeskController off the same data, so it can land either side of
--> this. Waiting on the id it will be filed under is cheaper than watching the folder.
local function WaitForDesk(Floor: number, Slot: number): Model?
	local DeskID = DeskController:GetDeskID(Floor, Slot)
	local Deadline = os.clock() + DeskTimeout

	while os.clock() < Deadline do
		local Desk = DeskController.Desks[DeskID]

		if Desk and Desk.Parent then
			return Desk
		end

		task.wait()
	end

	return nil
end

function EmployeeController:Seat(UID: string)
	local Employee = PlayerData.Employees[UID]()

	if not Employee or self.Seated[UID] then
		return
	end

	local Template = Assets.Employees:FindFirstChild(Employee.Type)

	if not Template then
		warn(`[Employee] Assets.Employees has no model named "{Employee.Type}"`)
		return
	end

	local Desk = WaitForDesk(Employee.Floor, Employee.Slot)

	--> Cleared while waiting, so there is nothing left to sit down
	if not Desk or not PlayerData.Employees[UID]() then
		return
	end

	local Model = Template:Clone()
	Model.Name = ModelName

	Model:PivotTo(Desk:GetPivot() * Offsets.Employee)
	Model.Parent = Desk

	Describe(Model, Employee)
	Animate(Model)

	self.Seated[UID] = Model
end

function EmployeeController:Unseat(UID: string)
	local Model = self.Seated[UID]

	if Model then
		Model:Destroy()
		self.Seated[UID] = nil
	end
end

function EmployeeController:Start()
	for UID in PlayerData.Employees() do
		task.spawn(function()
			self:Seat(UID)
		end)
	end

	PlayerData.Employees.OnKeyAdded(function(UID: string)
		task.spawn(function()
			self:Seat(UID)
		end)
	end)

	PlayerData.Employees.OnKeyRemoved(function(UID: string)
		self:Unseat(UID)
	end)
end

return EmployeeController
