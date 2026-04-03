# res://Scripts/Joint.gd
extends RefCounted
class_name Joint

# ジョイントの種類を定義
# FLAT: 平坦(0), CONVEX: 凸(1), CONCAVE: 凹(2)
enum Type { FLAT = 0, CONVEX = 1, CONCAVE = 2 }
