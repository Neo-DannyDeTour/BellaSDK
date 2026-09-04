## A fog volume that simulates localized smoke using a compute shader.
##
## [SmokeSimulation] leverages a [FogVolume] paired with a [FogMaterial]
## to render volumetric smoke driven by the [SmokeManager]'s 3D texture.
class_name SmokeSimulation
extends FogVolume

## The material applied to this fog volume.
@export var fog_material: FogMaterial
## The base color of the smoke rendered in the volume.
@export var smoke_color: Color = Color(0.6, 0.6, 0.6)

## The resolution of the simulation grid.
var grid_size: int = 128


## Initializes the fog volume, binds it to the global [SmokeManager], and updates its material.
func _ready() -> void:
	SmokeManager.active_fog_volume = self

	var texture_rd: Texture3DRD = Texture3DRD.new()
	texture_rd.texture_rd_rid = SmokeManager.texture_rid

	if fog_material:
		fog_material.density_texture = texture_rd
		fog_material.albedo = smoke_color

		# Increase base density significantly for thick, opaque smoke.
		# Default is 1.0, which is often too thin for weapon smoke.
		fog_material.density = 4.0

		self.material = fog_material
