extends FogVolume

@export var fog_material: FogMaterial
@export var smoke_color: Color = Color(0.6, 0.6, 0.6)

var grid_size: int = 128


func _ready() -> void:
	SmokeManager.active_fog_volume = self

	var texture_rd := Texture3DRD.new()
	texture_rd.texture_rd_rid = SmokeManager.texture_rid

	if fog_material:
		fog_material.density_texture = texture_rd
		fog_material.albedo = smoke_color
		
		# Increase base density significantly for thick, opaque smoke.
		# Default is 1.0, which is often too thin for weapon smoke.
		fog_material.density = 4.0 
		
		self.material = fog_material
