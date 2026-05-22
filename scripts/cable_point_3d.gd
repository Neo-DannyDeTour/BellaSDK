@tool
extends Marker3D
class_name CablePoint3D

@export_category("Span to Next Point")
## How far the cable hangs between THIS point and the next one
@export var droop: float = 2.0

## Lower is better for performance. Controls segments for THIS span only.
@export var segments: int = 10
