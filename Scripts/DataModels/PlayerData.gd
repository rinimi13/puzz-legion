extends Resource
class_name PlayerData

@export_category("基本情報")
@export var player_name: String = "プレイヤー"
@export var texture: Texture2D
@export var max_hp: int = 100

@export_category("初期設定")
@export var starting_deck: Array[PieceData] = []

@export_category("特殊能力")
# ※後々は専用の SkillData クラスなどを作るのがおすすめですが、今は仮でStringにしておきます
@export var passive_skills: Array[String] = [] 
@export var active_skills: Array[String] = []
