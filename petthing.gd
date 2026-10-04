# I am very sorry I forgot to put comments so it's easier to read the code :(
# Hopefully its not too hard to read since its not too much code
# Also I should of probably written comments so I remember what I did lol

extends Node2D

var user_api_key: String = ""
var chat_history: Array = []
var max_history_turns: int = 10
var pending_file_name: String = ""
var pending_file_content: String = ""

var annoying_mode_enabled: bool = false
var idle_only_mode: bool = false
var is_active: bool = true
var annoying_cooldown: float = 0.0

var speed = 300.0
var direction = Vector2(1, 0)
var screen_size = Vector2()
var window_size = Vector2(64, 64)

var pet_window_size = Vector2i(64, 64)
var bubble_window_size = Vector2i(300, 200)

var idle_timer = 0.0
var is_idling = false
var walk_timer = 0.0

var is_dragging = false
var drag_offset = Vector2()
var last_mouse_pos = Vector2()
var throw_velocity = Vector2()

var is_thrown = false
var bounce_count = 0
var max_bounces = 2
var rotation_speed = 12.0

var current_bezel = "bottom"
var window_position: Vector2
var is_expanded: bool = false

@onready var animated_sprite = $AnimatedSprite2D
@onready var area = $Area2D 
@onready var http_request: HTTPRequest = $HTTPRequest
@onready var search_bubble: PanelContainer = $CanvasLayer/SearchBubble
@onready var line_edit: LineEdit = $CanvasLayer/SearchBubble/VBoxContainer/LineEdit
@onready var answer_label: Label = $CanvasLayer/SearchBubble/VBoxContainer/AnswerLabel
@onready var close_button: Button = $CanvasLayer/SearchBubble/VBoxContainer/CloseButton
@onready var context_menu = $CanvasLayer/ContextMenu

func _ready() -> void: 
	DisplayServer.window_set_size(Vector2i(64,64))
	window_size = Vector2i(64, 64)
	
	screen_size = Vector2(DisplayServer.screen_get_size())
	animated_sprite.play("walk")
	area.input_event.connect(_on_area_input)
	
	window_position = Vector2(DisplayServer.window_get_position())
	snap_to_nearest_bezel()
	load_api_key()
	_setup_ui()
	get_window().files_dropped.connect(_on_files_dropped)
	
	
	if not http_request.request_completed.is_connected(_on_gemini_response):
		http_request.request_completed.connect(_on_gemini_response)
		
	if not line_edit.text_submitted.is_connected(_on_line_edit_text_submitted):
		line_edit.text_submitted.connect(_on_line_edit_text_submitted)
		
	if not close_button.pressed.is_connected(_on_close_button_pressed):
		close_button.pressed.connect(_on_close_button_pressed)
	
func load_api_key() -> void:
	var config = ConfigFile.new()
	if config.load("user://neil_settings.cfg") == OK :
		user_api_key = config.get_value("settings", "gemini_api_key" )
	
func save_api_key(key: String) -> void:
	user_api_key = key.strip_edges()
	var config = ConfigFile.new()
	config.set_value("settings", "gemini_api_key", user_api_key)
	config.save("user://neil_settings.cfg")
	
	
func _setup_ui():
	context_menu.clear()
	context_menu.add_item(" Ask Neil (F1)", 0)
	context_menu.add_item("Set Gemini API Key (Optional)", 1)
	context_menu.add_separator()
	context_menu.add_check_item("Idle Only Mode", 2)
	context_menu.add_check_item("Annoying mode (Closes Tabs)", 3)
	context_menu.add_separator()
	context_menu.add_item("Let Neil sleep (He sleeps in the ISS)! (Exit)", 99)
	
	if not context_menu.id_pressed.is_connected(_on_menu_item_selected):
		context_menu.id_pressed.connect(_on_menu_item_selected)
		
		
	close_button.text = "Close"
	
	
	search_bubble.visible = false
	
	
func _on_menu_item_selected(id: int):
	match id:
		0:
			toggle_search_bubble()
		1:
			prompt_api_key_entry()
		2:
			idle_only_mode = !idle_only_mode
			context_menu.set_item_checked(context_menu.get_item_index(2), idle_only_mode)
			if idle_only_mode:
				is_idling = true
				speed = 0.0 
				animated_sprite.play("idle")
			else:
				is_idling = false
				speed = 300.0
				animated_sprite.play("walk")
		3:
			annoying_mode_enabled = !annoying_mode_enabled
			context_menu.set_item_checked(context_menu.get_item_index(3), annoying_mode_enabled)
		99:
			get_tree().quit()
			
			
func expand_window_for_bubble():
	if is_expanded:
		return
		
	is_expanded = true
	search_bubble.visible = true
	
	answer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	search_bubble.set_anchors_preset(Control.PRESET_TOP_LEFT)
	search_bubble.position = Vector2(64, 0)
	search_bubble.size = Vector2(300, 180)
	
	animated_sprite.position = Vector2(33, 26 + 180)
	area.position = Vector2(34, 20 + 180)
	
	var current_pos = DisplayServer.window_get_position()
	current_pos.y -= 180
	if current_pos.y < 0:
		current_pos.y = 0
		
	DisplayServer.window_set_position(current_pos)
	DisplayServer.window_set_size(Vector2i(364, 244))
	window_size = Vector2i(364, 244)


func shrink_window_to_pet():
	if not is_expanded:
		return
		
	is_expanded = false
	search_bubble.visible = false
	
	animated_sprite.position = Vector2(33, 26)
	area.position = Vector2(34, 20)
	
	var current_pos = DisplayServer.window_get_position()
	current_pos.y += 180
	
	DisplayServer.window_set_size(pet_window_size)
	window_size = Vector2(pet_window_size)
	DisplayServer.window_set_position(current_pos)
	snap_to_nearest_bezel()
	
func toggle_search_bubble():
	if search_bubble.visible:
		shrink_window_to_pet()
	else:
		expand_window_for_bubble()
		line_edit.text = ""
		line_edit.grab_focus()
		
		if user_api_key == "":
			prompt_api_key_entry()
		else:
			answer_label.text = "Ask Neil anything!!"
			line_edit.placeholder_text = "Type your query ... "
	
	
func prompt_api_key_entry():
	expand_window_for_bubble()
	answer_label.text = "Google AI integration (Optional)\n Get apikey at aistudio.google.com\n (Stored locally on your PC and it's a Open Source project)"
	line_edit.text = ""
	line_edit.placeholder_text = "Paste Api key here ..."
	
func _on_close_button_pressed():
	shrink_window_to_pet()
	

func _on_line_edit_text_submitted(new_text: String) -> void:
	var clean_text = new_text.strip_edges()
	
	if clean_text.begins_with("AQ.") or clean_text.begins_with("AIza"):
		save_api_key(clean_text)
		answer_label.text = "Key saved! What would you like to ask?"
		line_edit.text = ""
		line_edit.placeholder_text = "Type your query..."
		return

	if not pending_file_content.is_empty():
		var task_instruction = clean_text
		if task_instruction.is_empty():
			task_instruction = "Summarize or comment on this file in 1-2 short sentences."
			
		var prompt = "I am sharing a file named '" + pending_file_name + "'. Here are its contents:\n\n" + pending_file_content + "\n\nTask: " + task_instruction
		
		pending_file_name = ""
		pending_file_content = ""
		line_edit.placeholder_text = "Type your query..."
		
		ask_gemini(prompt)
		return

	if clean_text.is_empty():
		return
		
	ask_gemini(clean_text)
	
func ask_gemini(prompt_text: String) -> void:
	if user_api_key.is_empty():
		answer_label.text = "Please enter your Gemini API key first!"
		return
		
	var clean_key = user_api_key.strip_edges().replace(" ", "").replace("\n", "").replace("\r", "").replace('"', '').replace("'", "")
	var url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key=" + clean_key
	var headers = ["Content-Type: application/json"]
	
	chat_history.append({
		"role": "user",
		"parts": [{"text": prompt_text}]
	})
	
	
	var body = {
	"system_instruction": {
			"parts": [{"text": "You are Neil, a friendly astronaut desktop pet. Answer concisely in 1-2 short sentences."}]
		},
		"contents": chat_history
	}
	
	answer_label.text = "Neil is querying mission control..."
	line_edit.clear()
	
	var err = http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		chat_history.pop_back()
		print("HTTPRequest Error Code: ", err)
		answer_label.text = "Failed to send HTTP request. Code: " + str(err)

func _on_files_dropped(files: PackedStringArray) -> void:
	if files.is_empty():
		return
		
	var file_path = files[0]
	var file_name = file_path.get_file()
	var extension = file_path.get_extension().to_lower()
	
	
	var valid_extensions = ["txt", "gd", "md", "json", "py", "js", "html", "css", "cpp", "c", "h", "cfg"]
	
	if not valid_extensions.has(extension):
		expand_window_for_bubble()
		answer_label.text = "Neil can't read '." + extension + "' files! Drop a text or code file."
		return
		
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var file_content = file.get_as_text()
		file.close()
		
		if file_content.length() > 3000:
			file_content = file_content.substr(0, 3000) + "\n...[file truncated]"
			
		pending_file_name = file_name
		pending_file_content = file_content
		
		expand_window_for_bubble()
		answer_label.text = "Loaded '" + file_name + "'! Type a task or press Enter for a summary."
		line_edit.text = ""
		line_edit.placeholder_text = "e.g., 'Find bugs', 'Translate to Spanish'..."
		line_edit.grab_focus()
	else:
		expand_window_for_bubble()
		answer_label.text = "Failed to open file: " + file_name
		
		
func _on_gemini_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var response_str = body.get_string_from_utf8()
	
	if response_code == 200:
		var json = JSON.parse_string(response_str)
		if json and json.has("candidates") and json["candidates"].size() > 0:
			var reply = json["candidates"][0]["content"]["parts"][0]["text"]
			answer_label.text = reply
			
			chat_history.append({
				"role": "model",
				"parts": [{"text": reply}]
				
			})
		
		else:
			chat_history.pop_back()
			answer_label.text = "Neil couldn't process signal."
	elif response_code == 503:
		chat_history.pop_back()
		answer_label.text = "Mission control is busy (503). Retrying in a moment..."
	else:
		chat_history.pop_back()
		print("Google Server Response (Code ", response_code, "): ", response_str)
		answer_label.text = "Neil lost signal... HTTP Code: " + str(response_code)
		
		
func check_annoying_tab_jump(delta:float):
	if not annoying_mode_enabled or is_dragging or is_thrown:
		return
		
	annoying_cooldown += delta
	if annoying_cooldown >= 30.0:
		annoying_cooldown = 0.0
		if randf() < 0.25:
			execute_close_button_attack()
			
func execute_close_button_attack():
	current_bezel = "top"
	window_position = Vector2(screen_size.x - window_size.x, 0)
	DisplayServer.window_set_position(Vector2i(window_position))
	animated_sprite.play("flail")
	
	var ps_script = "Start-Sleep -Milliseconds 200; $wshell = New-Object -ComObject wscript.shell; $wshell.SendKeys('%{TAB}'); Start-Sleep -Milliseconds 100; $wshell.SendKeys('^{w}')"
	OS.execute("powershell", ["-Command", ps_script], [], false)
	land_and_idle()

func maybe_idle():
	if randf() < 0.45:
		is_idling = true 
		idle_timer = randf_range(2.0, 4.0)
		animated_sprite.play("idle")
		speed = 0.0
		
func land_and_idle():
	is_thrown = false
	is_idling = true
	idle_timer = 3.0
	animated_sprite.play("idle")
	speed = 0.0
	snap_to_nearest_bezel()
	
func snap_to_nearest_bezel():
	var dist_bottom = abs ((screen_size.y - window_size.y) -  window_position.y)
	var dist_top = abs(window_position.y)
	var dist_left = abs(window_position.x)
	var dist_right = abs((screen_size.x - window_size.x) - window_position.x)
	
	var min_dist = min(dist_bottom, min(dist_top, min (dist_left, dist_right )))
	
	if min_dist == dist_bottom:
		current_bezel = "bottom"
		window_position.y = screen_size.y - window_size.y
		direction = Vector2(-1,0) if randf() > 0.5 else Vector2(1,0)
	elif min_dist == dist_top:
		current_bezel = "top"
		window_position.y = 0.0
		direction = Vector2(1,0) if randf() > 0.5 else Vector2(-1,0)
	elif min_dist == dist_left:
		current_bezel = "left"
		window_position.x = 0.0
		direction = Vector2(0,1) if randf() > 0.5 else Vector2(0,-1)
	else:
		current_bezel = "right"
		window_position.x = screen_size.x - window_size.x
		direction = Vector2(0,1) if randf() > 0.5 else Vector2(0,-1)
		
	update_sprite_orientation()
	
func update_sprite_orientation():
		if is_thrown or is_dragging:
			return
			
		match current_bezel:
			"bottom":
				animated_sprite.rotation = 0.0
				animated_sprite.flip_h = (direction.x < 0)
			"top":
				animated_sprite.rotation = PI
				animated_sprite.flip_h = (direction.x > 0)
			"left":
				animated_sprite.rotation = PI / 2.0
				animated_sprite.flip_h = (direction.y < 0)
			"right":
				animated_sprite.rotation = -PI / 2.0
				animated_sprite.flip_h = (direction.y > 0)
		
func start_throw():
	if throw_velocity.length() > 60.0:
		is_thrown = true
		is_idling = false
		current_bezel = "floating"
		bounce_count = 0
		max_bounces = randi_range(1,2)
		speed = clamp(throw_velocity.length(),400.0, 900.0 )
		direction = throw_velocity.normalized()
		animated_sprite.play('flail')
	else:
		land_and_idle()
		
func _on_area_input(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = true
			current_bezel = "floating"
			var mouse_pos = Vector2(DisplayServer.mouse_get_position())
			var win_pos = Vector2(DisplayServer.window_get_position())
			drag_offset = mouse_pos - win_pos
			last_mouse_pos = mouse_pos
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			context_menu.position = Vector2i(get_viewport().get_mouse_position())
			context_menu.popup()

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and is_dragging:
			is_dragging = false
			start_throw()
			
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			throw_velocity = Vector2(randf_range(-500,500), -600)
			start_throw()
		elif event.keycode == KEY_F1:
			toggle_search_bubble()

func _physics_process(delta: float) -> void:
	if is_dragging: 
		var current_mouse_pos = Vector2(DisplayServer.mouse_get_position())
		if delta > 0:
			throw_velocity = (current_mouse_pos - last_mouse_pos) / delta
		last_mouse_pos = current_mouse_pos
		
		window_position = current_mouse_pos - drag_offset 
		DisplayServer.window_set_position(Vector2i(window_position))
		return
	
	if is_thrown:
		animated_sprite.rotation += rotation_speed * delta
		window_position += direction * speed * delta
		
		var hit_border = false
		
		if window_position.x <= 0 and direction.x < 0:
			direction.x *= -1
			window_position.x = 0
			hit_border = true
		elif window_position.x >= screen_size.x - window_size.x and direction.x > 0:
			direction.x *= -1
			window_position.x = screen_size.x - window_size.x 
			hit_border = true
			
		if window_position.y <= 0 and direction.y < 0:
			direction.y *= -1
			window_position.y = 0
			hit_border = true
		elif window_position.y >= screen_size.y - window_size.y and direction.y > 0:
			direction.y *= -1
			window_position.y = screen_size.y - window_size.y
			hit_border = true
		
		if hit_border:
			bounce_count += 1
			if bounce_count >= max_bounces:
				land_and_idle()
				return
				
		DisplayServer.window_set_position(Vector2i(window_position))
		return

	
	check_annoying_tab_jump(delta)
	
	if idle_only_mode:
		if animated_sprite.animation != "idle":
			animated_sprite.play("idle")
		return
	
	if is_idling:
		idle_timer -= delta
		if idle_timer <= 0:
			is_idling = false
			speed = 300.0
			animated_sprite.play("walk")
		return

	walk_timer += delta
	if walk_timer >= 4.0:
		walk_timer = 0.0
		maybe_idle()
			
	window_position += direction * speed * delta
	
	if current_bezel == "bottom" or current_bezel == "top":
		if window_position.x <= 0 and direction.x < 0:
			direction.x *= -1
			window_position.x = 0.0
			update_sprite_orientation()
		elif window_position.x >= screen_size.x - window_size.x and direction.x > 0:
			direction.x *= -1
			window_position.x = screen_size.x - window_size.x
			update_sprite_orientation()
	elif current_bezel == "left" or current_bezel == "right":
		if window_position.y <= 0 and direction.y < 0:
			direction.y *= -1
			window_position.y = 0.0
			update_sprite_orientation()
		elif window_position.y >= screen_size.y - window_size.y and direction.y > 0:
			direction.y *= -1
			window_position.y = screen_size.y - window_size.y
			update_sprite_orientation()
		
	DisplayServer.window_set_position(Vector2i(window_position))
