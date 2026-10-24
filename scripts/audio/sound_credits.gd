class_name SoundCredits
extends RefCounted
## Credits for the field recordings the town plays, shown under Credits in the
## pause menu. Keep in step with assets/audio/LICENSES.md.

const LINES := [
	"Music: metzguy",
	"Katydids: peterwchen (CC BY 4.0)",
	"Leaves, meadow and wind: Gravity Sound (CC BY 4.0)",
	"Grain dryer: Work With Sounds / Linköping University (CC BY 4.0)",
	"Garden birds: ezwa (public domain)",
	"Highway: stephan (public domain)",
	"Air conditioner: Ranch9613 (CC0)",
	"All via Wikimedia Commons.",
	"Sound picker options: Kenney and the Versilian Community Sample Library (CC0)",
]


static func text() -> String:
	return "Music and sounds\n" + "\n".join(LINES)
