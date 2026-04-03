# res://Scripts/Core/BattleUI.gd
extends CanvasLayer
class_name BattleUI

const PIECE_SCENE = preload("res://Scenes/PieceNode.tscn")

# 画面の部品（UI）への参照
@onready var player_portrait: TextureRect = $PlayerPortrait
@onready var enemy_portrait: TextureRect = $EnemyPortrait

@onready var draw_count_label: Label = $DeckUI/DrawCountLabel
@onready var discard_count_label: Label = $DeckUI/DiscardCountLabel
@onready var deck_view_panel: Panel = $DeckUI/DeckViewPanel
@onready var item_list: VBoxContainer = $DeckUI/DeckViewPanel/ScrollContainer/ItemList

@onready var view_draw_button: Button = $DeckUI/ViewDrawButton
@onready var view_discard_button: Button = $DeckUI/ViewDiscardButton
@onready var dim_overlay: ColorRect = $DeckUI/DimOverlay
@onready var damage_label: Label = $DamageLabel

@onready var player_hp_bar: ProgressBar = $PlayerHPBar
@onready var enemy_hp_bar: ProgressBar = $EnemyHPBar
@onready var player_hp_text: Label = $PlayerHPBar/PlayerHPText
@onready var enemy_hp_text: Label = $EnemyHPBar/EnemyHPText

@onready var result_overlay: ColorRect = $ResultOverlay
@onready var result_label: Label = $ResultOverlay/ResultLabel
@onready var execute_button: Button = $ExecuteButton

var current_view_type: String = ""

func _ready() -> void:
	if damage_label:
		damage_label.modulate.a = 0.0
	
	# ボタンの信号を接続
	if view_draw_button and not view_draw_button.pressed.is_connected(_on_view_draw_button_pressed):
		view_draw_button.pressed.connect(_on_view_draw_button_pressed)
	if view_discard_button and not view_discard_button.pressed.is_connected(_on_view_discard_button_pressed):
		view_discard_button.pressed.connect(_on_view_discard_button_pressed)

# 画像のセット
func setup_portraits(player_data: PlayerData, enemy_data: EnemyData) -> void:
	if player_data and player_portrait and player_data.texture:
		player_portrait.texture = player_data.texture
	if enemy_data and enemy_portrait and enemy_data.texture:
		enemy_portrait.texture = enemy_data.texture

# HPの更新
func update_hp_ui(player_hp: int, player_max: int, enemy_hp: int, enemy_max: int) -> void:
	if player_hp_bar:
		player_hp_bar.max_value = player_max
		player_hp_bar.value = player_hp
		player_hp_text.text = str(player_hp) + " / " + str(player_max)
	if enemy_hp_bar and enemy_max > 0:
		enemy_hp_bar.max_value = enemy_max
		enemy_hp_bar.value = enemy_hp
		enemy_hp_text.text = str(enemy_hp) + " / " + str(enemy_max)

# 山札の枚数更新
func update_deck_ui(draw_count: int, discard_count: int) -> void:
	if draw_count_label: draw_count_label.text = "山札: " + str(draw_count)
	if discard_count_label: discard_count_label.text = "捨て札: " + str(discard_count)

# ダメージ演出
func show_damage_popup(text: String) -> void:
	if not damage_label: return
	damage_label.text = text
	var tween = create_tween()
	damage_label.modulate.a = 1.0
	damage_label.scale = Vector2(1.5, 1.5)
	tween.tween_property(damage_label, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.0)
	tween.tween_property(damage_label, "modulate:a", 0.0, 0.5)

# 勝敗のリザルト画面
func show_result(is_victory: bool) -> void:
	if execute_button: execute_button.disabled = true
	if is_victory:
		result_label.text = "GAME CLEAR!"
		result_label.add_theme_color_override("font_color", Color(1, 1, 0))
	else:
		result_label.text = "GAME OVER..."
		result_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
		
	result_overlay.visible = true
	result_overlay.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(result_overlay, "modulate:a", 1.0, 1.0)

# --- 山札・捨て札の確認画面 ---
func _on_view_draw_button_pressed() -> void:
	if deck_view_panel.visible and current_view_type == "draw": _close_deck_view()
	else:
		current_view_type = "draw"
		_show_deck_view("【山札の中身】", DeckManager.draw_pile)

func _on_view_discard_button_pressed() -> void:
	if deck_view_panel.visible and current_view_type == "discard": _close_deck_view()
	else:
		current_view_type = "discard"
		_show_deck_view("【捨て札の中身】", DeckManager.discard_pile)

func _close_deck_view() -> void:
	deck_view_panel.visible = false
	dim_overlay.visible = false
	current_view_type = ""
	
	if execute_button:
		execute_button.disabled = false

func _show_deck_view(title_text: String, pile: Array) -> void:
	if execute_button:
		execute_button.disabled = true
	
	for child in item_list.get_children(): child.queue_free()
		
	var top_spacer = Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 40)
	item_list.add_child(top_spacer)
	
	if pile.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "（空っぽです）"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		item_list.add_child(empty_lbl)
	else:
		var grid = GridContainer.new()
		grid.columns = 5
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		grid.add_theme_constant_override("h_separation", 15)
		grid.add_theme_constant_override("v_separation", 15)
		item_list.add_child(grid)
		
		for data in pile:
			var piece_space = Control.new()
			piece_space.custom_minimum_size = Vector2(80, 80)
			
			var piece_node = PIECE_SCENE.instantiate()
			piece_node.piece_data = data
			piece_node.input_pickable = false 
			piece_node.position = Vector2(40, 40)
			
			if piece_node.is_in_group("pieces"): piece_node.remove_from_group("pieces")
			
			piece_space.add_child(piece_node)
			grid.add_child(piece_space)
			
			piece_node.info_ui.visible = false
			piece_node.info_ui.top_level = true
			
			piece_space.mouse_entered.connect(func():
				piece_node.info_ui.visible = true
				piece_node.z_index = 100
				piece_node.info_ui.global_position = piece_node.global_position + Vector2(20, -20)
			)
			piece_space.mouse_exited.connect(func():
				piece_node.info_ui.visible = false
				piece_node.z_index = 0
			)
			
	var bottom_spacer = Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, 60)
	item_list.add_child(bottom_spacer)
	dim_overlay.visible = true
	deck_view_panel.visible = true
