--> Who gets the Kmdr console. Studio always counts so a solo playtest never needs this file
--> touched, and a user owned place lets its owner in without an ID lookup. Everyone else has
--> to be listed here by UserId.

return {
	UserIds = {
		-- [123456789] = true,
	} :: { [number]: boolean },

	ActivationKeys = { Enum.KeyCode.F2 },

	PlaceName = "Run an Office",

	--> Turning this off hands the console to every player on a live server, which is only
	--> ever safe in a private test place.
	RestrictInGame = true,
}
