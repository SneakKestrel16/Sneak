extends Node
## Session settings carried from the main menu into the game, the ENet peer
## that connects players, and a helper to replicate node properties.

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 6
const MENU := "res://scenes/main_menu.tscn"

var port := DEFAULT_PORT  ## `-- --port=N` overrides it (the smoke test uses its own).
var hosting := true
var address := "127.0.0.1"
var message := ""  ## Shown by the main menu after a session ends.
var args_used := false  ## Command-line --host/--join only apply once.


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
	# Connected here, once: the multiplayer API outlives each game scene, so connecting in
	# game.gd added a duplicate every time a session started.
	multiplayer.server_disconnected.connect(stop.bind("The host left."), CONNECT_DEFERRED)
	multiplayer.connection_failed.connect(
		func() -> void: stop("Could not reach %s:%d." % [address, port]), CONNECT_DEFERRED
	)


## Hosts or joins, depending on the menu choice. Returns the ENet error.
func start() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := (
		peer.create_server(port, MAX_PLAYERS - 1) if hosting else peer.create_client(address, port)
	)
	if error == OK:
		multiplayer.multiplayer_peer = peer
	return error


## Leaves the session and goes back to the menu, showing reason there.
func stop(reason: String) -> void:
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	message = reason
	if reason != "":
		print("[net] session ended: %s" % reason)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU)


## Adds a MultiplayerSynchronizer that sends node's properties from its
## authority to everyone else: every network frame by default, or only when
## they change (REPLICATION_MODE_ON_CHANGE).
func replicate(
	node: Node,
	properties: Array[String],
	mode := SceneReplicationConfig.REPLICATION_MODE_ALWAYS,
) -> void:
	var config := SceneReplicationConfig.new()
	for property in properties:
		var path := NodePath(".:" + property)
		config.add_property(path)
		config.property_set_replication_mode(path, mode)
	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "Sync"  # Same path on every peer; see docs/gotchas.md.
	synchronizer.replication_config = config
	node.add_child(synchronizer)
