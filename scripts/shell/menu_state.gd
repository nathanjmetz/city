class_name MenuState
## Whether the pause menu (GameMenu) is up. Kept apart from GameMenu so the
## camera and the Pad autoload can check it without loading the menu.

## True while the pause menu is up: the camera, the pad and the game's keys
## leave the town alone underneath it.
static var showing := false
## True while a panel covers the town (All roads): the camera takes no wheel,
## trackpad, drag or key input, so scrolling the panel never moves the map
## behind it (the review of #939, 2026-10-29).
static var covering := false


## The interface owns the mouse and keys: the camera leaves the town alone.
static func owns_input() -> bool:
	return showing or covering
