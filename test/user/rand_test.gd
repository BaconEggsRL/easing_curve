extends Node

const _seed = 12345

var rng := RandomNumberGenerator.new()


func _ready():
	print("default")
	seed(_seed)
	print(randi()) ## 1321476956
	seed(_seed)
	print(randi()) ## 1321476956
	seed(_seed)
	print(randi()) ## 1321476956
	seed(_seed)
	print(randi()) ## 1321476956

	print()
	print("rng")
	rng.seed = _seed
	print(rng.randi()) ## 1321476956
	print(rng.randi()) ## 1321476956
	print(rng.randi()) ## 1321476956
	print(rng.randi()) ## 1321476956
	print(rng.randi()) ## 1321476956
