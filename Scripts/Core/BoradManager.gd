# res://Scripts/BoardManager.gd
extends Node
class_name BoardManager

const ROWS: int = 6
const COLS: int = 10

const CELL_SIZE: float = 64.0
@onready var board_guide: ColorRect = $BoardGuide # ※パスは実際のツリーに合わせてください
@onready var BOARD_OFFSET: Vector2 = board_guide.position

var grid: Array = []

const PIECE_SCENE = preload("res://Scenes/PieceNode.tscn")

const HAND_START_POS: Vector2 = Vector2(200, 500) # 手札の左端の座標
const HAND_SPACING: float = 100.0 # ピース同士の間隔

var hand_pieces: Array = []
var current_view_type: String = ""

@export var current_stage: StageData
@export var starting_deck: Array[PieceData] = []

@onready var draw_count_label: Label = $UILayer/DeckUI/DrawCountLabel
@onready var discard_count_label: Label = $UILayer/DeckUI/DiscardCountLabel
@onready var deck_view_panel: Panel = $UILayer/DeckUI/DeckViewPanel
@onready var item_list: VBoxContainer = $UILayer/DeckUI/DeckViewPanel/ScrollContainer/ItemList

@onready var view_draw_button: Button = $UILayer/DeckUI/ViewDrawButton
@onready var view_discard_button: Button = $UILayer/DeckUI/ViewDiscardButton

@onready var dim_overlay: ColorRect = $UILayer/DeckUI/DimOverlay
@onready var damage_label: Label = $UILayer/DamageLabel

@onready var player_hp_bar: ProgressBar = $UILayer/PlayerHPBar
@onready var enemy_hp_bar: ProgressBar = $UILayer/EnemyHPBar

@onready var player_hp_text: Label = $UILayer/PlayerHPBar/PlayerHPText
@onready var enemy_hp_text: Label = $UILayer/EnemyHPBar/EnemyHPText

@onready var result_overlay: ColorRect = $UILayer/ResultOverlay
@onready var result_label: Label = $UILayer/ResultOverlay/ResultLabel

@onready var execute_button: Button = $UILayer/ExecuteButton
@onready var enemy_dataset = preload("res://Resources/Enemies/enemy1.tres") 

var current_enemy_hp: int = 0

func _ready() -> void:
	if damage_label:
		damage_label.modulate.a = 0.0
	
	if board_guide: board_guide.visible = false
	
	_initialize_grid()
	
	# 初回起動なら初期デッキをマスター登録
	if DeckManager.master_deck.is_empty():
		DeckManager.master_deck = starting_deck.duplicate()
	
	if current_stage and current_stage.enemy_info:
		var enemy = current_stage.enemy_info
		current_enemy_hp = enemy.max_hp
		# ステージの敵HPバーなどの最大値を更新
		enemy_hp_bar.max_value = enemy.max_hp
		
	_update_hp_ui()
	
	# バトル開始の準備（山札作成・シャッフル）
	DeckManager.prepare_battle()

	if view_draw_button and not view_draw_button.pressed.is_connected(_on_view_draw_button_pressed):
		view_draw_button.pressed.connect(_on_view_draw_button_pressed)
		
	if view_discard_button and not view_discard_button.pressed.is_connected(_on_view_discard_button_pressed):
		view_discard_button.pressed.connect(_on_view_discard_button_pressed)	
	
	# 最初の5枚をドロー
	draw_new_hand(5)
	
	_enemy_action_phase()
	_update_deck_ui()

func _update_hp_ui():
	# --- プレイヤー側のUI更新 ---
	player_hp_bar.max_value = DeckManager.player_max_hp
	player_hp_bar.value = DeckManager.player_current_hp
	
	# ★追加：文字を「今のHP / 最大HP」の形にする
	player_hp_text.text = str(DeckManager.player_current_hp) + " / " + str(DeckManager.player_max_hp)
	
	# --- 敵側のUI更新 ---
	# ステージデータと、そのステージの敵情報がちゃんと設定されているか確認
	if current_stage and current_stage.enemy_info:
		# ★修正：EnemyData（敵情報）の中にある max_hp を見るように変更！
		var enemy_max = current_stage.enemy_info.max_hp
		
		if enemy_hp_bar and enemy_hp_text:
			enemy_hp_bar.max_value = enemy_max
			enemy_hp_bar.value = current_enemy_hp
			
			# 文字を「今のHP / 最大HP」の形にする
			enemy_hp_text.text = str(current_enemy_hp) + " / " + str(enemy_max)

func _update_deck_ui() -> void:
	draw_count_label.text = "山札: " + str(DeckManager.draw_pile.size())
	discard_count_label.text = "捨て札: " + str(DeckManager.discard_pile.size())

# ★新しく追加：ドローして手札として画面に生成する関数
func draw_new_hand(count: int):
	var new_data_list = DeckManager.draw_pieces(count)
	
	for data in new_data_list:
		var piece_node = PIECE_SCENE.instantiate() as PieceNode
		piece_node.piece_data = data
		piece_node.input_pickable = true
		piece_node.is_enemy = false
		
		add_child(piece_node)
		piece_node.add_to_group("pieces")
		hand_pieces.append(piece_node)
		
		piece_node.piece_dropped.connect(_on_piece_dropped)
		piece_node.piece_picked_up.connect(_on_piece_picked_up)
			
	_arrange_hand()
	_update_deck_ui()
	
func _initialize_grid() -> void:
	# 1. まず古い盤面データを空にする
	grid.clear()
	
	# 2. ROWS(縦) × COLS(横) のマス目を作り、すべて null（空きマス）で埋める
	for y in range(ROWS):
		var row: Array = []
		for x in range(COLS):
			row.append(null)
		grid.append(row)
	
	# ステージデータがセットされていなければ警告を出す
	if current_stage == null:
		push_error("エラー：インスペクターに current_stage がセットされていません！")
		return	
	
# ジョイントの照合を行う関数（my_joints: 自分の辺, neighbor_joints: 相手の辺）
func check_match(my_joints: Array, neighbor_joints: Array) -> bool:
	for i in range(3):
		var me: int = my_joints[i]
		var neighbor: int = neighbor_joints[i]
		
		# 自分が凸(CONVEX)の場合、相手は絶対に凹(CONCAVE)でなければならない
		if me == Joint.Type.CONVEX and neighbor != Joint.Type.CONCAVE:
			return false
			
		# 相手が凸(CONVEX)の場合、自分は絶対に凹(CONCAVE)でなければならない
		if neighbor == Joint.Type.CONVEX and me != Joint.Type.CONCAVE:
			return false
			
		# 上記の「凸が刺さらないエラー」をパスすれば接続OK。
		# （平坦vs平坦、凹vs凹、凹vs平坦 などはすべて許容される）
		
	return true # 3つのジョイント全てで問題がなければTrueを返す
	
	
# ピースが指定座標 (x, y) に配置可能か判定する関数
func can_place_piece(piece: PieceData, x: int, y: int) -> bool:
	# 1. 基本チェック（盤面外、既に埋まっている）
	if x < 0 or x >= COLS or y < 0 or y >= ROWS:
		return false
	if grid[y][x] != null:
		return false
	
	# ★ 今回追加するフラグ：接続が1つ以上成立しているか
	var has_valid_connection: bool = false
	
	# 2. 四方のチェック
	var p_data = piece
	
# --- 右隣 ---
	if x + 1 < COLS and grid[y][x + 1] != null:
		var neighbor = grid[y][x + 1]
		var n_data = neighbor.piece_data if (neighbor is Node) else neighbor
		
		if not check_match(p_data.right_joints, n_data.left_joints):
			return false
		if _has_any_interlock(p_data.right_joints, n_data.left_joints):
			has_valid_connection = true
			
	# --- 左隣 ---
	if x - 1 >= 0 and grid[y][x - 1] != null:
		var neighbor = grid[y][x - 1]
		var n_data = neighbor.piece_data if (neighbor is Node) else neighbor
		
		if not check_match(p_data.left_joints, n_data.right_joints):
			return false
		if _has_any_interlock(p_data.left_joints, n_data.right_joints):
			has_valid_connection = true

	# --- 下隣 ---
	if y + 1 < ROWS and grid[y + 1][x] != null:
		var neighbor = grid[y + 1][x]
		var n_data = neighbor.piece_data if (neighbor is Node) else neighbor
		
		if not check_match(p_data.bottom_joints, n_data.top_joints):
			return false
		if _has_any_interlock(p_data.bottom_joints, n_data.top_joints):
			has_valid_connection = true

	# --- 上隣 ---
	if y - 1 >= 0 and grid[y - 1][x] != null:
		var neighbor = grid[y - 1][x]
		var n_data = neighbor.piece_data if (neighbor is Node) else neighbor
		
		if not check_match(p_data.top_joints, n_data.bottom_joints):
			return false
		if _has_any_interlock(p_data.top_joints, n_data.bottom_joints):
			has_valid_connection = true

	if not has_valid_connection:
		print("配置失敗：どこにも接続していません！")
		return false
				
	return true

# ★ 補助関数：噛み合っているジョイントが1つでもあるか判定
func _has_any_interlock(my_side: Array, neighbor_side: Array) -> bool:
	for i in range(3):
		if _is_interlocking(my_side[i], neighbor_side[i]):
			return true
	return false
		
func _on_piece_picked_up(piece_node: PieceNode) -> void:
	var pos = piece_node.board_pos
	if pos.x != -1 and pos.y != -1:
		grid[pos.y][pos.x] = null
	
	_update_all_connections() # ★追加：持ち上げられたので接続状態を再計算

func _on_piece_dropped(piece_node: PieceNode, drop_pos: Vector2) -> void:
	var local_pos = drop_pos - BOARD_OFFSET
	var grid_x = int(local_pos.x / CELL_SIZE)
	var grid_y = int(local_pos.y / CELL_SIZE)
	
	# 盤面外にドロップされた場合 -> 失敗処理へ（手札に戻る）
	if local_pos.x < 0 or local_pos.y < 0 or grid_x >= COLS or grid_y >= ROWS:
		_handle_placement_failure(piece_node)
		return
	
	if can_place_piece(piece_node.piece_data, grid_x, grid_y):
		# 【成功】盤面に配置
		grid[grid_y][grid_x] = piece_node.piece_data
		piece_node.board_pos = Vector2i(grid_x, grid_y) 
		
		var snap_x = BOARD_OFFSET.x + (grid_x * CELL_SIZE) + (CELL_SIZE / 2.0)
		var snap_y = BOARD_OFFSET.y + (grid_y * CELL_SIZE) + (CELL_SIZE / 2.0)
		piece_node.global_position = Vector2(snap_x, snap_y)
		
		# ★追加：手札リストにこのピースが含まれていたら削除し、手札を詰め直す
		if hand_pieces.has(piece_node):
			hand_pieces.erase(piece_node)
			_arrange_hand()
			
		print("配置成功！ [", grid_x, ", ", grid_y, "]")
		_update_all_connections() 
	else:
		# 【失敗】ルール違反
		print("配置失敗！ ジョイントが合いません。")
		_handle_placement_failure(piece_node)

func _handle_placement_failure(piece_node: PieceNode) -> void:
	# 1. 盤面の座標記憶をリセット（手札状態にする）
	piece_node.board_pos = Vector2i(-1, -1)
	
	# 2. 手札リストにまだ入っていない場合は追加する
	if not hand_pieces.has(piece_node):
		hand_pieces.append(piece_node)
	
	# 3. 手札を並べ直し、ピースを適切な位置へ移動させる
	_arrange_hand()
	
	# 4. 接続状態（光る演出）を再計算
	_update_all_connections()
	
	print(piece_node.piece_data.piece_name, " が手札に戻りました。")
	
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
		
		# --- 右隣(x+1)とのチェック ---
		if pos.x + 1 < COLS and grid[pos.y][pos.x + 1] != null:
			var neighbor = grid[pos.y][pos.x + 1]
			var n_data = neighbor.piece_data if (neighbor is Node) else neighbor
			for i in range(3):
				if _is_interlocking(my_data.right_joints[i], n_data.left_joints[i]):
					c_right[i] = true
						
		# --- 左隣(x-1)とのチェック ---
		if pos.x - 1 >= 0 and grid[pos.y][pos.x - 1] != null:
			var neighbor = grid[pos.y][pos.x - 1]
			var n_data = neighbor.piece_data if (neighbor is Node) else neighbor
			for i in range(3):
				if _is_interlocking(my_data.left_joints[i], n_data.right_joints[i]):
					c_left[i] = true
						
		# --- 下隣(y+1)とのチェック ---
		if pos.y + 1 < ROWS and grid[pos.y + 1][pos.x] != null:
			var neighbor = grid[pos.y + 1][pos.x]
			var n_data = neighbor.piece_data if (neighbor is Node) else neighbor
			for i in range(3):
				if _is_interlocking(my_data.bottom_joints[i], n_data.top_joints[i]):
					c_bottom[i] = true
						
		# --- 上隣(y-1)とのチェック ---
		if pos.y - 1 >= 0 and grid[pos.y - 1][pos.x] != null:
			var neighbor = grid[pos.y - 1][pos.x]
			var n_data = neighbor.piece_data if (neighbor is Node) else neighbor
			for i in range(3):
				if _is_interlocking(my_data.top_joints[i], n_data.bottom_joints[i]):
					c_top[i] = true
						
		piece.set_connections(c_top, c_bottom, c_left, c_right)
				
# ★追加：凸と凹が正しく噛み合っているか判定する補助関数
func _is_interlocking(joint_a: int, joint_b: int) -> bool:
	if joint_a == Joint.Type.CONVEX and joint_b == Joint.Type.CONCAVE: return true
	if joint_a == Joint.Type.CONCAVE and joint_b == Joint.Type.CONVEX: return true
	return false


# 実行ボタンが押された時の処理
func _on_execute_button_pressed() -> void:
	print("\n=== 1. 効果解決フェーズ ===")
	_resolve_effects()
	
	print("\n=== 2. クリーンアップ ===")
	_cleanup_board()
	
	print("\n=== 3. 敵のアクションフェーズ ===")
	_enemy_action_phase()
	
	print("\n=== 4. ドローフェーズ ===")
	draw_new_hand(5)
	_update_deck_ui()
	_update_all_connections()
	print("ターン終了。次のターンが始まります。\n")

# --- 1. 効果解決とコンボ計算 ---
func _resolve_effects() -> void:
	var groups = _get_connected_groups()
	
	if groups.is_empty():
		_show_damage_popup("0")
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
			var base_dmg = p.piece_data.attack_power
			var final_dmg = int(base_dmg * combo_multiplier)
			group_total_dmg += final_dmg
			
		total_all_dmg += group_total_dmg
		
		# 画面に表示する用のテキストを組み立てる
		display_text += "【" + str(combo_count) + "コンボ】 " + str(group_total_dmg) + "!\n"
	
	# 敵にダメージを与える
	current_enemy_hp -= total_all_dmg
	current_enemy_hp = max(0, current_enemy_hp) # 0以下にならないように
	_update_hp_ui()
	
	# 組み立てたテキストを画面にアニメーション表示！
	_show_damage_popup(display_text)
	
	# 敵の死亡判定
	if current_enemy_hp <= 0:
		_stage_clear(true) # 勝利

# ==========================================
# ★新規追加：文字をアニメーションで表示する関数
# ==========================================
func _show_damage_popup(text: String) -> void:
	if not damage_label:
		return
		
	damage_label.text = text
	
	# アニメーションを作るための「Tween（トゥイーン）」を作成
	var tween = create_tween()
	
	# 1. 最初に文字を完全に表示（透明度を1.0に）し、少し大きく(1.5倍)する
	damage_label.modulate.a = 1.0
	damage_label.scale = Vector2(1.5, 1.5)
	
	# 2. ボヨーンと元のサイズ(1.0)に戻るアニメーション（0.3秒かける）
	tween.tween_property(damage_label, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	# 3. そのまま 1.0秒 待機する
	tween.tween_interval(1.0)
	
	# 4. スーッと透明になって消えるアニメーション（0.5秒かける）
	tween.tween_property(damage_label, "modulate:a", 0.0, 0.5)


# --- 2. 捨て札送り処理（以前のコードの切り出し） ---
func _cleanup_board() -> void:
	var all_pieces = get_tree().get_nodes_in_group("pieces")
	for p_node in all_pieces:
		if p_node.is_enemy or p_node.is_queued_for_deletion():
			continue
		
		p_node.reset_rotation_state()
			
		if p_node.board_pos.x != -1:
			grid[p_node.board_pos.y][p_node.board_pos.x] = null
			
		DeckManager.add_to_discard(p_node.piece_data)
		p_node.queue_free()
	
	hand_pieces.clear()

# --- 3. 敵の行動 ---
func _enemy_action_phase() -> void:
	# 1. 敵情報がない、または既に倒しているなら何もしない
	if not current_stage.enemy_info or current_enemy_hp <= 0:
		return
	
	var enemy = current_stage.enemy_info
	_clear_enemy_pieces() # 前のターンの敵ピースを消す

	var empty_cells = _get_empty_cells()
	if empty_cells.is_empty(): return

	# 2. 敵が持つアクションプールから抽選
	if enemy.action_pool.is_empty():
		print("この敵はアクションを持っていません")
		return

	# 例：敵が一度に配置する数（敵のステータスに持たせてもOK）
	var spawn_count = 1 
	empty_cells.shuffle()

	for i in range(min(spawn_count, empty_cells.size())):
		var target_cell = empty_cells[i]
		
		# ★ここがポイント：その敵専用のアクションプールから選ぶ
		var random_action = enemy.action_pool.pick_random()
		
		_spawn_enemy_piece(target_cell, random_action)

# --- 古い敵ピースを掃除する関数 ---
func _clear_enemy_pieces() -> void:
	var all_pieces = get_tree().get_nodes_in_group("pieces")
	for p in all_pieces:
		if p.is_enemy:
			# 盤面データ(grid)から削除
			if p.board_pos.x != -1:
				grid[p.board_pos.y][p.board_pos.x] = null
			# シーンから削除
			p.queue_free()

# --- 空きマスリストを取得する関数 ---
func _get_empty_cells() -> Array:
	var cells = []
	for y in range(grid.size()):
		for x in range(grid[y].size()):
			if grid[y][x] == null:
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
	grid[cell.y][cell.x] = enemy_piece
	

	# BOARD_OFFSET（盤面の左上）を基準に、Xマス目・Yマス目へ移動し、さらに半マス分(cell_size / 2.0)だけ右下にズラして中央に置く
	var snap_x = BOARD_OFFSET.x + (cell.x * CELL_SIZE) + (CELL_SIZE / 2.0)
	var snap_y = BOARD_OFFSET.y + (cell.y * CELL_SIZE) + (CELL_SIZE / 2.0)
	
	enemy_piece.global_position = Vector2(snap_x, snap_y)
	
	
	# 出現アニメーション
	enemy_piece.scale = Vector2.ZERO
	var tween = create_tween()
	tween.tween_property(enemy_piece, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# ステージ終了（勝敗）
func _stage_clear(is_victory: bool):
	# 実行ボタンを押せなくして、ゲームの進行を止める
	if execute_button:
		execute_button.disabled = true
	
	if is_victory:
		# 勝利時の表示
		result_label.text = "GAME CLEAR!"
		result_label.add_theme_color_override("font_color", Color(1, 1, 0)) # 文字色を黄色に
		print("★★★ ステージクリア！ ★★★")
	else:
		# 敗北時の表示
		result_label.text = "GAME OVER..."
		result_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2)) # 文字色を赤色に
		print("††† ゲームオーバー †††")
		
	# リザルト画面のフィルターと文字を表示する
	result_overlay.visible = true
	
	# ※少しフワッと表示させたい場合は、Tweenを使うこともできます
	result_overlay.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(result_overlay, "modulate:a", 1.0, 1.0)

# ★追加：手札にあるピースを綺麗に並べ直す関数
func _arrange_hand() -> void:
	for i in range(hand_pieces.size()):
		var piece = hand_pieces[i]
		# 盤面座標をリセット（手札にいる証拠）
		piece.board_pos = Vector2i(-1, -1)
		
		# 左から順に間隔を空けて配置する目標座標を計算
		var target_pos = HAND_START_POS + Vector2(i * HAND_SPACING, 0)
		
		# 位置を更新する（アニメーションさせるとより良いですが今回は瞬間移動）
		piece.global_position = target_pos
		# original_position も更新しておく（掴んで離した時用）
		piece.original_position = target_pos

# --- 山札を見るボタン ---
func _on_view_draw_button_pressed() -> void:
	if deck_view_panel.visible and current_view_type == "draw":
		_close_deck_view() # 閉じる
	else:
		current_view_type = "draw"
		_show_deck_view("【山札の中身】", DeckManager.draw_pile)

# --- 捨て札を見るボタン ---
func _on_view_discard_button_pressed() -> void:
	if deck_view_panel.visible and current_view_type == "discard":
		_close_deck_view() # 閉じる
	else:
		current_view_type = "discard"
		_show_deck_view("【捨て札の中身】", DeckManager.discard_pile)

# --- ★名前変更：パネルを閉じる共通処理 ---
func _close_deck_view() -> void:
	deck_view_panel.visible = false
	dim_overlay.visible = false
	current_view_type = ""

# --- 中身をリストに並べてパネルを表示する共通処理 ---
# res://Scripts/BoardManager.gd (_show_deck_view関数をまるごと上書き)

func _show_deck_view(title_text: String, pile: Array) -> void:
	# 前のリストを消去
	for child in item_list.get_children():
		child.queue_free()
	
	# ==========================================
	# ★追加1：開始位置を下にずらすための「透明な空白（スペーサー）」
	# ==========================================
	var top_spacer = Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 40) # 40の部分を増やすとさらに下がります
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
			
			var piece_node = PIECE_SCENE.instantiate() as PieceNode
			piece_node.piece_data = data
			piece_node.input_pickable = false 
			piece_node.position = Vector2(40, 40)
			
			if piece_node.is_in_group("pieces"):
				piece_node.remove_from_group("pieces")
			
			piece_space.add_child(piece_node)
			grid.add_child(piece_space)
			
			piece_node.info_ui.visible = false
			
			# ==========================================
			# ★追加2：UIがパネルの枠で切り取られないようにする魔法の設定
			# ==========================================
			piece_node.info_ui.top_level = true
			
			piece_space.mouse_entered.connect(func():
				piece_node.info_ui.visible = true
				piece_node.z_index = 100
				
				# top_level=trueにすると親の座標を無視して画面の左上(0,0)に飛んでしまうため、
				# ピースの現在の画面上の位置(global_position)を基準に表示位置を強制的に合わせます。
				# ※もしUIの出る位置がピースと被って見づらい場合は、ここの Vector2 の数値をいじって調整してください！
				piece_node.info_ui.global_position = piece_node.global_position + Vector2(20, -20)
			)
			piece_space.mouse_exited.connect(func():
				piece_node.info_ui.visible = false
				piece_node.z_index = 0
			)
			
	# ==========================================
	# ★追加3：一番下にも空白を入れて、下端のピースにUIを出すスペースを作る
	# ==========================================
	var bottom_spacer = Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, 60)
	item_list.add_child(bottom_spacer)
	
	dim_overlay.visible = true
	deck_view_panel.visible = true

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
