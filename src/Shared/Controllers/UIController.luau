local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local CashController = require(Shared.Controllers.CashController)
local SoundController = require(Shared.Controllers.SoundController)
local HudSweep = require(Shared.Utilities.HudSweep)
local Signal = require(Shared.Packages.Fastsignal)
local UIMotion = require(Shared.Utilities.UIMotion)
local Fusion = require(Shared.Packages.Fusion)

local Scope = Fusion.scoped(Fusion)

--> Its own effect rather than the Blur already in Lighting: that one is part of how the world is
--> lit and sits at a size the scene was built around, so a screen opening adds to it instead of
--> taking it over and having to remember to put it back.
local BlurName = "UIBlur"
local BlurSize = 18
local BlurTween = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local HudName = "HudGUI"

--> For putting the hud away by hand, which is what a screenshot wants. Kept apart from the screens
--> so neither can undo the other: a hud put away by hand stays away through a screen being opened
--> and shut again, and a screen closing does not bring back a hud the player hid.
local ToggleKey = Enum.KeyCode.H

--> Anything in a screen named this closes it, so a screen with its own X needs no wiring here.
local CloseName = "Close"

--> A copied X sits in the top right corner: this tall as a share of the screen, square, and this
--> far in from both edges, also as a share of the screen's height.
local CopiedCloseSize = 0.09
local CopiedCloseMargin = 0.03

--> B on a gamepad backs out of whatever screen is open, which is the only way out a pad has.
local BackKey = Enum.KeyCode.ButtonB

export type Screen = {
	Gui: string,

	--> the word on the HUD button that opens it. Two buttons can read the same thing -- the top
	--> bar has a "Shop" of its own -- so Under names an ancestor to look inside when they do.
	--> More than one name may be listed, for a hud mid rename.
	Label: string?,
	Under: { string }?,

	--> where the screen's own X lives, from the ScreenGui down. Only Shop names its one, and the
	--> rest are called ImageButton like everything else around them, so there is nothing to search
	--> for and the path is spelled out instead.
	Close: string?,

	--> off for a screen that animates itself. The tree is the one: scaling its root would change
	--> the canvas size its layout and pan are measured against, and the rings unfolding from the
	--> middle is a better opening than a pop anyway.
	Motion: boolean?,

	--> how long to leave the screen switched on after it closes. A screen animating itself out
	--> takes longer than the panel pop does, and going dark underneath it cuts the fold short.
	ShutTime: number?,

	--> the screen whose X is copied into the top corner of this one when it has no X of its own.
	--> The tree's only way out used to be the Exit hex in its middle, which testers never read as
	--> a close button, and which pans off the screen with the rest of the tree.
	CloseFrom: string?,
}

--> Every screen the HUD opens. Adding one here is the whole job: it gets the blur, the toggle and
--> its close button for free, and it closes whatever else was open.
local Defaults: { [string]: Screen } = {
	Shop = {
		Gui = "ShopUI",
		Label = "Shop",
		Under = { "SideBar" },
		Close = "MainBackground.MainBackground.CloseButton",
	},
	Rebirth = {
		Gui = "RebirthGUI",
		Label = "Rebirth",
		Under = { "SideBar" },
		Close = "Frame.ImageLabel.ImageButton",
	},
	Index = { Gui = "IndexGUI", Label = "Index", Close = "Frame.ImageLabel.ImageButton" },
	Inventory = { Gui = "InventoryGUI", Label = "Inventory", Close = "Frame.ImageLabel.ImageButton" },

	--> the tree also closes on the Exit node in the middle of it, which UpgradeTreeController presses
	Upgrades = { Gui = "UpgradeTree", Label = "Upgrades", Motion = false, ShutTime = 0.65, CloseFrom = "Shop" },

	--> no hud button: opened off the prompt on a seated employee, by EmployeeMenuController
	Employee = { Gui = "EmployeesUI", Close = "Root.Panel.CloseButton" },
}

local UIController = {
	--> One screen at a time: opening a second closes the first, so the blur only ever has one
	--> owner and there is no stack to unwind when a screen closes out of order.
	Current = nil :: string?,

	Screens = {} :: { [string]: Screen },
	Blur = nil :: BlurEffect?,

	--> one per screen, rebuilt whenever the screen it is attached to is cloned again
	Motion = {} :: { [string]: UIMotion.Handle },
	MotionScopes = {} :: { [string]: any },

	--> rebuilt with the hud, which is cloned again every respawn
	Sweep = nil :: HudSweep.Handle?,
	SweepScope = nil :: any,
	HudHiddenByHand = false,

	--> Carrying a part is the third reason the hud goes away, and it is its own flag rather than
	--> the hand one: a player who put the hud away by hand and then picked something up must still
	--> have it away once they have put the part down.
	HudHiddenByCarry = false,

	Opened = Signal.new(),
	Closed = Signal.new(),
}

--> A button carries its word on a label somewhere inside it rather than on itself.
local function LabelOf(Button: GuiButton): string?
	for _, Child in Button:GetDescendants() do
		if Child:IsA("TextLabel") and Child.Text ~= "" then
			return Child.Text
		end
	end

	return nil
end

--> "Frame.ImageLabel.ImageButton" walked one name at a time, so a screen rebuilt without one of
--> those links gives back nothing instead of erroring.
local function Resolve(Root: Instance, Path: string): Instance?
	local Current: Instance? = Root

	for _, Step in string.split(Path, ".") do
		if not Current then
			return nil
		end

		Current = (Current :: Instance):FindFirstChild(Step)
	end

	return Current
end

--> The icon drawn on a hud button is usually a button in its own right, and being on top it takes
--> the press instead of the thing it is drawn on -- which is what made these need hitting on the
--> edge to work at all. A nested button carrying no words of its own is part of the art, so it
--> forwards the same press. One that does carry words is somebody else's button -- Invite, and the
--> Shop and Rebirth icons that live inside Inventory -- and is left alone.
local function ForwardPress(Parent: Instance, Press: () -> ())
	for _, Child in Parent:GetChildren() do
		--> a button with words of its own is somebody else's, and so is everything drawn inside it.
		--> Shop and Rebirth sit inside Inventory, so descending past them would hand their icons to
		--> the wrong menu
		if Child:IsA("GuiButton") and LabelOf(Child) ~= nil then
			continue
		end

		if Child:IsA("GuiButton") then
			--> left active on purpose. Active off does not take a button out of the input path the
			--> way it does a frame: the button still swallows the press and then fires nothing,
			--> which is a dead spot exactly where the icon is. Leaving it active and forwarding
			--> what it catches is what makes the middle of the button work.
			Child.Active = true
			Child.Activated:Connect(Press)
		end

		ForwardPress(Child, Press)
	end
end

local function BindPress(Button: GuiButton, Press: () -> ())
	Button.Active = true
	Button.Activated:Connect(Press)

	--> Only the outer one is given the hover. MouseEnter fires per object, and the icon inside a
	--> hud button covers most of it, so binding the forwarded ones too would sound the button
	--> twice on the way in.
	Button.MouseEnter:Connect(function()
		SoundController:Play("Hover")
	end)

	ForwardPress(Button, Press)
end

local function IsUnder(Button: GuiButton, Under: { string }): boolean
	for _, Name in Under do
		if Button:FindFirstAncestor(Name) then
			return true
		end
	end

	return false
end

local function FindButton(Hud: ScreenGui, Screen: Screen): GuiButton?
	for _, Descendant in Hud:GetDescendants() do
		if not Descendant:IsA("GuiButton") or LabelOf(Descendant) ~= Screen.Label then
			continue
		end

		if not Screen.Under or IsUnder(Descendant, Screen.Under) then
			return Descendant
		end
	end

	return nil
end

--> The same wiring the screen buttons get, hover sound and icon forwarding, for a hud button that
--> does something other than open a screen.
function UIController:BindPress(Button: GuiButton, Press: () -> ())
	BindPress(Button, Press)
end

function UIController:Register(Name: string, Screen: Screen)
	self.Screens[Name] = Screen
end

function UIController:GetGui(Name: string): ScreenGui?
	local Screen = self.Screens[Name]

	if not Screen then
		return nil
	end

	local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")

	return PlayerGui and PlayerGui:FindFirstChild(Screen.Gui) :: ScreenGui?
end

function UIController:IsOpen(Name: string): boolean
	return self.Current == Name
end

function UIController:Open(Name: string)
	local Gui = self:GetGui(Name)

	if not Gui then
		warn(`[UI] "{Name}" has no screen in the PlayerGui`)
		return
	end

	if self.Current == Name then
		return
	end

	--> Silent, because the screen going out is only doing so to make room for this one: the pair
	--> played back to back reads as a fumble rather than as a switch.
	if self.Current then
		self:Close(self.Current, true)
	end

	self.Current = Name
	Gui.Enabled = true

	SoundController:Play(if Name == "Shop" then "ShopOpen" else "MenuOpen")

	local Motion = self.Motion[Name]

	if Motion then
		Motion.Show()
	end

	self:_SetBlur(true)
	self:_RefreshHud()
	self.Opened:Fire(Name)
end

function UIController:Close(Name: string, Silent: boolean?)
	if self.Current ~= Name then
		return
	end

	local Gui = self:GetGui(Name)
	local Screen = self.Screens[Name]
	local Motion = self.Motion[Name]

	if Motion then
		Motion.Hide()
	end

	if not Silent then
		SoundController:Play("Click")
	end

	self.Current = nil

	self:_SetBlur(false)
	self:_RefreshHud()
	self.Closed:Fire(Name)

	--> the screen stays switched on for as long as the shrink takes, and only goes dark if nothing
	--> reopened it in the meantime
	task.delay(Screen.ShutTime or UIMotion.ShutTime, function()
		if Gui and self.Current ~= Name then
			Gui.Enabled = false
		end
	end)
end

function UIController:Toggle(Name: string)
	if self:IsOpen(Name) then
		self:Close(Name)
		return
	end

	self:Open(Name)
end

--> Takes the screens down without tweening anything back: used on the way in, and again every
--> respawn, when the whole PlayerGui is handed back fresh.
function UIController:CloseAll()
	for Name in self.Screens do
		local Gui = self:GetGui(Name)

		if Gui then
			Gui.Enabled = false
		end
	end

	self.Current = nil

	self:_SetBlur(false)
	self:_RefreshHud()
end

--> The hud is out while a screen is open, while the player is carrying a part, and while they have
--> put it away by hand. Three reasons that do not know about each other, so none of them can undo
--> another: the hud comes back only once every one of them has let go.
function UIController:_RefreshHud()
	local Sweep = self.Sweep

	if not Sweep then
		return
	end

	if self.HudHiddenByHand or self.HudHiddenByCarry or self.Current ~= nil then
		Sweep.Hide()
		return
	end

	Sweep.Show()
end

function UIController:SetHudHidden(Hidden: boolean)
	self.HudHiddenByHand = Hidden

	self:_RefreshHud()
end

--> Carrying a part is a placement: the hud sits over exactly the bottom and sides of the screen the
--> part is being lined up against, and the buttons on it are not what is being aimed at.
function UIController:SetHudCarrying(Carrying: boolean)
	if self.HudHiddenByCarry == Carrying then
		return
	end

	self.HudHiddenByCarry = Carrying

	self:_RefreshHud()
end

function UIController:ToggleHud()
	self:SetHudHidden(not self.HudHiddenByHand)
end

function UIController:_GetBlur(): BlurEffect
	local Existing = self.Blur or Lighting:FindFirstChild(BlurName)

	if Existing and Existing:IsA("BlurEffect") then
		self.Blur = Existing
		return Existing
	end

	local Blur = Instance.new("BlurEffect")
	Blur.Name = BlurName
	Blur.Size = 0
	Blur.Parent = Lighting

	self.Blur = Blur

	return Blur
end

function UIController:_SetBlur(IsOn: boolean)
	TweenService:Create(self:_GetBlur(), BlurTween, { Size = if IsOn then BlurSize else 0 }):Play()
end

--> The hud is hydrated rather than rebuilt, so the springs of a hud that has been thrown away are
--> cleaned up with the scope they were made under.
function UIController:_BindSweep(Hud: ScreenGui)
	local Previous = self.SweepScope

	if Previous then
		Fusion.doCleanup(Previous)
	end

	local Inner = Fusion.innerScope(Scope)

	self.SweepScope = Inner
	self.Sweep = HudSweep.Attach(Inner, Hud)

	--> a hud cloned again while a screen is open comes back home, so it is sent straight back out
	self:_RefreshHud()
end

function UIController:_BindHud(Hud: ScreenGui)
	self:_BindSweep(Hud)

	--> the counter is taken over the same way the sweep is, and for the same reason: it is built in
	--> the place, and the copy handed back on a respawn has none of its connections
	CashController:Attach(Hud)

	for Name, Screen in self.Screens do
		if not Screen.Label then
			continue
		end

		local Button = FindButton(Hud, Screen)

		if not Button then
			warn(`[UI] no HUD button reading "{Screen.Label}" for {Name}`)
			continue
		end

		--> Shop and Rebirth are built with Active off, and a button that is not active never fires
		--> Activated however cleanly it is pressed. Binding one is what makes it a button.
		BindPress(Button, function()
			self:Toggle(Name)
		end)
	end
end

--> The frame the screen is actually drawn in: Shop calls it Handle, the tree calls it Background,
--> the rest call it Frame. Whatever it is, it is the only GuiObject the ScreenGui holds.
local function RootOf(Gui: ScreenGui): GuiObject?
	for _, Child in Gui:GetChildren() do
		if Child:IsA("GuiObject") then
			return Child
		end
	end

	return nil
end

function UIController:_BindMotion(Name: string, Gui: ScreenGui)
	local Screen = self.Screens[Name]

	if Screen.Motion == false then
		return
	end

	local Root = RootOf(Gui)

	if not Root then
		warn(`[UI] {Name} has no frame to animate`)
		return
	end

	--> the springs of the copy that was thrown away go with it
	local Previous = self.MotionScopes[Name]

	if Previous then
		Fusion.doCleanup(Previous)
	end

	local Inner = Fusion.innerScope(Scope)

	self.MotionScopes[Name] = Inner
	self.Motion[Name] = UIMotion.Attach(Inner, Root)
end

--> The X out of another screen, copied into the top right corner of this one. Sized off the
--> screen's height rather than its own, since the one it came from was sized off a panel.
function UIController:_CopyClose(From: string, Gui: ScreenGui): GuiButton?
	local Source = self.Screens[From]
	local SourceGui = self:GetGui(From)
	local Original = if Source and Source.Close and SourceGui then Resolve(SourceGui, Source.Close) else nil

	if not Original or not Original:IsA("GuiButton") then
		warn(`[UI] no X on {From} to copy onto {Gui.Name}`)
		return nil
	end

	local Copy = Original:Clone()
	Copy.Name = CloseName
	Copy.AnchorPoint = Vector2.new(1, 0)
	Copy.SizeConstraint = Enum.SizeConstraint.RelativeYY
	Copy.Size = UDim2.fromScale(CopiedCloseSize, CopiedCloseSize)
	Copy.Visible = true
	Copy.ZIndex = 100
	Copy.Parent = Gui

	--> The margin off the right edge is in the same unit as the one off the top, the height. A
	--> screen drawn under Roblox's own top bar starts the margin below that bar, or the X sits in
	--> the band Roblox keeps for its buttons.
	local function Place()
		local Margin = Gui.AbsoluteSize.Y * CopiedCloseMargin
		local Top = if Gui.IgnoreGuiInset then GuiService:GetGuiInset().Y else 0

		Copy.Position = UDim2.new(1, -Margin, 0, Top + Margin)
	end

	Place()
	Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(Place)

	return Copy
end

function UIController:_BindScreen(Name: string, Gui: ScreenGui)
	local Screen = self.Screens[Name]
	local Button = if Screen.Close then Resolve(Gui, Screen.Close) else Gui:FindFirstChild(CloseName, true)

	if not Button and Screen.CloseFrom then
		Button = self:_CopyClose(Screen.CloseFrom, Gui)
	end

	self:_BindMotion(Name, Gui)

	if not Button or not Button:IsA("GuiButton") then
		return
	end

	BindPress(Button, function()
		self:Close(Name)
	end)
end

function UIController:Init()
	for Name, Screen in Defaults do
		self:Register(Name, Screen)
	end

	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	self:CloseAll()

	for Name in self.Screens do
		local Gui = self:GetGui(Name)

		if Gui then
			self:_BindScreen(Name, Gui)
		end
	end

	self:_BindHud(PlayerGui:WaitForChild(HudName) :: ScreenGui)

	UserInputService.InputBegan:Connect(function(Input: InputObject, Processed: boolean)
		--> read before the processed check: with the pad's gui selection on, B arrives processed
		if Input.KeyCode == BackKey and self.Current then
			self:Close(self.Current)
			return
		end

		if Processed or Input.KeyCode ~= ToggleKey then
			return
		end

		self:ToggleHud()
	end)

	--> Screens with ResetOnSpawn on are thrown away and cloned again every respawn, and the copy
	--> has none of these connections. The hud is one of them, so its buttons come back dead.
	PlayerGui.ChildAdded:Connect(function(Child: Instance)
		if not Child:IsA("ScreenGui") then
			return
		end

		if Child.Name == HudName then
			self:CloseAll()
			self:_BindHud(Child)

			return
		end

		for Name, Screen in self.Screens do
			if Screen.Gui == Child.Name then
				Child.Enabled = false
				self:_BindScreen(Name, Child)
			end
		end
	end)
end

return UIController
