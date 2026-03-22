extends Resource
class_name ItemData

@export var item_name: String

@export_group("Visuals")
@export var is_tool: bool = false
@export var single_texture: Texture2D
@export var head_texture: Texture2D
@export var handle_texture: Texture2D

@export_group("The Recipe")
@export var req_axe_head: String = ""
@export var req_pickaxe_head: String = ""
@export var req_handle_slot: String = ""

@export_group("Stats")
@export var is_stackable: bool = false
@export var stack_limit: int = 0
@export var damage: float = 0.0
@export var durability: float = 0.0
@export var efficiency: float = 0.0
