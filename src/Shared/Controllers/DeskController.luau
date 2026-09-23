local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Assets = ReplicatedStorage:WaitForChild("Assets")

local NetworkingClient = require(Shared.Networking.networkingClient)
local SoundController = require(Shared.Controllers.SoundController)
local PlotController = require(Shared.Controllers.PlotController)
local RollingController = require(Shared.Controllers.RollingController)
local ScreenShakeController = require(Shared.Controllers.ScreenShakeController)
local DeskData = require(Shared.Utilities.DeskData)
local DeskPlacements = require(Shared.Utilities.DeskPlacements)
local DeskPurchase = require(Shared.Utilities.DeskPurchase)
local Format = require(Shared.Utilities.Format)
local Signal = require(Shared.Packages.Fastsignal)
local Offsets = require(Shared.Configs.Offsets)
local PlayerData = require(Shared.PlayerData).client
local Tiers = require(Shared.Utilities.Tiers)
local TutorialConfigs = require(Shared.Configs.Tutorial)
local TutorialController = require(Shared.Controllers.TutorialController)
local VfxController = require(Shared.Controllers.VfxController)
local Parts = require(Assets.Parts)

--> Down to the frame the buy board draws, from the plot. Waited on link by link rather than looked
--> up in one go, since the plot is still streaming in when this runs.
local BoardPath = { "Boards", "BuyDesk", "Main", "BuyUI" }
local ButtonPath = { "BuyDesk", "GoButton" }
local BoardWait = 15

--> What the board reads once every floor of the plot is open and every desk on them is standing.
--> There is nothing left to sell at that point, so a price would be a price for nothing.
local MaxText = "MAX"

--> Names the price may have been drawn under. A board that names it none of these is found by
--> what it says instead: it ships with a number written on it, and the only label on it carrying a
--> digit is the price.
local PriceNames = { "Price", "PriceLabel", "Cost", "CostLabel", "Amount", "Cash" }

type Price = TextLabel | TextButton

local DeskController = {
	Desks = {} :: { [string]: Model },

	--> The label on the buy board carrying the price, and whether it was drawn with a currency
	--> mark on it: a board that spells the dollar out beside the number would otherwise be handed
	--> a second one.
	Price = nil :: Price?,
	Marked = true,

	--> One purchase in flight at a time, or a button held down sends the same one twice and the
	--> second is charged for a desk the first already bought.
	Buying = false,

	--> A desk standing up is either one that was just bought or one being put back on join, and only
	--> the first of those is worth an effect. Set by the press and taken by the next desk to appear,
	--> so building a plot out of a save never sets a dozen of them off at once.
	Celebrate = false,

	ComponentsChanged = Signal.new(),
}

local function IsText(Object: Instance): boolean
	return Object:IsA("TextLabel") or Object:IsA("TextButton")
end

--> The label the price is written on: by name where the board names it, and by what it says where
--> it does not.
local function FindPrice(Root: Instance): Price?
	local Inside = Root:GetDescendants()

	for _, Object in Inside do
		if IsText(Object) and table.find(PriceNames, Object.Name) then
			return Object :: Price
		end
	end

	for _, Object in Inside do
		if IsText(Object) and string.find((Object :: Price).Text, "%d") then
			return Object :: Price
		end
	end

	return nil
end

--> One name at a time so a plot missing any link gives back nothing, with the name of the link it
--> stopped at, rather than hanging on a board that is never coming.
local function WalkTo(Root: Instance, Path: { string }): (Instance?, string?)
	local Current: Instance = Root

	for _, Step in Path do
		local Next = Current:WaitForChild(Step, BoardWait)

		if not Next then
			return nil, Step
		end

		Current = Next
	end

	return Current, nil
end

function DeskController:GetDeskID(Floor: number, Slot: number): string
	return tostring(Floor) .. "-" .. tostring(Slot)
end

--> The spins running right now, keyed by the slot of the desk rather than by the desk: all three
--> gifts on a desk can be opened at once, and a lock on the whole desk meant the second press was
--> refused until the first spin had finished.
local Spinning: { [string]: boolean } = {}

local function SpinKey(DeskID: string, Component: string): string
	return DeskID .. "-" .. Component
end

function DeskController:SpawnComponents(Floor: number, Slot: number)
	local DeskID = self:GetDeskID(Floor, Slot)
	local Desk = self.Desks[DeskID]
	local Components = PlayerData.Floors[Floor].Desks[Slot]()

	if not Desk or not Components then
		return
	end

	local Existing = Desk:FindFirstChild("Components")

	if Existing then
		Existing:Destroy()
	end

	local Container = Instance.new("Folder")
	Container.Name = "Components"
	Container.Parent = Desk

	local Pivot = Desk:GetPivot()

	for Component, Offset in Offsets.Desk do
		local Variant = Components[Component]

		--> A part still being spun for is left off the desk. The server writes the result the
		--> moment it grants the roll, so it is in the save already; standing it up now would be
		--> standing it there before the spin meant to reveal it had finished. The spin puts it back
		--> itself when it ends. A slot emptied by a theft is not a part either: nothing stands
		--> there, and no gift does, until something is placed on it.
		if DeskData.IsPart(Variant) and not Spinning[SpinKey(DeskID, Component)] then
			local Model: Model = Parts(Component, Variant)

			Model:PivotTo(Pivot * Offset)
			Model.Parent = Container

			VfxController:Aura(Model, (Tiers.FromVariant(Variant)))
		end
	end

	self.ComponentsChanged:Fire(Floor, Slot)
end

--> A desk comes in bare, whether it was just bought or is being stood back up on join: nothing on
--> it spins until the gift over each slot is opened, which is what rolls that part.
function DeskController:NewDesk(Floor: number, Slot: number)
	local DeskID = self:GetDeskID(Floor, Slot)
	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)
	local DeskCFrame = DeskPlacements.GetCFrame(Plot, Floor, Slot)

	if not DeskCFrame then
		return
	end

	local Desk = Assets.Desk:Clone()

	Desk:PivotTo(DeskCFrame)
	Desk.Parent = workspace.Desks

	DeskController.Desks[DeskID] = Desk

	self:SpawnComponents(Floor, Slot)

	if self.Celebrate then
		self.Celebrate = false

		local Middle = Desk:GetBoundingBox()

		VfxController:Burst("BuyMax", Middle.Position)
	end
end

--> Rolling one part of a standing desk in place, off the button floating where that part sits.
--> The slot is pinned for the length of the spin: the server writes the result the moment it grants
--> the roll, and without the pin the new part would already be standing on the desk before the spin
--> meant to reveal it had started. The pin is on the slot and not on the desk, so the other two
--> gifts on it can be opened while this one is still spinning; the spins overlap in the world the
--> same way a desk roll and a pad roll already do.
function DeskController:RollSlot(Floor: number, Slot: number, Component: string): boolean
	local DeskID = self:GetDeskID(Floor, Slot)
	local Key = SpinKey(DeskID, Component)
	local Desk = self.Desks[DeskID]
	local Offset = Offsets.Desk[Component]

	if not Desk or not Offset or Spinning[Key] then
		return false
	end

	Spinning[Key] = true

	local Ok, Problem = pcall(function()
		local Rolled = NetworkingClient.Items.RollSlot
			.Invoke({
				Floor = Floor,
				Slot = Slot,
				Component = Component,
			})
			:expect()

		--> The part being replaced comes off before the spin rather than with the rebuild after it,
		--> or the old one stands inside the reel for the whole roll.
		local Built = Desk:FindFirstChild("Components")
		local Existing = Built and Built:FindFirstChild(Component)

		if Existing then
			Existing:Destroy()
		end

		RollingController:RollComponent(Desk:GetPivot() * Offset, Component, Rolled.Variant):Destroy()
	end)

	Spinning[Key] = nil

	--> Runs either way: a roll that threw part way has already taken the old part off the desk, and
	--> this is what puts one back. A slot next to this one still spinning is left off by the pin.
	self:SpawnComponents(Floor, Slot)

	if not Ok then
		warn(`[Desk] slot roll failed: {Problem}`)
	end

	return Ok
end

function DeskController:RemoveDesk(Floor: number, Slot: number)
	local DeskID = self:GetDeskID(Floor, Slot)
	local Desk = self.Desks[DeskID]

	if Desk then
		Desk:Destroy()
		self.Desks[DeskID] = nil

		self.ComponentsChanged:Fire(Floor, Slot)
	end
end

--> The desk a press on the board would buy and what it costs, or nil once the plot is finished.
--> Read off the save exactly the way the server reads it, so the board never offers a desk the
--> server would refuse to build.
function DeskController:GetNext(): DeskPurchase.Next?
	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)

	return DeskPurchase.Next(PlayerData, Plot)
end

function DeskController:RefreshPrice()
	local Label = self.Price

	if not Label then
		return
	end

	local Next = self:GetNext()

	if not Next then
		Label.Text = MaxText
		return
	end

	Label.Text = if self.Marked then Format.Cash(Next.Price) else Format.Short(Next.Price)
end

function DeskController:Start()
	local WatchDesk = function(Floor: number, Slot: number)
		PlayerData.Floors[Floor].Desks[Slot].Changed(function()
			self:SpawnComponents(Floor, Slot)
		end)
	end

	local WatchFloor = function(Floor: number)
		local Desks = PlayerData.Floors[Floor].Desks

		for Slot in Desks() do
			self:NewDesk(Floor, Slot)
			WatchDesk(Floor, Slot)
		end

		Desks.OnKeyAdded(function(Slot: number)
			WatchDesk(Floor, Slot)
			self:NewDesk(Floor, Slot)
		end)

		Desks.OnKeyRemoved(function(Slot: number)
			self:RemoveDesk(Floor, Slot)
		end)
	end

	for Floor in PlayerData.Floors() do
		WatchFloor(Floor)
	end

	PlayerData.Floors.OnKeyAdded(function(Floor: number)
		WatchFloor(Floor)
	end)

	local _PlotIndex, Plot = PlotController:GetPlot(Players.LocalPlayer)
	local BuyUI, Missing = WalkTo(Plot, BoardPath)

	if not BuyUI then
		warn(`[Desk] the plot has no {Missing or table.concat(BoardPath, ".")}, so there is no buy board`)
		return
	end

	local Pressable = WalkTo(BuyUI, ButtonPath)

	if not Pressable or not Pressable:IsA("GuiButton") then
		warn(`[Desk] the buy board has no {table.concat(ButtonPath, ".")}, so nothing on it can be pressed`)
		return
	end

	local GoButton = Pressable

	--> Read before anything is written to it, since the price the board was drawn with is what says
	--> whether it carries its own currency mark.
	local Label = FindPrice(BuyUI)

	if Label then
		self.Price = Label
		self.Marked = string.find(Label.Text, "%$") ~= nil
	else
		warn("[Desk] the buy board has no price on it, so the price is not shown")
	end

	self:RefreshPrice()

	--> Fires for a desk being bought and for a floor opening, which are the two things the price
	--> and the MAX are read off.
	PlayerData.Floors.Changed(function()
		self:RefreshPrice()
	end)

	GoButton.MouseEnter:Connect(function()
		SoundController:Play("Hover")
	end)

	--> The press is a request and nothing else: the server picks the desk, takes the cash and
	--> writes it, and the sound waits on that rather than playing over a purchase that was refused.
	GoButton.Activated:Connect(function()
		if self.Buying then
			return
		end

		local Next = self:GetNext()

		--> Turned down here as well as on the server, so a board pressed with nothing left to buy
		--> or nothing to buy it with answers on the spot instead of after a round trip.
		if not Next or PlayerData.Cash() < Next.Price then
			SoundController:Play("Error")

			if Next then
				TutorialController:Notify(TutorialConfigs.Notices.NoCash)
			end

			return
		end

		self.Buying = true

		NetworkingClient.Purchases.BuyDesk
			.Invoke()
			:andThen(function(Bought: boolean)
				SoundController:Play(if Bought then "Purchase" else "Error")

				if Bought then
					ScreenShakeController:Shake(1.2)
					TutorialController:Notify(TutorialConfigs.Notices.DeskBought)
				end

				--> Armed rather than played here: the desk it belongs over does not exist yet, and
				--> the write that stands it up is still on its way back from the server.
				self.Celebrate = Bought
			end)
			:catch(function(Problem)
				warn(`[Desk] {Problem}`)
			end)
			:finally(function()
				self.Buying = false
			end)
	end)
end

return DeskController
