# res://Scripts/PieceData.gd
extends Resource
class_name PieceData

@export_category("基本ステータス")
@export var piece_name: String = "名無しピース"
@export var character_texture: Texture2D
@export var attack_power: int = 0
@export var has_immediate_effect: bool = false
@export var is_end_piece: bool = false

@export_category("ジョイント設定（各辺3つ）")
@export var top_joints: Array[Joint.Type] = [Joint.Type.FLAT, Joint.Type.FLAT, Joint.Type.FLAT]
@export var bottom_joints: Array[Joint.Type] = [Joint.Type.FLAT, Joint.Type.FLAT, Joint.Type.FLAT]
@export var left_joints: Array[Joint.Type] = [Joint.Type.FLAT, Joint.Type.FLAT, Joint.Type.FLAT]
@export var right_joints: Array[Joint.Type] = [Joint.Type.FLAT, Joint.Type.FLAT, Joint.Type.FLAT]
