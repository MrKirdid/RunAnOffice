--> Every flat icon the game draws that is not part of a place-built screen: the hotbar's gear
--> images, the shop's cards and the upgrade tree's nodes. Image ids, not decal ids: a script setting
--> an ImageLabel or a Tool's TextureId to a decal id loads nothing. The toolbox ones were picked by
--> looking at them and resolved from their decal to the image underneath.
--> Configs.Upgrades carries its own copies as plain strings, since the tree editor plugin rewrites
--> that file and cannot follow a require.

local function Id(Number: number): string
	return "rbxassetid://" .. Number
end

return {
	--> already in the place: the shop's own art
	Trophy = Id(73898620648802),
	Clover = Id(78045260176458),
	Ticket = Id(109116277315334),
	Cash = Id(139241177703025),

	--> the shop and the tree
	Sneaker = Id(100093128978218),
	Crown = Id(675103130),
	Jetpack = Id(13220467566),
	Gift = Id(591644027),
	Shield = Id(132769868),

	--> one set of dice, drawn alike: gold for the luck nodes past the clovers, rainbow for anything
	--> that makes rolls quicker, white for one more pad, celestial for the server's luck
	DiceGold = Id(92190657341460),
	DiceRainbow = Id(116904434697196),
	DiceWhite = Id(101771429151948),
	DiceCelestial = Id(137764937081540),

	--> the gears, for the hotbar, which only takes an image
	WoodenBat = Id(14583816373),
	SteelBat = Id(17668674217),
	Bomb = Id(17724514739),
	TNT = Id(122062844480032),
	Goo = Id(13510998982),
	Trap = Id(6977364783),
	SpeedPotion = Id(131981582617200),
	InvisibilityCloak = Id(13871580573),
	CoilBlue = Id(5641003827),
	CoilGreen = Id(138578361104613),
	CoilRed = Id(123249466429400),
}
