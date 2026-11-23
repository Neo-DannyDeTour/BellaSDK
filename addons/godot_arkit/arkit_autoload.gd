@tool
## Autoload singleton bridging [ARKitServer] UDP facial mocap streams to editor and runtime nodes.
extends Node

## Emitted by UI or callers to start the UDP listener.
signal start_server
## Emitted by UI or callers to stop the UDP listener.
signal stop_server
## Emitted by UI or callers to change the UDP listener port to [param p].
signal change_port(p: int)
## Emitted when an error message [param e] should be displayed.
signal show_error(e: String)
## Emitted when the active error display should be cleared.
signal clear_error
## Emitted when a new [ARKitSubject] [param s] is discovered on the UDP stream.
signal add_subject(s: ARKitSubject)
## Emitted when an [ARKitSubject] [param s] is removed.
signal remove_subject(s: ARKitSubject)
## Emitted when a subject with [param subject_device_id] is selected in the UI.
signal select_subject(subject_device_id: String)
## Emitted on every valid UDP facial frame received from [param subject].
signal frame_received(subject: ARKitSubject, packet: ARKitPacket)

## Active [ARKitServer] UDP instance managed by this singleton.
var _server: ARKitServer = null


## Creates [member _server] on port 11111 and connects lifecycle and subject signals.
func _ready() -> void:
	_server = ARKitServer.new(11111)
	_server.add_subject.connect(_on_server_add_subject)
	_server.remove_subject.connect(_on_server_remove_subject)
	_server.frame_received.connect(_on_server_frame_received)

	change_port.connect(_on_change_port)
	start_server.connect(_on_start_server)
	stop_server.connect(_on_stop_server)


## Polls [member _server] every frame while listening.
func _process(_delta: float) -> void:
	if is_instance_valid(_server):
		_server.poll()


## Stops [member _server] cleanly on tree exit.
func _exit_tree() -> void:
	if is_instance_valid(_server):
		_server.stop()


## Returns the underlying [ARKitServer] instance.
func get_server() -> ARKitServer:
	return _server


## Returns true if a tracked subject with [param subject_name] exists.
func has_subject_from_name(subject_name: String) -> bool:
	if not is_instance_valid(_server):
		return false
	for subject: ARKitSubject in _server.subjects.values():
		if subject.subject_name == subject_name:
			return true
	return false


## Returns the tracked [ARKitSubject] matching [param subject_name], or null if not found.
func get_subject_from_name(subject_name: String) -> ARKitSubject:
	if not is_instance_valid(_server):
		return null
	for subject: ARKitSubject in _server.subjects.values():
		if subject.subject_name == subject_name:
			return subject
	return null


## Returns an array of all currently tracked [ARKitSubject] instances.
func get_subject_list() -> Array[ARKitSubject]:
	var result: Array[ARKitSubject] = []
	if not is_instance_valid(_server):
		return result
	for subject: ARKitSubject in _server.subjects.values():
		result.append(subject)
	return result


## Returns true if a subject with [param device_id] is currently tracked.
func has_subject(device_id: String) -> bool:
	if not is_instance_valid(_server):
		return false
	return _server.subjects.has(device_id)


## Returns the tracked [ARKitSubject] for [param device_id], or null if not found.
func get_subject(device_id: String) -> ARKitSubject:
	if has_subject(device_id):
		return _server.subjects[device_id]
	return null


## Starts [member _server] and emits [signal show_error] on failure.
func _on_start_server() -> void:
	if not is_instance_valid(_server):
		return
	var err: Error = _server.start()
	if err != OK:
		show_error.emit("Failed to listen on port %d" % _server.get_port())
	else:
		clear_error.emit()


## Stops [member _server] when requested.
func _on_stop_server() -> void:
	if is_instance_valid(_server):
		_server.stop()


## Forwards [param s] addition from [member _server].
func _on_server_add_subject(s: ARKitSubject) -> void:
	add_subject.emit(s)


## Forwards [param s] removal from [member _server].
func _on_server_remove_subject(s: ARKitSubject) -> void:
	remove_subject.emit(s)


## Forwards incoming [param subject] and [param packet] frames from [member _server].
func _on_server_frame_received(subject: ARKitSubject, packet: ARKitPacket) -> void:
	frame_received.emit(subject, packet)


## Updates the UDP server port to [param port].
func _on_change_port(port: int) -> void:
	if is_instance_valid(_server):
		_server.change_port(port)
