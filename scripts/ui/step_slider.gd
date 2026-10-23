class_name StepSlider
extends HBoxContainer
## One broad slider with five steps (Funding: Lean to Generous, Growth: Hold
## to Expand; see Policies). It shows the step in force, in coral when it's
## set right here and muted when it follows the town or its area, with a
## small button to go back to following.

signal picked(step: int)   # -1 = follow the scope above again

var slider_kind := ""
var _slider := HSlider.new()
var _value := UiStyle.label("", 12)
var _follow := Button.new()
var _quiet := false


func _init(kind: String, title: String, tip: String, title_width := 64.0, resettable := true) -> void:
	slider_kind = kind
	add_theme_constant_override("separation", 6)
	var name_label := UiStyle.label(title, 12, UiStyle.MUTED)
	name_label.custom_minimum_size.x = title_width
	name_label.tooltip_text = tip
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(name_label)
	_slider.min_value = 0
	_slider.max_value = Policies.STEP_NAMES[kind].size() - 1
	_slider.step = 1
	_slider.tick_count = Policies.STEP_NAMES[kind].size()
	_slider.ticks_on_borders = true
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.custom_minimum_size = Vector2(112, 18)
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.tooltip_text = tip
	_slider.value_changed.connect(func(v):
		if not _quiet:
			picked.emit(int(v)))
	add_child(_slider)
	_value.custom_minimum_size.x = 76
	add_child(_value)
	_follow.text = "↺"
	_follow.flat = true
	_follow.focus_mode = Control.FOCUS_NONE
	_follow.custom_minimum_size = Vector2(20, 18)
	_follow.add_theme_font_size_override("font_size", 12)
	_follow.pressed.connect(func(): picked.emit(-1))
	_follow.visible = false
	_follow.modulate.a = 1.0 if resettable else 0.0
	_follow.disabled = not resettable
	add_child(_follow)


## Shows `step`; `own` if it's set on this scope, else `follows` names what
## it takes after ("the town", "Farms").
func show_step(step: int, own: bool, follows := "") -> void:
	_quiet = true
	_slider.value = step
	_quiet = false
	_value.text = Policies.STEP_NAMES[slider_kind][step]
	_value.add_theme_color_override("font_color", UiStyle.ACCENT if own and step != Policies.STANDARD else
		(UiStyle.TEXT if own else UiStyle.MUTED))
	_value.tooltip_text = Policies.STEP_TIPS[slider_kind][step] + ("" if own or follows == "" else
		" (same as %s)" % follows)
	_value.mouse_filter = Control.MOUSE_FILTER_PASS
	_follow.visible = own and not _follow.disabled
	_follow.tooltip_text = "Follow %s again" % follows if follows != "" else ""
