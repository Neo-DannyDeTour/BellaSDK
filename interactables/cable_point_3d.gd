@tool
## A 3D marker that defines a point along a physics or visual cable.
##
## Controls the droop and segmentation details for the cable span between this point
## and the subsequent point in the hierarchy.
class_name CablePoint3D
extends Marker3D

@export_category("Span to Next Point")
## How far the cable hangs downward between this point and the next one.
@export var droop: float = 2.0

## The number of geometry segments used for this span. Lower is better for performance.
@export var segments: int = 10
