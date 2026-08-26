extends Node

func _ready() -> void:
	print("before")
	var nul := String.chr(0)
	print("after")
	print("nul empty: ", nul.is_empty())
