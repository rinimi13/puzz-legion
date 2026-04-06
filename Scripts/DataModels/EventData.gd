# res://Scripts/DataModels/EventData.gd
extends Resource
class_name EventData

# イベントの種類を定義
enum EventType {
	EMPTY,      # 0: 空白（通れないマス）
	START,      # 1: スタート地点
	BATTLE,     # 2: 通常戦闘
	ELITE,      # 3: エリート戦闘
	SHOP,       # 4: ショップ
	REST,       # 5: 休憩（回復など）
	BOSS        # 6: ボス戦闘
}

@export var event_type: EventType = EventType.BATTLE
@export var event_name: String = "通常戦闘"
@export var icon: Texture2D # マスに表示するアイコン画像
@export var enemy_data: EnemyData # バトルの場合、どの敵が出るかのデータ
