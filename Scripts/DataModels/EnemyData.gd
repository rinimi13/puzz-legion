extends Resource
class_name EnemyData

enum EnemyType { NORMAL, ELITE, BOSS }

@export_category("基本ステータス")
@export var enemy_name: String = "騎士"
@export var texture: Texture2D
@export var max_hp: int = 50
@export var enemy_type: EnemyType = EnemyType.NORMAL

@export_category("ドロップ報酬")
@export var reward_drop_rate: float = 1.0 # 1.0 = 100%
@export var reward_money: int = 15

@export_category("行動パターン")
@export var action_list: Array[PieceData] = [] # この敵が使ってくるピース群
@export var action_count: int = 1 # 1ターンに盤面に出すピースの数
@export var action_weights: Array[float] = [] # 各アクションの選ばれやすさ（確率）
