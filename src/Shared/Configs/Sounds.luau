--> Every entry here is materialised as a Sound under ReplicatedStorage.Assets.SFX.<Folder> by
--> SoundController, so this list is the only place an id or a mix value should ever be edited.
--> Ids stay empty until the matching file in "SFX temp" is uploaded; a blank id plays nothing.

export type Effect = {
	Id: string,
	Volume: number?,
	Speed: number?,
}

return {
	Folder = "UI",

	--> Applied to any effect that does not override it.
	Volume = 0.5,

	Effects = {
		--> Actions
		Click = { Id = "134309646300984", Volume = 0.35 } :: Effect,
		Press = { Id = "99631176640521", Volume = 0.45 } :: Effect,
		Hover = { Id = "138425147850446", Volume = 0.2 } :: Effect,
		Confirm = { Id = "120166475386612" } :: Effect,
		Lock = { Id = "91042656324448" } :: Effect,

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
	},
}
