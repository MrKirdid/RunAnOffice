local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Arrow = require(script.Arrow)
local FireworksController = require(Shared.Controllers.FireworksController)
local Follow = require(script.Follow)
local Gui = require(script.Gui)
local Information = require(script.Information)
local NetworkingClient = require(Shared.Networking.networkingClient)
local Overhead = require(script.Overhead)
local PlayerData = require(Shared.PlayerData).client
local ScreenShakeController = require(Shared.Controllers.ScreenShakeController)
local SoundController = require(Shared.Controllers.SoundController)
local TutorialConfigs = require(Shared.Configs.Tutorial)

local Stages = Shared:WaitForChild("Tutorial"):WaitForChild("Stages")

--> Plays the tutorial out on the client, one step at a time, off the stage the server keeps in
--> the save. Each step is a module under Shared.Tutorial.Stages that puts the pointers where they
--> go and takes them away again; this hands them the pointers and the text and keeps the hud out of
--> the way.

local HudName = "HudGUI"
local HudRoot = "Root"

export type Stage = {
	Start: (Tutorial: any) -> (),
	Cleanup: (Tutorial: any) -> (),
}

local TutorialController = {
	Name = "TutorialController",

	Gui = nil :: ScreenGui?,

	Arrow = Arrow,
	Follow = Follow,
	Overhead = Overhead,
	Information = Information,

	--> the step on the screen right now, by index in the config and by module
	Current = nil :: number?,
	Running = nil :: Stage?,

	--> Nothing is drawn until the intro delay is up, whatever the save does in the meantime: the
	--> stage it lands on is read then.
	Shown = false,

	--> the hud frames put away for the tutorial, so a finish puts back exactly what was taken
	Hidden = {} :: { GuiObject },
}

--> One pointer per step: the beam from the player's feet for anything in the world, the arrow over
--> the player's head for an employee walking by, and the arrow on the screen for a hud button.

--> A refusal explained in the bar, from anything that turned a purchase down. Shown outside the
--> tutorial too: the bar is the one place the game already talks to the player.
function TutorialController:Notify(Text: string)
	self.Information:Notice(Text)
end

function TutorialController:IsCompleted(): boolean
	return PlayerData.TutorialStage() > #TutorialConfigs.Stages
end

--> Takes the hud frames named in the config away, on whichever copy of the hud is up.
function TutorialController:_HideHud(Hud: Instance)
	local Root = Hud:FindFirstChild(HudRoot)

	if not Root then
		return
	end

	for _, Name in TutorialConfigs.HiddenBars do
		local Bar = Root:FindFirstChild(Name)

		if Bar and Bar:IsA("GuiObject") and Bar.Visible then
			Bar.Visible = false
			table.insert(self.Hidden, Bar)
		end
	end
end

function TutorialController:_ShowHud()
	for _, Bar in self.Hidden do
		Bar.Visible = true
	end

	table.clear(self.Hidden)
end

function TutorialController:_Cleanup()
	local Stage = self.Running

	if not Stage then
		return
	end

	self.Running = nil

	Stage.Cleanup(self)
end

--> Everything down and the fireworks up, for the step after the last one.
function TutorialController:_Finish()
	self.Current = nil

	self.Arrow:Stop()
	self.Follow:Stop()
	self.Overhead:Stop()
	self:_ShowHud()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	self.Information:Display(TutorialConfigs.FinishText, nil, true)

	local Character = Players.LocalPlayer.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")

	if Root and Root:IsA("BasePart") then
		task.spawn(function()
			FireworksController:Play(Root.Position, TutorialConfigs.Fireworks)
		end)
	end
end

function TutorialController:_Enter(Index: number)
	local Entry = TutorialConfigs.Stages[Index]
	local Previous = self.Current

	self:_Cleanup()

	--> a step done is a step done, and it is heard as one
	if Previous and Index > Previous then
		SoundController:Play("Confirm")
	end

	if not Entry then
		self:_Finish()
		return
	end

	local Module = Stages:FindFirstChild(Entry.Module or Entry.Name)

	if not Module or not Module:IsA("ModuleScript") then
		warn(`[Tutorial] no stage module called {Entry.Module or Entry.Name}`)
		return
	end

	local Stage = require(Module) :: Stage

	self.Current = Index
	self.Running = Stage

	local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local Hud = PlayerGui and PlayerGui:FindFirstChild(HudName)

	if Hud then
		self:_HideHud(Hud)
	end

	--> the hotbar along the bottom comes with the first gear, and is one more thing on a screen
	--> that is meant to have one thing on it; it is back with the rest of the hud at the end
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	self.Information:Display(Entry.Text, Entry.Detail)

	Stage.Start(self)
end

function TutorialController:Init()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local Screen = Gui.Build(PlayerGui)

	self.Gui = Screen

	self.Arrow:Attach(Screen:FindFirstChild("Arrow") :: ImageLabel)
	self.Information:Attach(Screen:FindFirstChild("Information") :: CanvasGroup)

	--> the hud is cloned again every respawn, and the copy comes back with every bar showing
	PlayerGui.ChildAdded:Connect(function(Child: Instance)
		if Child.Name == HudName and self.Current then
			self:_HideHud(Child)
		end
	end)

	--> somebody walked out with one of the player's employees. The bar is the one place the game
	--> talks to the player, so it is said there, with a kick, wherever they happen to be
	NetworkingClient.Notices.Stolen.On(function(Notice)
		ScreenShakeController:Shake(1.5)
		self:Notify(`{Notice.Thief.Name} stole {Notice.Name} ({Notice.Type})`)
	end)
end

function TutorialController:Start()
	--> Changed is a field, not a method: a colon here drops the callback.
	PlayerData.TutorialStage.Changed(function(Index: number)
		if not self.Shown then
			return
		end

		self:_Enter(Index)
	end)

	task.delay(TutorialConfigs.IntroDelay, function()
		self.Shown = true

		--> a save that is already through it gets nothing, the fireworks included
		if self:IsCompleted() then
			return
		end

		self:_Enter(PlayerData.TutorialStage())
	end)
end

return TutorialController
