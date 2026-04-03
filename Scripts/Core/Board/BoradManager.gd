# res://Scripts/BoardManager.gd
extends Node
class_name BoardManager

const ROWS: int = 6
const COLS: int = 10

const CELL_SIZE: float = 64.0
@onready var board_guide: ColorRect = $BoardGuide # ※パスは実際のツリーに合わせてください
@onready var BOARD_OFFSET: Vector2 = board_guide.position

var grid_system: GridSystem

var current_view_type: String = ""

@export var player_data: PlayerData
@export var current_enemy: EnemyData
const PIECE_SCENE = preload("res://Scenes/PieceNode.tscn")

@onready var battle_ui: BattleUI = $UILayer

var hand_manager: HandManager

@onready var execute_button: Button = $UILayer/ExecuteButton

var current_enemy_hp: int = 0

func _ready() -> void:
	if board_guide: board_guide.visible = false
	
	grid_system = GridSystem.new()
	add_child(grid_system)
	grid_system.initialize_grid()
	
	battle_ui.setup_portraits(player_data, current_enemy)
	
	hand_manager = HandManager.new()
	add_child(hand_manager)
	hand_manager.piece_picked_up_signal.connect(_on_piece_picked_up)
	hand_manager.piece_dropped_signal.connect(_on_piece_dropped)
	
	if player_data:
		DeckManager.player_max_hp = player_data.max_hp
		DeckManager.player_current_hp = player_data.max_hp
		if DeckManager.master_deck.is_empty():
			DeckManager.master_deck = player_data.starting_deck.duplicate()
	
	if current_enemy:
		current_enemy_hp = current_enemy.max_hp
		
	_update_hp_ui()
	DeckManager.prepare_battle()

	hand_manager.draw_new_hand(5, self)
	_enemy_action_phase()
	_update_deck_ui()
	
func _update_hp_ui():
	var enemy_max = current_enemy.max_hp if current_enemy else 0
	battle_ui.update_hp_ui(DeckManager.player_current_hp, DeckManager.player_max_hp, current_enemy_hp, enemy_max)

func _update_deck_ui() -> void:
	battle_ui.update_deck_ui(DeckManager.draw_pile.size(), DeckManager.discard_pile.size())	
		
func _on_piece_picked_up(piece_node: PieceNode) -> void:
	var pos = piece_node.board_pos
	if pos.x != -1 and pos.y != -1:
		grid_system.clear_piece_at(pos.x, pos.y)
	
	_update_all_connections() # ★追加：持ち上げられたので接続状態を再計算

func _on_piece_dropped(piece_node: PieceNode, drop_pos: Vector2) -> void:
	var local_pos = drop_pos - BOARD_OFFSET
	var grid_x = int(local_pos.x / CELL_SIZE)
	var grid_y = int(local_pos.y / CELL_SIZE)
	
	# 盤面外にドロップされた場合 -> 失敗処理（手札に戻す）
	if local_pos.x < 0 or local_pos.y < 0 or grid_x >= COLS or grid_y >= ROWS:
		hand_manager.handle_placement_failure(piece_node)
		_update_all_connections() # 念のため光の更新
		return
	
	# GridSystem に配置可能か判定を依頼する
	if grid_system.can_place_piece(piece_node.piece_data, grid_x, grid_y):
		# 【成功】盤面にデータをセット
		grid_system.set_piece_at(grid_x, grid_y, piece_node.piece_data)
		piece_node.board_pos = Vector2i(grid_x, grid_y) 
		
		# マス目の中央にスナップ（吸着）させる
		var snap_x = BOARD_OFFSET.x + (grid_x * CELL_SIZE) + (CELL_SIZE / 2.0)
		var snap_y = BOARD_OFFSET.y + (grid_y * CELL_SIZE) + (CELL_SIZE / 2.0)
		piece_node.global_position = Vector2(snap_x, snap_y)
		
		# HandManager に依頼して手札リストから外し、残りを並べ直す
		hand_manager.remove_from_hand(piece_node)
			
		print("配置成功！ [", grid_x, ", ", grid_y, "]")
		_update_all_connections() 
	else:
		# 【失敗】ジョイントが合わないなど -> 失敗処理（手札に戻す）
		print("配置失敗！ ジョイントが合いません。")
		hand_manager.handle_placement_failure(piece_node)
		_update_all_connections()

func _update_all_connections() -> void:
	var all_pieces = get_tree().get_nodes_in_group("pieces")
	
	for piece in all_pieces:
		var pos = piece.board_pos
		
		# もし盤面外（手札）にいるなら、全て false（光らない）にして次へ
		if pos.x == -1 or pos.y == -1:
			piece.set_connections([false,false,false], [false,false,false], [false,false,false], [false,false,false])
			continue
			
		var c_top = [false, false, false]
		var c_bottom = [false, false, false]
		var c_left = [false, false, false]
		var c_right = [false, false, false]
		var my_data = piece.piece_data
		
		if pos.x + 1 < COLS and grid_system.get_piece_at(pos.x + 1, pos.y) != null:
			var neighbor = grid_system.get_piece_at(pos.x + 1, pos.y)
			var n_data = neighbor.piece_data if (neighbor is Node) else neighbor
			for i in range(3):
				if grid_system.is_interlocking(my_data.right_joints[i], n_data.left_joints[i]): c_right[i] = true
					
		if pos.x - 1 >= 0 and grid_system.get_piece_at(pos.x - 1, pos.y) != null:
			var neighbor = grid_system.get_piece_at(pos.x - 1, pos.y)
			var n_data = neighbor.piece_data if (neighbor is Node) else neighbor
			for i in range(3):
				if grid_system.is_interlocking(my_data.left_joints[i], n_data.right_joints[i]): c_left[i] = true
					
		if pos.y + 1 < ROWS and grid_system.get_piece_at(pos.x, pos.y + 1) != null:
			var neighbor = grid_system.get_piece_at(pos.x, pos.y + 1)
			var n_data = neighbor.piece_data if (neighbor is Node) else neighbor
			for i in range(3):
				if grid_system.is_interlocking(my_data.bottom_joints[i], n_data.top_joints[i]): c_bottom[i] = true
					
		if pos.y - 1 >= 0 and grid_system.get_piece_at(pos.x, pos.y - 1) != null:
			var neighbor = grid_system.get_piece_at(pos.x, pos.y - 1)
			var n_data = neighbor.piece_data if (neighbor is Node) else neighbor
			for i in range(3):
				if grid_system.is_interlocking(my_data.top_joints[i], n_data.bottom_joints[i]): c_top[i] = true
					
		piece.set_connections(c_top, c_bottom, c_left, c_right)

# 実行ボタンが押された時の処理
func _on_execute_button_pressed() -> void:
	print("\n=== 1. 効果解決フェーズ ===")
	_resolve_effects()
	
	print("\n=== 2. クリーンアップ ===")
	_cleanup_board()
	
	print("\n=== 3. 敵のアクションフェーズ ===")
	_enemy_action_phase()
	
	print("\n=== 4. ドローフェーズ ===")
	hand_manager.draw_new_hand(5, self)
	_update_deck_ui()
	_update_all_connections()
	print("ターン終了。次のターンが始まります。\n")

# --- 1. 効果解決とコンボ計算 ---
func _resolve_effects() -> void:
	var groups = _get_connected_groups()
	
	if groups.is_empty():
		battle_ui._show_damage_popup("0")
		return
		
	var display_text = ""
	var total_all_dmg = 0
	
	for i in range(groups.size()):
		var group = groups[i]
		var combo_count = group.size()
		
		# コンボ倍率の計算（2個で1.5倍、3個で2.0倍）
		var combo_multiplier = 1.0 + (combo_count - 1) * 0.5 
		
		var group_total_dmg = 0
		for p in group:
			var base_dmg = p.piece_data.effect_value
			var final_dmg = int(base_dmg * combo_multiplier)
			group_total_dmg += final_dmg
			
		total_all_dmg += group_total_dmg
		
		# 画面に表示する用のテキストを組み立てる
		display_text += "【" + str(combo_count) + "コンボ】 " + str(group_total_dmg) + "!\n"
	
	# 敵にダメージを与える
	current_enemy_hp -= total_all_dmg
	current_enemy_hp = max(0, current_enemy_hp) # 0以下にならないように
	_update_hp_ui()
	
	battle_ui.show_damage_popup(display_text)
	
	# 敵の死亡判定
	if current_enemy_hp <= 0:
		_stage_clear(true) # 勝利

# --- 2. 捨て札送り処理（以前のコードの切り出し） ---
func _cleanup_board() -> void:
	var all_pieces = get_tree().get_nodes_in_group("pieces")
	for p_node in all_pieces:
		if p_node.is_enemy or p_node.is_queued_for_deletion():
			continue
		
		p_node.reset_rotation_state()
			
		if p_node.board_pos.x != -1:
			grid_system.clear_piece_at(p_node.board_pos.x, p_node.board_pos.y)
			
		DeckManager.add_to_discard(p_node.piece_data)
		p_node.queue_free()
	
	hand_manager.hand_pieces.clear()

# --- 3. 敵の行動 ---
func _enemy_action_phase() -> void:
	# ★修正：current_enemy を使う
	if not current_enemy or current_enemy_hp <= 0:
		return
	
	var enemy = current_enemy
	_clear_enemy_pieces()

	var empty_cells = _get_empty_cells()
	if empty_cells.is_empty(): return

	# ★修正：action_pool を action_list に変更
	if enemy.action_list.is_empty():
		print("この敵はアクションを持っていません")
		return

	# ★修正：action_count を使う
	var spawn_count = enemy.action_count 
	empty_cells.shuffle()

	for i in range(min(spawn_count, empty_cells.size())):
		var target_cell = empty_cells[i]
		
		# ★修正：action_pool を action_list に変更
		var random_action = enemy.action_list.pick_random()
		
		_spawn_enemy_piece(target_cell, random_action)

# --- 古い敵ピースを掃除する関数 ---
func _clear_enemy_pieces() -> void:
	var all_pieces = get_tree().get_nodes_in_group("pieces")
	for p in all_pieces:
		if p.is_enemy:
			# 盤面データ(grid)から削除
			if p.board_pos.x != -1:
				grid_system.clear_piece_at(p.board_pos.x, p.board_pos.y)
			# シーンから削除
			p.queue_free()

# --- 空きマスリストを取得する関数 ---
func _get_empty_cells() -> Array:
	var cells = []
	for y in range(ROWS):
		for x in range(COLS):
			if grid_system.get_piece_at(x, y) == null: # ★変更
				cells.append(Vector2(x, y))
	return cells
	
# --- 敵ピースを1つ生成する関数 ---
func _spawn_enemy_piece(cell: Vector2, data: PieceData) -> void:
	var enemy_piece = PIECE_SCENE.instantiate() as PieceNode
	enemy_piece.piece_data = data
	enemy_piece.is_enemy = true
	enemy_piece.board_pos = cell
	enemy_piece.input_pickable = false # プレイヤーは動かせない
	
	add_child(enemy_piece)
	grid_system.grid[cell.y][cell.x] = enemy_piece
	

	# BOARD_OFFSET（盤面の左上）を基準に、Xマス目・Yマス目へ移動し、さらに半マス分(cell_size / 2.0)だけ右下にズラして中央に置く
	var snap_x = BOARD_OFFSET.x + (cell.x * CELL_SIZE) + (CELL_SIZE / 2.0)
	var snap_y = BOARD_OFFSET.y + (cell.y * CELL_SIZE) + (CELL_SIZE / 2.0)
	
	enemy_piece.global_position = Vector2(snap_x, snap_y)
	
	
	# 出現アニメーション
	enemy_piece.scale = Vector2.ZERO
	var tween = create_tween()
	tween.tween_property(enemy_piece, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _stage_clear(is_victory: bool):
	battle_ui.show_result(is_victory)

func _get_connected_groups() -> Array:
	var groups = []
	var visited = [] # すでにチェックしたピースのリスト
	var all_pieces = get_tree().get_nodes_in_group("pieces")
	
	# 盤面に置かれているプレイヤーのピースだけを集める
	var board_pieces = []
	for p in all_pieces:
		if not p.is_enemy and p.board_pos.x != -1 and not p.is_queued_for_deletion():
			board_pieces.append(p)
			
	# 幅優先探索（BFS）で繋がっているピースをグループ化する
	for piece in board_pieces:
		if piece in visited:
			continue # 既にどこかのグループに属しているならスキップ
			
		var current_group = []
		var queue = [piece]
		visited.append(piece)
		
		while queue.size() > 0:
			var current = queue.pop_front()
			current_group.append(current)
			
			# 他のすべての盤面ピースと比較し、隣接しているかチェック
			for other in board_pieces:
				if other in visited:
					continue
				
				# 上下左右に隣接しているか（マンハッタン距離が 1 かどうか）
				var dist = abs(current.board_pos.x - other.board_pos.x) + abs(current.board_pos.y - other.board_pos.y)
				if dist == 1:
					visited.append(other)
					queue.append(other)
					
		groups.append(current_group)
		
	return groups
	
func _reverse_array(arr: Array) -> Array:
	var new_arr = arr.duplicate()
	new_arr.reverse()
	return new_arr
