--> Everything the artist handed over lives under one folder, so a new effect is a drop in rather
--> than a path written into a controller.
local Folder = "SuitedStudios"

return {
	Folder = Folder,

	--> The tier a part rolled into, from Tiers.FromVariant, to the aura that stands on it. Common
	--> and Uncommon are deliberately absent: an aura on the parts most rolls hand out is an aura
	--> nobody reads as one.
	--> Boost is a thumb on the scale for art that was drawn too small to read once it has been
	--> fitted to an item. Rare's stars are seven hundredths of a stud across at the size they were
	--> drawn, which on a keyboard is a couple of pixels and reads as nothing at all; the rest of the
	--> ladder was drawn big enough to leave alone.
	Auras = {
		Rare = { Effect = "Rare", Boost = 2.4 },
		Epic = { Effect = "Epic" },
		Legendary = { Effect = "Legendary" },
		Mythic = { Effect = "Mythical" },
		Divine = { Effect = "Secret" },
	} :: { [string]: { Effect: string, Boost: number? } },

	--> The part every aura was drawn against. An aura on an item is that art resized, so this is
	--> what it is resized from. The diagonal is what the resizing is measured in and not the volume:
	--> a keyboard is nearly flat, and a cube root of volume collapses on anything flat enough while
	--> the diagonal never does.
	Reference = Vector3.new(4, 1, 2),

	--> Emission scales with the square of the item rather than with the item, because a rate is a
	--> count spread over a surface: an aura twice as long is four times the art to cover. Held under
	--> a ceiling so one enormous item cannot hand the renderer a thousand particles a second.
	RateExponent = 2,
	RateCeiling = 240,

	--> An item under the first of these reads as wearing no aura at all; one over the second wears
	--> an aura instead of the other way round.
	MinScale = 0.35,
	MaxScale = 3,

	--> How many particles one press of a burst is worth, per emitter, and what colour it comes out.
	--> These are impact rings drawn as a single expanding particle each, so one apiece is the whole
	--> effect.
	--> Both ship tinted a lime green, which reads as a thing of its own rather than as the gift
	--> coming apart, and fights whatever the burst happens to go off over. White lets the art's own
	--> shading carry it and sits on any background. Set a Tint back to nil to keep the art's colour.
	Bursts = {
		Click = { Count = 1, Tint = Color3.new(1, 1, 1) },
		BuyMax = { Count = 1, Tint = Color3.new(1, 1, 1) },
	} :: { [string]: { Count: number, Tint: Color3? } },

	Footsteps = {
		--> The template the puff is thrown from.
		Effect = "WalkDust",

		--> Where in each loop a foot is planted, as a fraction of the loop, and which foot it is.
		--> Read off the animation's own phase rather than off distance travelled, because the
		--> employee rigs walk at a speed the upgrade tree moves while their loop plays at a fixed
		--> one -- anything measured in studs comes apart the moment that multiplier is not 1, and
		--> the dust slides away from the feet throwing it.
		--> Every number here was measured by sampling how low each foot got across the loop, not
		--> guessed: all three lead with the right foot, and the run plants later in its loop than
		--> the two walks do. A loop that is not named here throws no dust, which is what keeps
		--> standing still, a jump and an employee typing at a desk from throwing any.
		Plants = {
			RunAnim = { { Phase = 0.25, Right = true }, { Phase = 0.75, Right = false } },
			WalkAnim = { { Phase = 0.18, Right = true }, { Phase = 0.68, Right = false } },
			Walking = { { Phase = 0.18, Right = true }, { Phase = 0.68, Right = false } },
		} :: { [string]: { { Phase: number, Right: boolean } } },

		--> A track on its way out is still playing for a fraction of a second after the walk ended,
		--> and a puff thrown from one lands under someone already standing still.
		MinWeight = 0.5,

		--> Feet, in the order they are looked for. R15 names its feet, R6 and the employee rigs stop
		--> at the leg, and the sole of either is the bottom of the part.
		Feet = {
			{ Left = "LeftFoot", Right = "RightFoot" },
			{ Left = "Left Leg", Right = "Right Leg" },
		},

		--> How much of a puff one footfall is worth.
		Emit = 2,

		--> The box the dust is thrown from. Small on purpose: a footfall is a point, and the
		--> template is a four stud slab only because that is what it was drawn on.
		Size = Vector3.new(0.8, 0.2, 0.8),

		--> Off the floor, so the puff is not born half inside it.
		Lift = 0.1,
	},
}
