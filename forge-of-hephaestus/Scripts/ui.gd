extends Control

# ==========================================
# 0. CUSTOM CLASS & VARIABLES
# ==========================================
class InventorySlot:
	var item: ItemData
	var count: int = 0

@onready var inv_grid = $Crafting_Panel/Inv
@onready var hotbar_grid = $HotBar_Panel/HotBar

@onready var slot_axe_btn = $Crafting_Panel/Slot_Axe_Head/Slot_Axe_Head_Btn
@onready var slot_pick_btn = $Crafting_Panel/Slot_Pickaxe_Head/Slot_Pickaxe_Head_Btn
@onready var slot_handle_btn = $Crafting_Panel/Slot_Handle/Slot_Handle_Btn
@onready var slot_res_btn = $Crafting_Panel/Slot_Res/Slot_Res_Btn

@onready var crafting_panel: Panel = $Crafting_Panel
@onready var hot_bar_panel: Panel = $HotBar_Panel

@export var all_recipes: Array[ItemData] = []
@export var empty_item: ItemData 

var player_inventory: Dictionary = {} 
const MAX_SLOTS = 18

# THE CURSOR SYSTEM
var held_slot: InventorySlot = null
var cursor_container: Control
var cursor_h_layer: TextureRect
var cursor_head_layer: TextureRect
var cursor_label: Label

var pending_result: ItemData = null
var craft_on: bool = false

# ==========================================
# 1. SETUP & CURSOR CREATION
# ==========================================
func _ready():
	craft_on = false
	update_ui_visibility() 
	
	# Pre-fill Main Inventory (0-17)
	for i in range(MAX_SLOTS):
		player_inventory[i] = create_empty_slot()
		
	# Pre-fill Forge Slots (Mapped to 100, 101, 102 so they act like normal inventory!)
	player_inventory[100] = create_empty_slot() # Axe
	player_inventory[101] = create_empty_slot() # Pick
	player_inventory[102] = create_empty_slot() # Handle
	
	setup_cursor_visuals()
	
	# Connect Forge Slots using GUI_INPUT to detect Right vs Left click
	slot_axe_btn.gui_input.connect(_on_any_slot_input.bind(100))
	slot_pick_btn.gui_input.connect(_on_any_slot_input.bind(101))
	slot_handle_btn.gui_input.connect(_on_any_slot_input.bind(102))
	slot_res_btn.pressed.connect(_on_craft_btn_pressed)
	
	# Connect Inventory
	var all_slots = inv_grid.get_children() + hotbar_grid.get_children()
	for i in range(all_slots.size()):
		all_slots[i].gui_input.connect(_on_any_slot_input.bind(i))
	
	update_all_visuals()

func setup_cursor_visuals():
	# Dynamically creates a floating UI element that follows the mouse
	cursor_container = Control.new()
	cursor_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_container.z_index = 100 # Keep on top of everything
	
	cursor_h_layer = TextureRect.new()
	cursor_h_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_head_layer = TextureRect.new()
	cursor_head_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Duplicates your existing label so the custom font carries over!
	cursor_label = inv_grid.get_child(0).get_node("Stack").duplicate()
	cursor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	cursor_container.add_child(cursor_h_layer)
	cursor_container.add_child(cursor_head_layer)
	cursor_container.add_child(cursor_label)
	add_child(cursor_container)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("inventory"):
		craft_on = !craft_on 
		update_ui_visibility()

	if Input.is_action_just_pressed("wood"):
		var test_item = load("res://Resources/wood.tres") 
		if test_item: add_item_to_inventory(test_item, 10)
		
	# Make the held item follow the mouse
	if cursor_container and cursor_container.visible:
		cursor_container.global_position = get_global_mouse_position() + Vector2(10, 10)

# Helper to instantly make an empty slot
func create_empty_slot() -> InventorySlot:
	var empty_slot = InventorySlot.new()
	empty_slot.item = empty_item
	empty_slot.count = 0
	return empty_slot

# ==========================================
# 2. CORE LOGIC: ADDING ITEMS
# ==========================================
func add_item_to_inventory(new_item: ItemData, amount: int = 1):
	var search_order = [9,10,11,12,13,14,15,16,17, 0,1,2,3,4,5,6,7,8]
	
	if new_item.is_stackable:
		var safe_limit = max(1, new_item.stack_limit)
		for i in search_order:
			var slot = player_inventory[i]
			if slot.item.item_name == new_item.item_name:
				if slot.count < safe_limit:
					var room = safe_limit - slot.count
					var adding = min(amount, room)
					slot.count += adding
					amount -= adding
					if amount <= 0:
						update_all_visuals()
						return

	while amount > 0:
		var found_slot = false
		for i in search_order:
			if player_inventory[i].item == empty_item:
				player_inventory[i].item = new_item.duplicate()
				var adding = 1
				if new_item.is_stackable:
					adding = min(amount, max(1, new_item.stack_limit))
				player_inventory[i].count = adding
				amount -= adding
				found_slot = true
				break 
		
		if not found_slot:
			print("Inventory Full!")
			break
			
	update_all_visuals()

# ==========================================
# 3. UNIVERSAL DRAG & DROP LOGIC
# ==========================================
func _on_any_slot_input(event: InputEvent, slot_index: int):
	if not craft_on: return
	
	# Only react to mouse clicks down
	if event is InputEventMouseButton and event.pressed:
		var is_right_click = (event.button_index == MOUSE_BUTTON_RIGHT)
		var is_left_click = (event.button_index == MOUSE_BUTTON_LEFT)
		
		if not is_left_click and not is_right_click: return
		
		var clicked_slot = player_inventory[slot_index]
		
		# STATE 1: MOUSE IS EMPTY (Pick up items)
		if held_slot == null:
			if clicked_slot.item != empty_item:
				if is_left_click:
					# Pick up entire stack
					held_slot = clicked_slot
					player_inventory[slot_index] = create_empty_slot()
				elif is_right_click:
					# Pick up exactly HALF the stack (Minecraft style!)
					var take_amount = max(1, clicked_slot.count / 2)
					held_slot = InventorySlot.new()
					held_slot.item = clicked_slot.item.duplicate()
					held_slot.count = take_amount
					
					clicked_slot.count -= take_amount
					if clicked_slot.count <= 0:
						player_inventory[slot_index] = create_empty_slot()

		# STATE 2: MOUSE IS HOLDING AN ITEM (Drop/Swap items)
		else:
			# If dropping into an empty slot
			if clicked_slot.item == empty_item:
				if is_left_click:
					# Drop all
					player_inventory[slot_index] = held_slot
					held_slot = null
				elif is_right_click:
					# Drop 1
					var drop_slot = InventorySlot.new()
					drop_slot.item = held_slot.item.duplicate()
					drop_slot.count = 1
					player_inventory[slot_index] = drop_slot
					
					held_slot.count -= 1
					if held_slot.count <= 0: held_slot = null
			
			# If dropping onto the SAME item type (Stacking)
			elif clicked_slot.item.item_name == held_slot.item.item_name and clicked_slot.item.is_stackable:
				if is_left_click:
					# Merge all possible
					var room = clicked_slot.item.stack_limit - clicked_slot.count
					var adding = min(held_slot.count, room)
					clicked_slot.count += adding
					held_slot.count -= adding
					if held_slot.count <= 0: held_slot = null
				elif is_right_click:
					# Add just 1 to the stack
					if clicked_slot.count < clicked_slot.item.stack_limit:
						clicked_slot.count += 1
						held_slot.count -= 1
						if held_slot.count <= 0: held_slot = null
			
			# If dropping onto a DIFFERENT item (Swapping)
			else:
				if is_left_click:
					var temp = clicked_slot
					player_inventory[slot_index] = held_slot
					held_slot = temp
					
		update_all_visuals()

# ==========================================
# 4. CRAFTING & RECIPE LOGIC
# ==========================================
func _on_craft_btn_pressed():
	if pending_result:
		# 1. Add result to inventory
		add_item_to_inventory(pending_result, 1)
		
		# 2. Consume 1 ingredient from each forge slot
		for i in [100, 101, 102]:
			if player_inventory[i].item != empty_item:
				player_inventory[i].count -= 1
				if player_inventory[i].count <= 0:
					player_inventory[i] = create_empty_slot()
					
		update_all_visuals()

func check_recipe():
	pending_result = null
	
	# Grab names from the forge slots (100, 101, 102)
	var axe_item = player_inventory[100].item
	var pick_item = player_inventory[101].item
	var han_item = player_inventory[102].item
	
	if axe_item == empty_item and pick_item == empty_item and han_item == empty_item: return
	
	var a_name = axe_item.item_name if axe_item != empty_item else ""
	var p_name = pick_item.item_name if pick_item != empty_item else ""
	var h_name = han_item.item_name if han_item != empty_item else ""
	
	for recipe in all_recipes:
		if recipe.req_axe_head == a_name and recipe.req_pickaxe_head == p_name and recipe.req_handle_slot == h_name:
			pending_result = recipe
			return

# ==========================================
# 5. UNIVERSAL VISUAL UPDATES
# ==========================================
func update_all_visuals():
	check_recipe()
	
	# Draw Inventory
	var all_ui_slots = inv_grid.get_children() + hotbar_grid.get_children()
	for i in range(all_ui_slots.size()):
		draw_slot_visuals(all_ui_slots[i], player_inventory[i].item, player_inventory[i].count)

	# Draw Forge Slots
	draw_slot_visuals(slot_axe_btn, player_inventory[100].item, player_inventory[100].count)
	draw_slot_visuals(slot_pick_btn, player_inventory[101].item, player_inventory[101].count)
	draw_slot_visuals(slot_handle_btn, player_inventory[102].item, player_inventory[102].count)
	
	# Draw Result Slot
	draw_slot_visuals(slot_res_btn, pending_result, 0)
	
	# Update floating cursor
	if held_slot:
		cursor_container.show()
		if held_slot.item.is_tool:
			cursor_h_layer.texture = held_slot.item.handle_texture
			cursor_head_layer.texture = held_slot.item.head_texture
		else:
			cursor_h_layer.texture = null
			cursor_head_layer.texture = held_slot.item.single_texture
			
		cursor_label.text = str(held_slot.count) if held_slot.count > 1 else ""
	else:
		cursor_container.hide()

func draw_slot_visuals(btn_node: Button, item: ItemData, count: int):
	var h_layer = btn_node.get_node_or_null("Layer_Handle")
	var head_layer = btn_node.get_node_or_null("Layer_Head")
	var label = btn_node.get_node_or_null("Stack")
	
	if item == null or item == empty_item:
		if h_layer: h_layer.texture = null
		if head_layer: head_layer.texture = null
		btn_node.icon = empty_item.single_texture if empty_item else null
		if label: label.hide()
		return
		
	if item.is_tool:
		if h_layer: h_layer.texture = item.handle_texture
		if head_layer: head_layer.texture = item.head_texture
		btn_node.icon = empty_item.single_texture 
	else:
		if h_layer: h_layer.texture = null
		if head_layer: head_layer.texture = item.single_texture 
		btn_node.icon = empty_item.single_texture 
		
	if label:
		label.text = str(count) if count > 1 else ""
		label.visible = count > 1

func update_ui_visibility():
	if craft_on:
		crafting_panel.show()
		hot_bar_panel.global_position.y = 420.177
	else:
		crafting_panel.hide()
		hot_bar_panel.global_position.y = 603.356
