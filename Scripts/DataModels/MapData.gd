extends Resource
class_name MapData

@export_category("MAP生成ルール")
@export var stage_name: String = "第1階層"
@export var total_nodes: int = 15 # MAPの総マス数

@export_category("イベント出現確率（重み）")
@export var weight_battle_normal: float = 50.0
@export var weight_battle_elite: float = 10.0
@export var weight_shop: float = 15.0
@export var weight_rest: float = 10.0
@export var weight_random_event: float = 15.0

# ボスは必ず最後に配置されるため確率ではなく直接指定
@export var boss_data: EnemyData
