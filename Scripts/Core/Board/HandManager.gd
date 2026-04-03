# res://Scripts/Core/HandManager.gd
extends Node
class_name HandManager

const PIECE_SCENE = preload("res://Scenes/PieceNode.tscn")
const HAND_START_POS: Vector2 = Vector2(200, 500) # 手札の左端
const HAND_SPACING: float = 100.0 # ピースの間隔

var hand_pieces: Array = []

# BoardManagerに報告するためのシグナル
signal piece_picked_up_signal(piece_node)
signal piece_dropped_signal(piece_node, drop_pos)

# ピースをドローして画面に出す
func draw_new_hand(count: int, parent_node: Node) -> void:
	var new_data_list = DeckManager.draw_pieces(count)
	
	for data in new_data_list:
		var piece_node = PIECE_SCENE.instantiate() as PieceNode
		piece_node.piece_data = data
		piece_node.input_pickable = true
		piece_node.is_enemy = false
		
		# BoardManagerの子として画面に追加
		parent_node.add_child(piece_node)
		piece_node.add_to_group("pieces")
		hand_pieces.append(piece_node)
		
		# ピースからの報告をHandManagerが受け取る
		piece_node.piece_dropped.connect(_on_piece_dropped)
		piece_node.piece_picked_up.connect(_on_piece_picked_up)
			
	arrange_hand()

# 手札を綺麗に並べる
func arrange_hand() -> void:
	for i in range(hand_pieces.size()):
		var piece = hand_pieces[i]
		piece.board_pos = Vector2i(-1, -1)
		var target_pos = HAND_START_POS + Vector2(i * HAND_SPACING, 0)
		piece.global_position = target_pos
		piece.original_position = target_pos

# 配置に失敗したピースを手札に戻す
func handle_placement_failure(piece_node: PieceNode) -> void:
	piece_node.board_pos = Vector2i(-1, -1)
	if not hand_pieces.has(piece_node):
		hand_pieces.append(piece_node)
	arrange_hand()
	print(piece_node.piece_data.piece_name, " が手札に戻りました。")

# 盤面に置かれたピースを手札リストから消す
func remove_from_hand(piece_node: PieceNode) -> void:
	if hand_pieces.has(piece_node):
		hand_pieces.erase(piece_node)
		arrange_hand()

# ターン終了時に手札リストを空にする
func clear_hand() -> void:
	hand_pieces.clear()

# --- ピースからの報告を流す処理 ---
func _on_piece_picked_up(piece_node: PieceNode) -> void:
	piece_picked_up_signal.emit(piece_node)

func _on_piece_dropped(piece_node: PieceNode, drop_pos: Vector2) -> void:
	piece_dropped_signal.emit(piece_node, drop_pos)
