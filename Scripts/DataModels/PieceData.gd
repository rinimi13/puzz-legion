# res://Scripts/DataModels/PieceData.gd
extends Resource
class_name PieceData

# ★追加：誰が使うピースなのかの判別用
enum OwnerType { PLAYER_ONLY, ENEMY_ONLY, BOTH }
enum EffectType { ATTACK, DEFENSE, BUFF, DEBUFF, HEAL, DRAW, MOVE, CHANGE_JOINT }

@export_category("基本情報")
@export var piece_name: String = "名無しピース"
@export var texture: Texture2D
@export var owner_type: OwnerType = OwnerType.PLAYER_ONLY # ★追加：インスペクタで切り替え可能

@export_category("効果とアクション")
@export var effect_type: EffectType = EffectType.ATTACK
@export var effect_value: int = 0
@export var placement_bonus: String = "" 
@export var placement_restriction: String = "" 

@export_category("ジョイント設定")
@export var top_joints: Array[Joint.Type] = [Joint.Type.FLAT, Joint.Type.FLAT, Joint.Type.FLAT]
@export var bottom_joints: Array[Joint.Type] = [Joint.Type.FLAT, Joint.Type.FLAT, Joint.Type.FLAT]
@export var left_joints: Array[Joint.Type] = [Joint.Type.FLAT, Joint.Type.FLAT, Joint.Type.FLAT]
@export var right_joints: Array[Joint.Type] = [Joint.Type.FLAT, Joint.Type.FLAT, Joint.Type.FLAT]
