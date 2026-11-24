extends Node
## Boot: shared UI theme, load the last profile, apply settings, go to menu.

func _ready() -> void:
	get_tree().root.theme = UITheme.make()
	if SaveSys.has_save():
		SaveSys.load_profile()
	Settings.apply()
	get_tree().change_scene_to_file.call_deferred(Game.MENU_SCENE)
