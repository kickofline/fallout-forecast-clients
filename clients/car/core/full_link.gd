extends Reference
## Transport contract for the Full-tier client (docs/open-protocol/spec-full.md).
##
## The Full client (core/full_net.gd) only ever talks to a FullLink. Three
## implementations exist:
##   - core/ws_full_link.gd  : WebSocket to a Full server (ws:// or wss://)
##   - core/tcp_full_link.gd : length-prefixed TCP to a Full server
##   - solo/local_link.gd    : in-process solo authority (no network)
## All behave identically from the client's point of view, so solo play
## exercises exactly the same client code as online play.
##
## Messages are Dictionaries shaped like the spec §6 JSON envelope, but with
## RPC arguments ALREADY DECODED to native Godot 3 Variants (Vector3, Basis,
## Transform, Color, PoolVector3Array, Dictionary, int, float, ...), never the
## {"_t":...} wire form. Online links handle the negotiated encoding.
##
##   control: {"t":"hello"|"welcome"|"error"|"ping"|"pong"|"leave", ...}  (spec-common)
##   rpc:     {"t":"rpc", "node":"Net", "method":"_push_roster", "args":[...], "rel":true}
##   raw:     {"t":"raw", "data":PoolByteArray(...), "ch":0, "rel":true}
##
## Threading: emit signals ONLY from poll(), which the client calls once per
## main-loop frame. A link may service its socket on a helper thread (see the
## Thin core/net.gd for why), but events are queued and delivered from poll().

signal message(msg)            # msg: Dictionary (see above)
signal closed(code, reason)    # code: int (-1 if no close frame), reason: String

## Peer id from welcome.you (0 until welcomed).
var you := 0


## Connect / start. hello is the spec §2 hello WITHOUT "t" handling needed:
## {"v":1,"tier":"full","enc":"json","client":"fallout-car/x.y"}.
func open(_hello: Dictionary) -> void:
	pass


## Send one message (control or rpc, decoded-args form).
func send(_msg: Dictionary) -> void:
	pass


## Called once per main-loop frame; deliver queued events via signals here.
func poll(_delta: float) -> void:
	pass


## Graceful leave + close. No "closed" signal is required after a deliberate close.
func close() -> void:
	pass


## Called by the client after the level for map_id is instanced and its
## physics/nav are built (world/level_physics.gd), right before it sends
## Net._report_in_run(true). The solo link uses it to start its simulation
## inside the same SceneTree; the WebSocket link ignores it.
## level_root: the instanced level Spatial. world: the client's world node
## (gives access to the 3D scene root for spawning authority-side helpers).
func level_ready(_map_id: String, _level_root: Spatial, _world: Node) -> void:
	pass


## Called when the client unloads the level (results / leave).
func level_unloaded() -> void:
	pass


## true for the in-process solo link.
func is_local() -> bool:
	return false
