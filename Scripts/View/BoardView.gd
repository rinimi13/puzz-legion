# res://Scripts/BoardView.gd
extends Node2D

# BoardManagerの定数と同じ値を設定します
const ROWS: int = 6
const COLS: int = 10
const CELL_SIZE: float = 64.0

func _draw() -> void:
	# y軸（行）と x軸（列）のループでマス目を一つずつ描画します
	for y in range(ROWS):
		for x in range(COLS):
			# 描画する四角形の位置とサイズを計算
			var rect = Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
			
			# 1. マスの背景を半透明の黒で塗りつぶす (R, G, B, Alpha)
			draw_rect(rect, Color(0, 0, 0, 0.2), true)
			
			# 2. マスの枠線を白で描画する (色, 塗りつぶしフラグ[false], 線の太さ)
			draw_rect(rect, Color.WHITE, false, 2.0)
