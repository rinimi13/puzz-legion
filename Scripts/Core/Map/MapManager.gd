# res://Scripts/Core/MapManager.gd
extends Node
class_name MapManager

const ROWS: int = 5  # マップの縦のマス数（レーン数）
const COLS: int = 12 # マップの横のマス数（進行度）

# マップの2次元配列（[y][x] の形で EventData を保持する）
var map_grid: Array = []

## ステージ1のマップをランダムに生成する処理
func generate_stage_1_map() -> void:
	map_grid.clear()
	
	# 2次元配列の初期化
	for y in range(ROWS):
		var row = []
		for x in range(COLS):
			row.append(null)
		map_grid.append(row)
		
	# マスにイベントを割り振っていく
	for x in range(COLS):
		for y in range(ROWS):
			var event = EventData.new()
			
			if x == 0:
				# 1列目は中央だけスタート地点、他は空白
				if y == int(ROWS / 2):
					event.event_type = EventData.EventType.START
					event.event_name = "START"
				else:
					event.event_type = EventData.EventType.EMPTY
					
			elif x == COLS - 1:
				# 最終列は中央だけボス、他は空白
				if y == int(ROWS / 2):
					event.event_type = EventData.EventType.BOSS
					event.event_name = "BOSS"
				else:
					event.event_type = EventData.EventType.EMPTY
					
			else:
				# 道中はランダム配置ルールの適用
				_apply_random_event_rules(event, x)
				
			map_grid[y][x] = event

## 道中のマスに確率でイベントを設定する処理
func _apply_random_event_rules(event: EventData, x: int) -> void:
	var roll = randf() # 0.0 ~ 1.0 のランダムな値
	
	# 前半（x が小さい）は敵が弱め・休憩多め、後半はエリートが出やすいなどの調整が可能
	if roll < 0.15:
		event.event_type = EventData.EventType.EMPTY
		event.event_name = "" # 所々穴あき（置けないマス）を作る
	elif roll < 0.60:
		event.event_type = EventData.EventType.BATTLE
		event.event_name = "BATTLE"
	elif roll < 0.75:
		event.event_type = EventData.EventType.REST
		event.event_name = "REST"
	elif roll < 0.90:
		event.event_type = EventData.EventType.SHOP
		event.event_name = "SHOP"
	else:
		event.event_type = EventData.EventType.ELITE
		event.event_name = "ELITE"
