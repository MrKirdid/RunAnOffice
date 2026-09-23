--> The gear shop. Every entry is a Tool that lives in ReplicatedStorage.Assets.Gears under the same
--> key, bought once with cash and kept in the save for good; one at a time sits in the backpack.
--> The Tool in the place is only the look of it, a Handle and whatever mesh is on it: what a gear
--> does is in Server.Gears.Effects, keyed the same way, so none of it depends on scripts in the
--> place. A key with no Tool in the place yet gets a stand-in built off Placeholder, so the whole
--> shop plays before the models are in. Order is the shop's row order.

--> Nothing here hurts anyone: a gear flings, freezes, slows, hides or speeds up, and that is all.

export type Placeholder = {
	Color: Color3,
	Size: Vector3,
	Shape: Enum.PartType?,
	Material: Enum.Material?,
}

export type Gear = {
	Name: string,
	Description: string,
	Price: number,
	Order: number,

	--> seconds between uses, for a gear that is swung, thrown, placed or drunk
	Cooldown: number?,

	--> walk speed added while the tool is in hand, as a fraction: 0.2 is a fifth faster
	Speed: number?,

	--> how the model is turned before it is shown in the shop, for one that stands oddly
	IconRotation: CFrame?,

	--> the swing the character makes on a use: "Slash" or "Lunge", the two the default animate
	--> script knows, or nothing for a gear that is drunk or worn
	Animation: string?,

	--> how the tool sits in the hand and how big it is, over whatever the Tool in the place says:
	--> Grip is the Tool's Grip, Scale multiplies the whole model, grip offset included. Here so a
	--> bat can be turned round without opening the place.
	Grip: CFrame?,
	Scale: number?,

	--> built off Placeholder even when the place has a Tool for it: for a gear that is better as
	--> a plain shape than as any model, like a ball of goo
	Plain: boolean?,

	Placeholder: Placeholder,
}

local Gears = {
	--> A folder in ReplicatedStorage.Assets, one Tool per key.
	Folder = "Gears",

	List = {
		WoodenBat = {
			Name = "Wooden Bat",
			Description = "Swing to knock whoever is in front of you off their feet",
			Price = 2_500,
			Order = 1,
			Cooldown = 1.5,
			Animation = "Slash",
			Grip = CFrame.new(0, 0.8, 0) * CFrame.Angles(math.pi, 0, 0),
			Scale = 1.8,
			IconRotation = CFrame.Angles(math.pi, 0, 0),
			Placeholder = { Color = Color3.fromRGB(160, 110, 60), Size = Vector3.new(0.6, 0.6, 4) },
		},
		SpeedCoil1 = {
			Name = "Speed Coil",
			Description = "Run 20% faster while you hold it",
			Price = 5_000,
			Order = 2,
			Speed = 0.2,
			Placeholder = { Color = Color3.fromRGB(80, 200, 255), Size = Vector3.new(1, 3, 1) },
		},
		Goo = {
			Name = "Goo",
			Description = "Throw it. It splats where it lands and slows anyone who walks through",
			Price = 8_000,
			Order = 3,
			Cooldown = 12,
			Animation = "Lunge",
			Plain = true,
			Placeholder = {
				Color = Color3.fromRGB(90, 230, 60),
				Size = Vector3.new(1.4, 1.4, 1.4),
				Shape = Enum.PartType.Ball,
				Material = Enum.Material.Neon,
			},
		},
		Trap = {
			Name = "Trap",
			Description = "Sets a trap at your feet. The first player onto it is frozen",
			Price = 12_000,
			Order = 4,
			Cooldown = 15,
			Placeholder = { Color = Color3.fromRGB(120, 120, 130), Size = Vector3.new(2, 0.4, 2) },
		},
		SpeedPotion = {
			Name = "Speed Potion",
			Description = "Drink for a burst of speed",
			Price = 15_000,
			Order = 5,
			Cooldown = 45,
			Placeholder = { Color = Color3.fromRGB(255, 200, 60), Size = Vector3.new(0.8, 1.4, 0.8) },
		},
		SteelBat = {
			Name = "Steel Bat",
			Description = "Like the wooden one, but they go a lot further",
			Price = 25_000,
			Order = 6,
			Cooldown = 1.5,
			Animation = "Slash",
			Grip = CFrame.new(0, -1.6, 0),
			Scale = 0.7,
			Placeholder = { Color = Color3.fromRGB(190, 195, 205), Size = Vector3.new(0.6, 0.6, 4) },
		},
		Bomb = {
			Name = "Bomb",
			Description = "Drops a bomb. Anyone nearby when it goes off is sent flying",
			Price = 30_000,
			Order = 7,
			Cooldown = 10,
			Placeholder = { Color = Color3.fromRGB(30, 30, 35), Size = Vector3.new(2, 2, 2) },
		},
		SpeedCoil2 = {
			Name = "Speed Coil II",
			Description = "Run 40% faster while you hold it",
			Price = 40_000,
			Order = 8,
			Speed = 0.4,
			Placeholder = { Color = Color3.fromRGB(60, 140, 255), Size = Vector3.new(1, 3, 1) },
		},
		InvisibilityCloak = {
			Name = "Invisibility Cloak",
			Description = "Vanish for ten seconds",
			Price = 60_000,
			Order = 9,
			Cooldown = 40,
			Placeholder = { Color = Color3.fromRGB(120, 60, 200), Size = Vector3.new(2, 3, 0.4) },
		},
		SpeedCoil3 = {
			Name = "Speed Coil III",
			Description = "Run 60% faster while you hold it",
			Price = 120_000,
			Order = 10,
			Speed = 0.6,
			Placeholder = { Color = Color3.fromRGB(255, 90, 90), Size = Vector3.new(1, 3, 1) },
		},
		TNT = {
			Name = "TNT",
			Description = "Throw it where you point. A bigger bang than the bomb",
			Price = 150_000,
			Order = 11,
			Cooldown = 12,
			Animation = "Lunge",
			Placeholder = { Color = Color3.fromRGB(220, 50, 40), Size = Vector3.new(1.5, 2, 1.5) },
		},
	} :: { [string]: Gear },
}

--> Keys in shop order, so the shop and the console list them the same way.
function Gears.Sorted(): { string }
	local Keys = {}

	for Key in Gears.List do
		table.insert(Keys, Key)
	end

	table.sort(Keys, function(A: string, B: string): boolean
		return Gears.List[A].Order < Gears.List[B].Order
	end)

	return Keys
end

return Gears
