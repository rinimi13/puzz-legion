extends Resource
class_name EventData

enum EventType { BATTLE_NORMAL, BATTLE_ELITE, BATTLE_BOSS, REST, SHOP, RANDOM_EVENT }

@export var event_type: EventType = EventType.BATTLE_NORMAL

# 戦闘マスの場合、出現する敵の候補リスト
@export var possible_enemies: Array[EnemyData] = []
