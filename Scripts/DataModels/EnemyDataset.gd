extends Resource
class_name EnemyDataset

@export var enemy_name: String = "兵士"
@export var max_hp: int = 50
@export var base_attack: int = 5
@export var action_pool: Array[PieceData] = [] # この敵が使ってくるピースのリスト
