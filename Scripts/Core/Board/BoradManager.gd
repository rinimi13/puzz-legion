# res://Scripts/Core/Board/BoradManager.gd
extends Node
class_name BoardManager

# ==========================================
# 1. 定数・変数の宣言
# ==========================================
const PIECE_SCENE = preload("res://Scenes/PieceNode.tscn")
const ROWS: int = 6
const COLS: int = 10
const CELL_SIZE: float = 64.0

@export var player_data: PlayerData
@export var current_enemy: EnemyData
@export var reward_pool: Array[PieceData]

@onready var board_guide: ColorRect = $BoardGuide
@onready var BOARD_OFFSET: Vector2 = board_guide.position
@onready var execute_button: Button = $UILayer/ExecuteButton
@onready var battle_ui: BattleUI = $UILayer

var grid_system: GridSystem
var hand_manager: HandManager
var is_processing_turn: bool = false

var current_enemy_hp: int = 0
var current_player_block: int = 0 
var next_turn_extra_draw: int = 0 # ★追加：次のターンの追加ドロー数


# ==========================================
# 2. 初期化・セットアップ
# ==========================================

## ゲーム開始時に呼ばれる初期化処理。
## 盤面や手札のシステムを準備し、UIのセットアップを行い、最初のターンを開始する。
func _ready() -> void:
	if board_guide: board_guide.visible = false
	
	# 専門家（システム）の召喚
	grid_system = GridSystem.new()
	add_child(grid_system)
	grid_system.initialize_grid()
	
	hand_manager = HandManager.new()
	add_child(hand_manager)
	hand_manager.piece_picked_up_signal.connect(_on_piece_picked_up)
	hand_manager.piece_dropped_signal.connect(_on_piece_dropped)
	
	# データの流し込み
	battle_ui.setup_portraits(player_data, current_enemy)
	
	if player_data:
		DeckManager.player_max_hp = player_data.max_hp
		DeckManager.player_current_hp = player_data.max_hp
		if DeckManager.master_deck.is_empty():
			DeckManager.master_deck = player_data.starting_deck.duplicate()
	
	if current_enemy:
		current_enemy_hp = current_enemy.max_hp
		
	# バトルの準備
	_update_hp_ui()
	DeckManager.prepare_battle()
	hand_manager.draw_new_hand(5, self)
	_enemy_action_phase()
	_update_deck_ui()


# ==========================================
# 3. ユーザー操作（シグナル受信）
# ==========================================

## プレイヤーが手札や盤面のピースを「掴んだ」瞬間に呼ばれる処理。
## 盤面に置かれていた場合は盤面から取り除き、接続エフェクトを更新する。
func _on_piece_picked_up(piece_node: PieceNode) -> void:
	var pos = piece_node.board_pos
	if pos.x != -1 and pos.y != -1:
		grid_system.clear_piece_at(pos.x, pos.y)
		piece_node.board_pos = Vector2i(-1, -1)
		_validate_board_pieces()
	_update_all_connections()

## プレイヤーがピースを「離した」瞬間に呼ばれる処理。
## ドロップされた座標が配置可能か判定し、成功すればマスに吸着させ、失敗すれば手札に戻す。
func _on_piece_dropped(piece_node: PieceNode, drop_pos: Vector2) -> void:
	var local_pos = drop_pos - BOARD_OFFSET
	var grid_x = int(local_pos.x / CELL_SIZE)
	var grid_y = int(local_pos.y / CELL_SIZE)
	
	if local_pos.x < 0 or local_pos.y < 0 or grid_x >= COLS or grid_y >= ROWS:
		hand_manager.handle_placement_failure(piece_node)
		_update_all_connections()
		return
	
	if grid_system.can_place_piece(piece_node.piece_data, grid_x, grid_y):
		grid_system.set_piece_at(grid_x, grid_y, piece_node.piece_data)
		piece_node.board_pos = Vector2i(grid_x, grid_y) 
		
		var snap_x = BOARD_OFFSET.x + (grid_x * CELL_SIZE) + (CELL_SIZE / 2.0)
		var snap_y = BOARD_OFFSET.y + (grid_y * CELL_SIZE) + (CELL_SIZE / 2.0)
		piece_node.global_position = Vector2(snap_x, snap_y)
		
		hand_manager.remove_from_hand(piece_node)
		_update_all_connections() 
	else:
		hand_manager.handle_placement_failure(piece_node)
		_update_all_connections()

## 「実行」ボタンが押された時に呼ばれる、ターンの進行を管理する処理。
## ダメージ計算 -> 盤面の掃除 -> 敵の行動 -> 新しい手札のドロー を順次実行する。
func _on_execute_button_pressed() -> void:
	if is_processing_turn: return
	is_processing_turn = true
	if execute_button: execute_button.disabled = true
	
	await _resolve_effects()
	
	if current_enemy_hp > 0:
		await _receive_enemy_damage()
	
	_cleanup_board()
	_enemy_action_phase()
	
	current_player_block = 0
	
	# 基本の5枚 ＋ 予約分をドローする
	var total_draw_count = 5 + next_turn_extra_draw
	hand_manager.draw_new_hand(total_draw_count, self)
	
	# ドローが終わったので予約をリセット
	next_turn_extra_draw = 0

	_update_hp_ui()
	_update_deck_ui()
	_update_all_connections()
	
	is_processing_turn = false
	if execute_button: execute_button.disabled = false

# 4. バトルの進行フェーズ（ゲームループ）
# ==========================================

## 盤面に配置されたピースからコンボを計算し、敵にダメージを与える処理。
## 繋がっている数に応じて倍率を上げ、最終的なダメージを UI に表示する。
# --- 1. 効果解決とコンボ計算 ---
func _resolve_effects() -> void:
	var groups = _get_connected_groups()
	
	if groups.is_empty():
		battle_ui.show_damage_popup("0")
		return
		
	var total_attack = 0
	var total_defend = 0
	var total_draw = 0
	var display_text = ""
	
	# ★設定スイッチ：敵に繋がっていない孤立グループを無効にするか？（true:無効になる / false:左上を起点に発動する）
	var require_enemy_connection: bool = true 
	
	for i in range(groups.size()):
		var group = groups[i]
		
		# 孤立チェック
		var has_enemy_connection = false
		var all_enemies = get_tree().get_nodes_in_group("pieces").filter(func(p): return p.is_enemy and p.board_pos.x != -1)
		for p in group:
			for enemy in all_enemies:
				if _count_active_joints_between(p, enemy) > 0:
					has_enemy_connection = true
					break
			if has_enemy_connection: break
			
		if require_enemy_connection and not has_enemy_connection:
			print("敵に繋がっていないため、このグループは不発に終わった！")
			continue
		
		# 敵に近い順（波紋状）にグループ内のピースを並び替える
		group = _sort_group_by_enemy_distance(group, all_enemies)
		
		var current_multiplier = 1.0
		var processed_pieces = []
		
		# 連鎖と倍率の計算
		for p in group:
			var new_joints_formed = 0
			
			# すでに処理した（自分より手前にある）ピースといくつのジョイントで合流したか
			for processed in processed_pieces:
				new_joints_formed += _count_active_joints_between(p, processed)
				
			# 倍率を計算する前に「適用前の倍率（開始倍率）」を記憶しておく
			var start_multiplier = current_multiplier
			
			# ジョイント合流ボーナス（二辺合流なら一気に+0.2倍）
			current_multiplier += (new_joints_formed * 0.1)
			
			var base_val = p.piece_data.effect_value
			var final_val = int(base_val * current_multiplier)
			
			# 効果タイプ別にアイコンを設定し、トータルダメージに加算
			var icon_text = "⚔️"
			if "effect_type" in p.piece_data:
				match p.piece_data.effect_type:
					0: # ATTACK（攻撃）
						total_attack += final_val
						icon_text = "⚔️"
					1: # DEFEND（防御）
						total_defend += final_val
						icon_text = "🛡️"
					2: # DRAW（ドロー）
						total_draw += final_val
						icon_text = "🃏"
			else:
				total_attack += final_val
				icon_text = "⚔️"
				
	
			# 「計算の元データ」をピースの演出関数に投げる
			await p.play_activation_effect(icon_text, base_val, start_multiplier, new_joints_formed)
			
			# 次のピースへ進む前に、波紋が流れるような短い余韻（0.1秒待つ）
			await get_tree().create_timer(0.1).timeout
						
			processed_pieces.append(p)
			
# --- 計算結果の適用とUI表示 ---
	if total_attack > 0:
		current_enemy_hp -= total_attack
		current_enemy_hp = max(0, current_enemy_hp)
		display_text += "⚔️ ダメージ: " + str(total_attack) + "\n"
		
	if total_defend > 0:
		# 防御力をストック
		current_player_block += total_defend 
		display_text += "🛡️ ブロック: " + str(total_defend) + "\n"
		
	if total_draw > 0:
		# 即座に引かず、予約変数に加算
		next_turn_extra_draw += total_draw 
		display_text += "🃏 次ターンドロー: +" + str(total_draw) + "\n"
			
	_update_hp_ui()
		
	if display_text != "":
		battle_ui.show_damage_popup(display_text.strip_edges())
	elif require_enemy_connection:
		battle_ui.show_damage_popup("MISS...") # 敵に繋がっていない時の表示
	
	if current_enemy_hp <= 0:
		_stage_clear(true)
		
# 補助処理：グループ内のピースを「敵からの距離」で並び替える関数
func _sort_group_by_enemy_distance(group: Array, all_enemies: Array) -> Array:
	var queue = []
	var distances = {} 
	
	for p in group:
		distances[p] = 999 # 初期値は無限遠
		for enemy in all_enemies:
			if _count_active_joints_between(p, enemy) > 0:
				distances[p] = 0
				queue.append(p)
				break
				
	# 敵に1つも繋がっていない場合は、左上を無理やり起点(0)にする
	if queue.is_empty():
		var top_left = group[0]
		for p in group:
			if p.board_pos.y < top_left.board_pos.y or (p.board_pos.y == top_left.board_pos.y and p.board_pos.x < top_left.board_pos.x):
				top_left = p
		distances[top_left] = 0
		queue.append(top_left)

	# 幅優先探索で距離を測る
	while queue.size() > 0:
		var current = queue.pop_front()
		var current_dist = distances[current]
		
		for other in group:
			if distances[other] > current_dist + 1:
				if _count_active_joints_between(current, other) > 0:
					distances[other] = current_dist + 1
					queue.append(other)

	var sorted_group = group.duplicate()
	sorted_group.sort_custom(func(a, b):
		if distances[a] != distances[b]:
			return distances[a] < distances[b] 
		if a.board_pos.y != b.board_pos.y:
			return a.board_pos.y < b.board_pos.y
		return a.board_pos.x < b.board_pos.x
	)
	
	return sorted_group

# 補助処理：2つのピース間で成功しているジョイント数を正確に数える関数
func _count_active_joints_between(p1: PieceNode, p2: PieceNode) -> int:
	var count = 0
	var dx = p2.board_pos.x - p1.board_pos.x
	var dy = p2.board_pos.y - p1.board_pos.y
	
	var data1 = p1.piece_data
	var data2 = p2.piece_data
	
	if dx == 1 and dy == 0:
		for i in range(3):
			if grid_system.is_interlocking(data1.right_joints[i], data2.left_joints[i]): count += 1
	elif dx == -1 and dy == 0:
		for i in range(3):
			if grid_system.is_interlocking(data1.left_joints[i], data2.right_joints[i]): count += 1
	elif dx == 0 and dy == 1:
		for i in range(3):
			if grid_system.is_interlocking(data1.bottom_joints[i], data2.top_joints[i]): count += 1
	elif dx == 0 and dy == -1:
		for i in range(3):
			if grid_system.is_interlocking(data1.top_joints[i], data2.bottom_joints[i]): count += 1
			
	return count
		
## ターンの終わりに、盤面に置かれたプレイヤーのピースを捨て札に送る処理。
## 手札に残っているピースもリセット（クリア）する。
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
	
	hand_manager.clear_hand()

## 敵が自分のアクション（ピース）を盤面に配置する処理。
## 空きマスをランダムに選び、敵のアクションリストから選ばれたピースを出現させる。
func _enemy_action_phase() -> void:
	if not current_enemy or current_enemy_hp <= 0: return
	
	var enemy = current_enemy
	_clear_enemy_pieces()

	var empty_cells = _get_empty_cells()
	if empty_cells.is_empty() or enemy.action_list.is_empty(): return

	var spawn_count = enemy.action_count 
	empty_cells.shuffle()

	for i in range(min(spawn_count, empty_cells.size())):
		var target_cell = empty_cells[i]
		var random_action = enemy.action_list.pick_random()
		_spawn_enemy_piece(target_cell, random_action)

## ゲームの勝敗が決まった時に呼ばれる処理。
## 実行ボタンを無効化し、勝利・敗北のリザルト画面を表示する。
func _stage_clear(is_victory: bool):
	battle_ui.show_result(is_victory)
	
	if is_victory:
		# 余韻
		await get_tree().create_timer(1.5).timeout
		
		# 報酬プールにカードが設定されていれば抽選を開始
		if reward_pool.size() > 0:
			var options = []
			var temp_pool = reward_pool.duplicate()
			temp_pool.shuffle() # プールをシャッフル
			
			# 最大3枚をランダムにピックアップ
			for i in range(min(3, temp_pool.size())):
				options.append(temp_pool[i])
				
			# UIに選択画面を出させ、プレイヤーが選ぶまで待機する
			battle_ui.show_reward_selection(options)
			var chosen_data = await battle_ui.reward_selected
			
			# マスターデッキにカードを追加
			DeckManager.master_deck.append(chosen_data)
			
			# 報酬を獲得した余韻を少し残して、マップ画面に戻る
			await get_tree().create_timer(1.0).timeout
			
			get_tree().change_scene_to_file("res://Scenes/MapScreen.tscn")

# ==========================================
# 5. 補助処理（ヘルパー関数）
# ==========================================
func _receive_enemy_damage() -> void:
	var total_enemy_damage = 0
	var all_pieces = get_tree().get_nodes_in_group("pieces")
	
	# 前のターンに敵が配置したピースのダメージを合計する
	for p in all_pieces:
		if p.is_enemy and p.board_pos.x != -1:
			total_enemy_damage += p.piece_data.effect_value
			
	if total_enemy_damage > 0:
		# ブロックで相殺を計算
		var blocked = min(total_enemy_damage, current_player_block)
		current_player_block -= blocked
		var final_damage = total_enemy_damage - blocked
		
		# ダメージを受ける
		DeckManager.player_current_hp -= final_damage
		DeckManager.player_current_hp = max(0, DeckManager.player_current_hp)
		
		_update_hp_ui()
		
		# 被弾のポップアップ演出
		var damage_text = "💥 敵の攻撃: " + str(total_enemy_damage)
		if blocked > 0:
			damage_text += " (ブロック: -" + str(blocked) + ")"
		if final_damage > 0:
			damage_text += "\n❤️ -" + str(final_damage)
		else:
			damage_text += "\n🛡️ NO DAMAGE!"
			
		battle_ui.show_damage_popup(damage_text)
		
		# テキストを見せるために少し待つ
		await get_tree().create_timer(1.2).timeout
		
		# ゲームオーバー判定
		if DeckManager.player_current_hp <= 0:
			_stage_clear(false)

# ==========================================
# 補助処理（ヘルパー関数）
# ==========================================

# ★引数に current_player_block を追加して UI に渡すよう修正！
func _update_hp_ui():
	var enemy_max = current_enemy.max_hp if current_enemy else 0
	battle_ui.update_hp_ui(DeckManager.player_current_hp, DeckManager.player_max_hp, current_player_block, current_enemy_hp, enemy_max)

## 山札と捨て札の最新の枚数を UI に反映させる処理。
func _update_deck_ui() -> void:
	battle_ui.update_deck_ui(DeckManager.draw_pile.size(), DeckManager.discard_pile.size())

## 盤面上のすべてのピースを確認し、ジョイント（凹凸）が正しく噛み合っている場合、
## その面を光らせるエフェクトのON/OFFを更新する処理。
func _update_all_connections() -> void:
	var all_pieces = get_tree().get_nodes_in_group("pieces")
	
	for piece in all_pieces:
		var pos = piece.board_pos
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

## 盤面で「正しく繋がっているプレイヤーのピース」をグループ分けして取得する処理。
## （例：3つ繋がっているグループが1つ、2つ繋がっているグループが1つ…など）
func _get_connected_groups() -> Array:
	var groups = []
	var visited = [] 
	var all_pieces = get_tree().get_nodes_in_group("pieces")
	
	var board_pieces = []
	for p in all_pieces:
		if not p.is_enemy and p.board_pos.x != -1 and not p.is_queued_for_deletion():
			board_pieces.append(p)
			
	for piece in board_pieces:
		if piece in visited:
			continue 
			
		var current_group = []
		var queue = [piece]
		visited.append(piece)
		
		while queue.size() > 0:
			var current = queue.pop_front()
			current_group.append(current)
			
			for other in board_pieces:
				if other in visited:
					continue
				
				var dist = abs(current.board_pos.x - other.board_pos.x) + abs(current.board_pos.y - other.board_pos.y)
				if dist == 1:
					visited.append(other)
					queue.append(other)
					
		groups.append(current_group)
		
	return groups

## 前のターンに敵が配置した「敵のピース」をすべて盤面から取り除き、削除する処理。
func _clear_enemy_pieces() -> void:
	var all_pieces = get_tree().get_nodes_in_group("pieces")
	for p in all_pieces:
		if p.is_enemy:
			if p.board_pos.x != -1:
				grid_system.clear_piece_at(p.board_pos.x, p.board_pos.y)
			p.queue_free()

## 盤面の中で、現在ピースが置かれていない「空きマス」の座標リストを取得する処理。
func _get_empty_cells() -> Array:
	var cells = []
	for y in range(ROWS):
		for x in range(COLS):
			if grid_system.get_piece_at(x, y) == null: 
				cells.append(Vector2(x, y))
	return cells

## 指定された空きマスに、敵のピースを生成して配置するアニメーション付きの処理。
func _spawn_enemy_piece(cell: Vector2, data: PieceData) -> void:
	var enemy_piece = PIECE_SCENE.instantiate() as PieceNode
	enemy_piece.piece_data = data
	enemy_piece.is_enemy = true
	enemy_piece.board_pos = cell
	enemy_piece.input_pickable = false 
	
	add_child(enemy_piece)
	grid_system.grid[cell.y][cell.x] = enemy_piece
	
	var snap_x = BOARD_OFFSET.x + (cell.x * CELL_SIZE) + (CELL_SIZE / 2.0)
	var snap_y = BOARD_OFFSET.y + (cell.y * CELL_SIZE) + (CELL_SIZE / 2.0)
	
	enemy_piece.global_position = Vector2(snap_x, snap_y)
	
	enemy_piece.scale = Vector2.ZERO
	var tween = create_tween()
	tween.tween_property(enemy_piece, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## 盤面にあるすべてのピースをチェックし、配置ルールを満たさなくなった
## （宙に浮いた）ピースをすべて手札に戻す連鎖処理。
func _validate_board_pieces() -> void:
	var changed = true
	# ピースが落ちることで別のピースが落ちる「連鎖」に対応するため、
	# 何も落ちなくなるまでループしてチェックし続けます。
	while changed:
		changed = false
		var all_pieces = get_tree().get_nodes_in_group("pieces")
		
		for p in all_pieces:
			# 敵ピースや、既に手札にいるピースは無視
			if p.is_enemy or p.board_pos.x == -1 or p.is_queued_for_deletion():
				continue
				
			var px = p.board_pos.x
			var py = p.board_pos.y
			
			# 一時的に盤面から消して「今この状態でここにおけるか？」を再判定
			grid_system.clear_piece_at(px, py)
			var is_valid = grid_system.can_place_piece(p.piece_data, px, py)
			
			if is_valid:
				# どこかに繋がっていて問題ないので、盤面に戻す
				grid_system.set_piece_at(px, py, p.piece_data)
			else:
				# どこにも繋がっていない孤立状態なので手札に戻す！
				hand_manager.handle_placement_failure(p)
				changed = true # 盤面が変化したのでもう1回全体をチェックさせる
