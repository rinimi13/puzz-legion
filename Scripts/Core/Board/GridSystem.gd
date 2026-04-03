# res://Scripts/Core/GridSystem.gd
extends Node
class_name GridSystem

const ROWS: int = 6
const COLS: int = 10

var grid: Array = []

func initialize_grid() -> void:
	grid.clear()
	for y in range(ROWS):
		var row: Array = []
		for x in range(COLS):
			row.append(null)
		grid.append(row)

func get_piece_at(x: int, y: int):
	if x < 0 or x >= COLS or y < 0 or y >= ROWS:
		return null
	return grid[y][x]

func set_piece_at(x: int, y: int, piece_data: PieceData) -> void:
	if x >= 0 and x < COLS and y >= 0 and y < ROWS:
		grid[y][x] = piece_data

func clear_piece_at(x: int, y: int) -> void:
	if x >= 0 and x < COLS and y >= 0 and y < ROWS:
		grid[y][x] = null

# ピースの配置確認
func can_place_piece(piece: PieceData, x: int, y: int) -> bool:
	if x < 0 or x >= COLS or y < 0 or y >= ROWS:
		return false
	if grid[y][x] != null:
		return false
	
	var has_valid_connection: bool = false
	var p_data = piece
	
	# 右隣
	if get_piece_at(x + 1, y) != null:
		var n_data = _get_data_from_cell(x + 1, y)
		if not check_match(p_data.right_joints, n_data.left_joints): return false
		if _has_any_interlock(p_data.right_joints, n_data.left_joints): has_valid_connection = true
	# 左隣
	if get_piece_at(x - 1, y) != null:
		var n_data = _get_data_from_cell(x - 1, y)
		if not check_match(p_data.left_joints, n_data.right_joints): return false
		if _has_any_interlock(p_data.left_joints, n_data.right_joints): has_valid_connection = true
	# 下隣
	if get_piece_at(x, y + 1) != null:
		var n_data = _get_data_from_cell(x, y + 1)
		if not check_match(p_data.bottom_joints, n_data.top_joints): return false
		if _has_any_interlock(p_data.bottom_joints, n_data.top_joints): has_valid_connection = true
	# 上隣
	if get_piece_at(x, y - 1) != null:
		var n_data = _get_data_from_cell(x, y - 1)
		if not check_match(p_data.top_joints, n_data.bottom_joints): return false
		if _has_any_interlock(p_data.top_joints, n_data.bottom_joints): has_valid_connection = true

	return has_valid_connection

func check_match(my_joints: Array, neighbor_joints: Array) -> bool:
	for i in range(3):
		var me: int = my_joints[i]
		var neighbor: int = neighbor_joints[i]
		if me == Joint.Type.CONVEX and neighbor != Joint.Type.CONCAVE: return false
		if neighbor == Joint.Type.CONVEX and me != Joint.Type.CONCAVE: return false
	return true 
	
func _has_any_interlock(my_side: Array, neighbor_side: Array) -> bool:
	for i in range(3):
		if is_interlocking(my_side[i], neighbor_side[i]): return true
	return false

func is_interlocking(joint_a: int, joint_b: int) -> bool:
	if joint_a == Joint.Type.CONVEX and joint_b == Joint.Type.CONCAVE: return true
	if joint_a == Joint.Type.CONCAVE and joint_b == Joint.Type.CONVEX: return true
	return false

func _get_data_from_cell(x: int, y: int):
	var cell = grid[y][x]
	return cell.piece_data if (cell is Node) else cell
