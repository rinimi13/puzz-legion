# res://Scripts/EnemyPieceData.gd
extends PieceData
class_name EnemyPieceData

@export_category("敵専用ステータス")
# 敵専用の変数を定義
@export var enemy_hp: int = 10
@export var is_boss: bool = false
@export var drop_reward: int = 50
