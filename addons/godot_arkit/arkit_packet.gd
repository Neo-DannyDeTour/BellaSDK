@tool
## Decodes and validates a big-endian Live Link Face v6 UDP packet into 52+9 ARKit floats.
class_name ARKitPacket
extends RefCounted

## Magic number for Live Link Face ARKit UDP packet format (version 6).
const PACKET_VERSION: int = 6
## Minimum header size in bytes before variable-length strings and blendshape floats.
const MIN_PACKET_BYTES: int = 26
## Upper bound for device ID and subject name string byte lengths to reject corrupt frames.
const MAX_STRING_BYTES: int = 1024

## Whether the UDP byte payload parsed cleanly as a valid version-6 ARKit frame.
var is_valid: bool = false
## Decoded Live Link Face protocol version byte.
var packet_version: int = 0
## Byte length of [member device_id].
var device_id_length: int = 0
## Sender iOS device UUID string.
var device_id: String = ""
## Byte length of [member subject_name].
var subject_name_length: int = 0
## Live Link Face subject name string.
var subject_name: String = ""
## Monotonic timecode frame index from the sender.
var frame: int = 0
## Timecode subframe value from the sender.
var subframe: int = 0
## Sender capture frame rate (typically 60 FPS).
var fps: int = 60
## Timecode rate denominator from the sender.
var denominator: int = 1
## Number of float channels contained in [member blendshapes_array] (typically 61).
var number_of_blendshapes: int = 0
## Decoded blendshape and head/eye rotation floats in Live Link Face index order.
var blendshapes_array: PackedFloat32Array = PackedFloat32Array()


## Decodes [param array_bytes] from a big-endian Live Link Face v6 UDP datagram.
func _init(array_bytes: PackedByteArray = PackedByteArray()) -> void:
	if array_bytes.size() < MIN_PACKET_BYTES:
		return

	var stream_peer_buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	stream_peer_buffer.data_array = array_bytes.duplicate()
	stream_peer_buffer.big_endian = true

	packet_version = stream_peer_buffer.get_u8()
	if packet_version != PACKET_VERSION:
		return

	if stream_peer_buffer.get_available_bytes() < 4:
		return
	device_id_length = stream_peer_buffer.get_u32()
	if (
		device_id_length <= 0
		or device_id_length > MAX_STRING_BYTES
		or stream_peer_buffer.get_available_bytes() < device_id_length + 4
	):
		return
	device_id = stream_peer_buffer.get_string(device_id_length)

	subject_name_length = stream_peer_buffer.get_u32()
	if (
		subject_name_length < 0
		or subject_name_length > MAX_STRING_BYTES
		or stream_peer_buffer.get_available_bytes() < subject_name_length + 17
	):
		return
	subject_name = (
		stream_peer_buffer.get_string(subject_name_length) if subject_name_length > 0 else ""
	)

	frame = stream_peer_buffer.get_u32()
	subframe = stream_peer_buffer.get_u32()
	fps = stream_peer_buffer.get_u32()
	denominator = stream_peer_buffer.get_u32()
	number_of_blendshapes = stream_peer_buffer.get_u8()

	var required_float_bytes: int = number_of_blendshapes * 4
	if (
		number_of_blendshapes <= 0
		or stream_peer_buffer.get_available_bytes() < required_float_bytes
	):
		return

	blendshapes_array.resize(number_of_blendshapes)
	for idx: int in range(number_of_blendshapes):
		blendshapes_array[idx] = stream_peer_buffer.get_float()

	is_valid = true


## Serializes a valid big-endian Live Link Face v6 UDP packet payload for testing or loopback.
static func build_packet_bytes(
	device_id_str: String,
	subject_name_str: String,
	frame_num: int,
	fps_val: int,
	weights: PackedFloat32Array,
	subframe_num: int = 0,
	denom_val: int = 1
) -> PackedByteArray:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.big_endian = true
	buf.put_u8(PACKET_VERSION)

	var dev_bytes: PackedByteArray = device_id_str.to_utf8_buffer()
	buf.put_u32(dev_bytes.size())
	buf.put_data(dev_bytes)

	var subj_bytes: PackedByteArray = subject_name_str.to_utf8_buffer()
	buf.put_u32(subj_bytes.size())
	buf.put_data(subj_bytes)

	buf.put_u32(frame_num)
	buf.put_u32(subframe_num)
	buf.put_u32(fps_val)
	buf.put_u32(denom_val)

	var count: int = mini(weights.size(), 255)
	buf.put_u8(count)
	for idx: int in range(count):
		buf.put_float(weights[idx])

	return buf.data_array
