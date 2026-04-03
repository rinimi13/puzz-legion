# res://Scripts/EnemyPlacement.gd
extends Resource
class_name EnemyPlacement

@export var grid_pos: Vector2i = Vector2i(9, 0) # 配置する座標 (x, y)
@export var enemy_data: EnemyPieceData          # 配置する敵のデータ
