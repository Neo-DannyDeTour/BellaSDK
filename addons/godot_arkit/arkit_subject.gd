@tool
## Tracks a connected Live Link Face sender subject and its latest [ARKitPacket].
class_name ARKitSubject
extends RefCounted

## Emitted when more than 30 seconds elapse between consecutive packets for this subject.
signal timed_out

## Sender iOS device UUID string.
var device_id: String = ""
## Human-readable Live Link Face subject name.
var subject_name: String = ""
## System Unix timestamp in seconds when the latest packet was received.
var last_seen_unix: float = 0.0
## Most recent valid [ARKitPacket] received from this subject.
var packet: ARKitPacket = null


## Initializes the subject record from its first valid [param arkit_packet].
func _init(arkit_packet: ARKitPacket) -> void:
	last_seen_unix = Time.get_unix_time_from_system()
	device_id = arkit_packet.device_id
	subject_name = arkit_packet.subject_name
	packet = arkit_packet


## Updates [member packet] and refreshes [member last_seen_unix] or emits [signal timed_out].
func update_packet(arkit_packet: ARKitPacket) -> void:
	packet = arkit_packet
	var current_time_unix: float = Time.get_unix_time_from_system()
	if current_time_unix - last_seen_unix > 30.0:
		timed_out.emit()
	last_seen_unix = current_time_unix
