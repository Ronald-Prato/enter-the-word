extends Node

## Total de unidades de recurso recogidas en esta partida (HUD, etc.).
var collected: int = 0
signal collected_changed(total: int)

## Total de puntos de experiencia recogidos (drops azules de los enemigos).
var experience: int = 0
signal experience_changed(total: int)

## Recompensas del Artifact (suelo dorado).
var artifact_rewards: int = 0
signal artifact_rewards_changed(total: int)


func add_collected(amount: int = 1) -> void:
	if amount <= 0:
		return
	collected += amount
	collected_changed.emit(collected)


func add_experience(amount: int = 1) -> void:
	if amount <= 0:
		return
	experience += amount
	experience_changed.emit(experience)


func add_artifact_reward(amount: int = 1) -> void:
	if amount <= 0:
		return
	artifact_rewards += amount
	artifact_rewards_changed.emit(artifact_rewards)
