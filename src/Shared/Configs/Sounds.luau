--> Every entry here is materialised as a Sound under ReplicatedStorage.Assets.SFX.<Folder> by
--> SoundController, so this list is the only place an id or a mix value should ever be edited.
--> Ids stay empty until the matching file in "SFX temp" is uploaded; a blank id plays nothing.

export type Effect = {
	Id: string,
	Volume: number?,
	Speed: number?,

	--> How far the playback speed may wander either side of Speed, as a fraction of it. Pressing a
	--> button four times plays the same clip four times, and it is the sameness that turns a click
	--> into a beep -- a few percent of drift is the whole difference between the two.
	Spread: number?,

	--> Only read by PlayAt and Attach: how far off, in studs, the sound has faded to nothing. Left
	--> out, a positional effect carries across the whole map at full volume.
	Range: number?,

	--> For the ones that are a place rather than a moment. Only Attach starts these, and it is the
	--> caller that ends them, by destroying what they were hung off.
	Loop: boolean?,
}

return {
	Folder = "UI",

	--> Applied to any effect that does not override it.
	Volume = 0.5,

	Effects = {
		--> Actions. These four are the ones that fire in a row, so they are the ones that carry
		--> any spread at all.
		Click = { Id = "134309646300984", Volume = 0.35, Spread = 0.07 } :: Effect,
		Press = { Id = "99631176640521", Volume = 0.45, Spread = 0.06 } :: Effect,
		Hover = { Id = "138425147850446", Volume = 0.2, Spread = 0.08 } :: Effect,
		Confirm = { Id = "120166475386612", Spread = 0.04 } :: Effect,
		--> Both played through PlayAt at the lasers, so they carry a Range. Unlock is the same
		--> clip slowed down, which is what makes it the door opening rather than closing again.
		Lock = { Id = "91042656324448", Volume = 0.6, Range = 70 } :: Effect,
		Unlock = { Id = "91042656324448", Volume = 0.45, Speed = 0.75, Range = 70 } :: Effect,

		--> Currency
		Purchase = { Id = "94479449466788" } :: Effect,
		Sell = { Id = "113288142201727" } :: Effect,
		Upgrade = { Id = "95316328089904" } :: Effect,
		ShopClick = { Id = "85369726821664" } :: Effect,
		PurchaseSuccess = { Id = "140306369430915", Volume = 0.6 } :: Effect,

		--> Menus
		MenuOpen = { Id = "101665006375114", Volume = 0.4 } :: Effect,
		ShopOpen = { Id = "123090047116488", Volume = 0.4 } :: Effect,
		Teleport = { Id = "137721297008707" } :: Effect,

		--> Alerts
		Error = { Id = "113575453161071" } :: Effect,
		Warning = { Id = "105847546541925" } :: Effect,

		--> Tutorial. The bar at the top types its line out one letter at a time, so Type is played
		--> thirty times a second for as long as the sentence is: quiet, and spread so it is a
		--> keyboard rather than a metronome. Notify is the bar arriving.
		TutorialType = { Id = "116080744084010", Volume = 0.35, Spread = 0.08 } :: Effect,
		TutorialNotify = { Id = "135366639238389", Volume = 0.5 } :: Effect,

		--> The finish. Both played through PlayAt at the shell, so they carry a Range. The bang is
		--> pitched up, which is what makes it a firework rather than a gun.
		FireworkLaunch = { Id = "160248621", Volume = 0.1, Speed = 1.075, Spread = 0.07, Range = 80 } :: Effect,
		FireworkExplode = { Id = "4583102108", Speed = 1.325, Spread = 0.02, Range = 120 } :: Effect,

		--> World. Both are played through PlayAt, so they carry a Range and are heard from where
		--> the thing happened rather than out of the middle of the player's head.
		--> The two ids point at clips already in the pack rather than at nothing, because a blank
		--> id plays silence and warns once. They are named anyway so either moment can be remixed,
		--> or handed its own upload, without touching the code that fires it.
		EmployeeSpawn = {
			Id = "134309646300984",
			Volume = 0.18,
			Speed = 0.8,
			Spread = 0.06,
			Range = 45,
		} :: Effect,

		EmployeeSeated = { Id = "120166475386612", Volume = 0.3, Spread = 0.05, Range = 60 } :: Effect,

		--> The till itself, at the speed it was recorded rather than pitched up into a blip. Loud,
		--> and paid for by a range short enough that it is a sound made at a desk you are standing
		--> at: out of the room it is gone entirely, which is what keeps one a second bearable.
		--> The spread stays wide, because it is the same clip on a one second timer.
		EmployeePay = {
			Id = "113288142201727",
			Volume = 0.55,
			Spread = 0.09,
			Range = 18,
		} :: Effect,

		--> Not a moment but a place: hung off every employee sat at a desk and left running, so a
		--> floor that is working sounds like it. Started by Attach, which staggers each one into a
		--> different part of the clip -- twenty copies of a four second loop all started on the
		--> same frame is not an office, it is one very loud typist.
		Typing = {
			Id = "9116157899",
			Volume = 0.3,
			Spread = 0.06,
			Range = 26,
			Loop = true,
		} :: Effect,
	},

	--> The gears, played by the server out in the world off the part the thing happened to, so
	--> everyone near it hears it from there. Not materialised by SoundController: Server.Gears.Effects
	--> builds each one where it is needed and throws it away after. Same shape as an Effect.
	Gear = {
		Swing = { Id = "9120972321", Volume = 0.6, Spread = 0.08, Range = 60 } :: Effect,
		Bonk = { Id = "9113333378", Volume = 0.8, Speed = 0.9, Spread = 0.06, Range = 80 } :: Effect,
		Throw = { Id = "9105104700", Volume = 0.6, Range = 60 } :: Effect,
		Fuse = { Id = "9113936794", Volume = 0.5, Range = 60, Loop = true } :: Effect,
		Explode = { Id = "138533090376585", Volume = 0.9, Spread = 0.05, Range = 160 } :: Effect,
		Splat = { Id = "96883255758820", Volume = 0.8, Spread = 0.06, Range = 80 } :: Effect,
		Snap = { Id = "9116719662", Volume = 0.8, Range = 80 } :: Effect,
		Freeze = { Id = "9125611419", Volume = 0.7, Range = 80 } :: Effect,
		Gulp = { Id = "9114171855", Volume = 0.7, Range = 40 } :: Effect,
		Cloak = { Id = "9125646918", Volume = 0.6, Range = 60 } :: Effect,
	} :: { [string]: Effect },
}
