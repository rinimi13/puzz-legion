# res://Scripts/DeckManager.gd
extends Node

# --- デッキデータ ---
var master_deck: Array[PieceData] = [] # 全体の所蔵ピース
var draw_pile: Array[PieceData] = []   # 山札
var discard_pile: Array[PieceData] = [] # 捨て札

var player_max_hp: int = 50
var player_current_hp: int = 50

# バトル開始：全カードを山札へ
func prepare_battle():
	draw_pile.clear()
	discard_pile.clear()
	# master_deckの中身をコピーして山札を作る
	for data in master_deck:
		draw_pile.append(data)
	draw_pile.shuffle()
	print("バトル開始。全枚数: ", draw_pile.size())

# ドロー処理（指示通りの順番に修正）
func draw_pieces(count: int) -> Array[PieceData]:
	var drawn_list: Array[PieceData] = []
	
	for i in range(count):
		# 1. 山札が空かチェック
		if draw_pile.is_empty():
			# 2. 山札が空なら、捨て札があるかチェック
			if discard_pile.is_empty():
				print("山札も捨て札も空です。これ以上引けません。")
				break # 両方空ならループ終了（5枚未満でもこれ以上引かない）
			
			# 3. 捨て札を山札に戻してシャッフル（リサイクル）
			_reshuffle_discard_into_draw()
		
		# 4. 山札から1枚取り出してリストに加える
		if not draw_pile.is_empty():
			drawn_list.append(draw_pile.pop_front())
	
	return drawn_list

func _reshuffle_discard_into_draw():
	print("山札が空になったので捨て札をリサイクルします。")
	draw_pile = discard_pile.duplicate()
	draw_pile.shuffle()
	discard_pile.clear()

# 捨て札に送る
func add_to_discard(piece: PieceData):
	if piece == null:
		return
	discard_pile.append(piece)
	# デバッグ用：枚数を確認
	# print("捨て札に追加されました。 現在の捨て札: ", discard_pile.size())
