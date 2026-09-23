local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Format = require(Shared.Utilities.Format)
local NetworkingClient = require(Shared.Networking.networkingClient)
local PlayerData = require(Shared.PlayerData).client
local ShopController = require(Shared.Controllers.ShopController)
local SoundController = require(Shared.Controllers.SoundController)
local Store = require(Shared.Utilities.Store)
local TutorialController = require(Shared.Controllers.TutorialController)
local UIController = require(Shared.Controllers.UIController)

--> The hud's buttons that do something other than open a screen, and the one label on it that
--> reads a live number: the + by the cash opens the shop on its cash section, Shop in the top bar
--> opens the shop, Home takes the player back to the ground floor of their own plot, Invite asks
--> Roblox for its invite prompt, and the friend multiplier says what the server is paying for the
--> friends here. The hud is built in the place and cloned again every respawn, so all of it is
--> wired again on each copy.

local HudName = "HudGUI"

--> from the hud's Root, as RenameHud named them
local AddCashPath = "Root.CashBar.AddCashButton"
local ShopPath = "Root.TopBar.ShopButton"
local HomePath = "Root.TopBar.HomeButton"
local InvitePath = "Root.SideBar.InviteButton"
local FriendLabelPath = "Root.CashBar.FriendMultiplierLabel"

local ShopScreen = "Shop"
local CashSection = "Cash"

--> how long the shop gets to pop in before it is scrolled, or the glide is measured mid-pop
local ScrollDelay = 0.35

local HomeFloor = 1
local StolenText = "Walk the employee home first"

--> how long after the client is up before the welcome back is shown, past the tutorial's intro
local WelcomeDelay = 3

local EarnedAttribute = "OfflineEarned"

local LocalPlayer = Players.LocalPlayer

local HudActionsController = {
	Name = "HudActionsController",

	--> the friend label on whichever copy of the hud is up
	FriendLabel = nil :: TextLabel?,

	--> the welcome back is said once a session, whatever the attribute does after
	Welcomed = false,
}

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

local function Bind(Hud: Instance, Path: string, Press: () -> ())
	local Button = Resolve(Hud, Path)

	if not Button or not Button:IsA("GuiButton") then
		warn(`[UI] no button at {HudName}.{Path}`)
		return
	end

	UIController:BindPress(Button, Press)
end

function HudActionsController:OpenCashShop()
	UIController:Open(ShopScreen)

	task.delay(ScrollDelay, function()
		if UIController:IsOpen(ShopScreen) then
			ShopController:JumpTo(CashSection)
		end
	end)
end

--> Refused on the server for anyone carrying a stolen employee; said here so the bar can say why.
function HudActionsController:GoHome()
	if PlayerData.Holding().StolenFrom ~= nil then
		SoundController:Play("Error")
		TutorialController:Notify(StolenText)
		return
	end

	NetworkingClient.Floors.Travel.Invoke(HomeFloor):andThen(function(Moved: boolean)
		SoundController:Play(if Moved then "Click" else "Error")
	end)
end

--> Roblox's own invite prompt, when this player is allowed to send one. Both calls are the
--> platform's: the check is a web call, so a failure is only a prompt that did not open.
function HudActionsController:Invite()
	task.spawn(function()
		local Ok, Can = pcall(SocialService.CanSendGameInviteAsync, SocialService, LocalPlayer)

		if not Ok then
			warn(`[UI] could not ask whether invites can be sent: {Can}`)
			return
		end

		if not Can then
			SoundController:Play("Error")
			return
		end

		SocialService:PromptGameInvite(LocalPlayer)
	end)
end

--> The label is authored as rich text with the number in a coloured font tag, so only what is
--> inside the tag is swapped and the colour stays whatever was drawn.
function HudActionsController:_DrawFriends()
	local Label = self.FriendLabel

	if not Label then
		return
	end

	local Percent = math.round(Store.FriendsCounted(LocalPlayer) * Store.FriendStep * 100)
	local Value = `+{Percent}%`

	--> a % in a gsub replacement starts a capture reference, so the one in the value is doubled
	local Replacement = ">" .. string.gsub(Value, "%%", "%%%%") .. "</font>"
	local Text, Swapped = string.gsub(Label.Text, ">[^<]*</font>", Replacement, 1)

	Label.Text = if Swapped > 0 then Text else `Friend Multiplier: {Value}`
end

function HudActionsController:_BindHud(Hud: Instance)
	Bind(Hud, AddCashPath, function()
		self:OpenCashShop()
	end)

	Bind(Hud, ShopPath, function()
		UIController:Toggle(ShopScreen)
	end)

	Bind(Hud, HomePath, function()
		self:GoHome()
	end)

	Bind(Hud, InvitePath, function()
		self:Invite()
	end)

	local Label = Resolve(Hud, FriendLabelPath)

	self.FriendLabel = if Label and Label:IsA("TextLabel") then Label else nil

	if not self.FriendLabel then
		warn(`[UI] no label at {HudName}.{FriendLabelPath}`)
	end

	self:_DrawFriends()
end

function HudActionsController:_Welcome()
	local Earned = LocalPlayer:GetAttribute(EarnedAttribute)

	if self.Welcomed or type(Earned) ~= "number" or Earned <= 0 then
		return
	end

	self.Welcomed = true

	SoundController:Play("Purchase")
	TutorialController:Notify(`Welcome back! Your office made {Format.Cash(Earned)} while you were away`)
end

function HudActionsController:Init()
	local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

	--> the + is there before this binds it: CashController only lays it out
	self:_BindHud(PlayerGui:WaitForChild(HudName))

	PlayerGui.ChildAdded:Connect(function(Child: Instance)
		if Child.Name == HudName and Child:IsA("ScreenGui") then
			self:_BindHud(Child)
		end
	end)

	LocalPlayer:GetAttributeChangedSignal(Store.FriendsAttribute):Connect(function()
		self:_DrawFriends()
	end)

	LocalPlayer:GetAttributeChangedSignal(EarnedAttribute):Connect(function()
		self:_Welcome()
	end)
end

function HudActionsController:Start()
	task.delay(WelcomeDelay, function()
		self:_Welcome()
	end)
end

return HudActionsController
