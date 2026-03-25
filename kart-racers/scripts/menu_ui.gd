extends Control

signal drive_pressed

var main_menu: VBoxContainer
var settings_screen: Control
var sliders: Dictionary = {}

const BG_COLOR := Color(0.1, 0.1, 0.15, 1.0)
const GOLD := Color(1.0, 0.85, 0.3)
const BUTTON_BG := Color(0.18, 0.18, 0.25)
const BUTTON_HOVER := Color(0.25, 0.25, 0.35)
const BUTTON_BORDER := Color(0.4, 0.4, 0.6)
const ACCENT_GREEN := Color(0.3, 0.8, 0.4)
const ACCENT_RED := Color(0.9, 0.35, 0.3)


func _ready() -> void:
	_build_main_menu()
	_build_settings_screen()
	show_main_menu()


func show_main_menu() -> void:
	main_menu.visible = true
	settings_screen.visible = false
	visible = true


func _show_settings() -> void:
	main_menu.visible = false
	settings_screen.visible = true
	_refresh_sliders()


# === MAIN MENU ===

func _build_main_menu() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	main_menu = VBoxContainer.new()
	main_menu.set_anchors_preset(PRESET_CENTER)
	main_menu.position = Vector2(640, 260)
	main_menu.size = Vector2(400, 300)
	main_menu.pivot_offset = Vector2(200, 150)
	main_menu.alignment = BoxContainer.ALIGNMENT_CENTER
	main_menu.add_theme_constant_override("separation", 20)
	add_child(main_menu)

	# Kart emoji
	var emoji := Label.new()
	emoji.text = "🏎️"
	emoji.add_theme_font_size_override("font_size", 64)
	emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_menu.add_child(emoji)

	# Title
	var title := Label.new()
	title.text = "ELEK'S KART RACERS"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_menu.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "A racing game by Elek"
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_menu.add_child(subtitle)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	main_menu.add_child(spacer)

	# DRIVE button
	var drive_btn := _make_button("DRIVE", ACCENT_GREEN)
	drive_btn.pressed.connect(_on_drive)
	main_menu.add_child(drive_btn)

	# SETTINGS button
	var settings_btn := _make_button("SETTINGS", BUTTON_BORDER)
	settings_btn.pressed.connect(_show_settings)
	main_menu.add_child(settings_btn)


func _on_drive() -> void:
	visible = false
	emit_signal("drive_pressed")


# === SETTINGS SCREEN ===

func _build_settings_screen() -> void:
	settings_screen = Control.new()
	settings_screen.set_anchors_preset(PRESET_FULL_RECT)
	add_child(settings_screen)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(PRESET_FULL_RECT)
	settings_screen.add_child(bg)

	# Header
	var header := Label.new()
	header.text = "SETTINGS"
	header.add_theme_font_size_override("font_size", 32)
	header.add_theme_color_override("font_color", GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.position = Vector2(0, 20)
	header.size = Vector2(1280, 50)
	settings_screen.add_child(header)

	# Scroll container
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(200, 80)
	scroll.size = Vector2(880, 540)
	settings_screen.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(860, 0)
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	# Build sliders by section
	for section in Settings.get_sections():
		var section_label := Label.new()
		section_label.text = section
		section_label.add_theme_font_size_override("font_size", 22)
		section_label.add_theme_color_override("font_color", GOLD)
		vbox.add_child(section_label)

		var sep := HSeparator.new()
		vbox.add_child(sep)

		for key in Settings.get_settings_for_section(section):
			var meta: Array = Settings.SETTING_META[key]
			var row := _make_slider_row(key, meta[1], meta[2], meta[3], Settings.get(key))
			vbox.add_child(row)

		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 12)
		vbox.add_child(spacer)

	# Bottom buttons
	var btn_row := HBoxContainer.new()
	btn_row.position = Vector2(350, 640)
	btn_row.size = Vector2(580, 50)
	btn_row.add_theme_constant_override("separation", 20)
	settings_screen.add_child(btn_row)

	var reset_btn := _make_button("RESET DEFAULTS", ACCENT_RED)
	reset_btn.pressed.connect(_on_reset_defaults)
	btn_row.add_child(reset_btn)

	var back_btn := _make_button("BACK", BUTTON_BORDER)
	back_btn.pressed.connect(show_main_menu)
	btn_row.add_child(back_btn)


func _make_slider_row(key: String, min_val: float, max_val: float, step: float, current: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	# Label
	var label := Label.new()
	label.text = key.replace("_", " ").capitalize()
	label.custom_minimum_size = Vector2(220, 0)
	label.add_theme_font_size_override("font_size", 15)
	row.add_child(label)

	# Slider
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = current
	slider.custom_minimum_size = Vector2(400, 30)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	# Value display
	var value_label := Label.new()
	value_label.text = _format_value(current)
	value_label.custom_minimum_size = Vector2(60, 0)
	value_label.add_theme_font_size_override("font_size", 15)
	value_label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	row.add_child(value_label)

	slider.value_changed.connect(func(val: float) -> void:
		Settings.set(key, val)
		Settings.save_settings()
		value_label.text = _format_value(val)
	)

	sliders[key] = {"slider": slider, "label": value_label}
	return row


func _refresh_sliders() -> void:
	for key in sliders:
		var s: Dictionary = sliders[key]
		var val: float = Settings.get(key)
		s["slider"].value = val
		s["label"].text = _format_value(val)


func _on_reset_defaults() -> void:
	Settings.reset_defaults()
	_refresh_sliders()


func _format_value(val: float) -> String:
	if abs(val - round(val)) < 0.001:
		return str(int(val))
	return "%.2f" % val


func _make_button(text: String, border_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(200, 45)
	btn.add_theme_font_size_override("font_size", 18)

	var style := StyleBoxFlat.new()
	style.bg_color = BUTTON_BG
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = BUTTON_HOVER
	hover_style.border_color = border_color
	hover_style.set_border_width_all(2)
	hover_style.set_corner_radius_all(6)
	hover_style.set_content_margin_all(10)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = border_color.darkened(0.3)
	pressed_style.border_color = border_color
	pressed_style.set_border_width_all(2)
	pressed_style.set_corner_radius_all(6)
	pressed_style.set_content_margin_all(10)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	return btn
