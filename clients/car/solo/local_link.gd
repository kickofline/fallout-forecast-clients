extends "res://core/full_link.gd"
## Solo play: an in-process Full-tier authority (OWNER: the solo worker).
## Implements the server side of docs/open-protocol (lobby, run lifecycle and
## every server->client RPC in rpc-catalog.md) so the Full client runs solo
## through exactly the same code path as online. Stub: welcomes and does nothing.

var _queue = []


func is_local() -> bool:
	return true


func open(_hello: Dictionary) -> void:
	you = 2
	_queue.append({"t": "welcome", "v": 1, "tier": "full", "enc": "json", "you": you, "game_protocol": 19,
		"maps": [{"id": "pinecrest", "name": "PINECREST"}, {"id": "harbor", "name": "HARBOR POINT"}, {"id": "maple_hollow", "name": "MAPLE HOLLOW"}]})


func poll(_delta: float) -> void:
	var q = _queue
	_queue = []
	for m in q:
		emit_signal("message", m)
