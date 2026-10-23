class_name MenuState
## Whether the pause menu (GameMenu) is up. Kept apart from GameMenu so the
## camera and the Pad autoload can check it without loading the menu.

## True while the pause menu is up: the camera, the pad and the game's keys
## leave the town alone underneath it.
static var showing := false
