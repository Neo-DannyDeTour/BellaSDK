extends FogVolume

@export var fog_material: FogMaterial 

func _ready() -> void: 
	# Tell the Autoload where the fog is so it can do the math
	SmokeManager.active_fog_volume = self
	
	# Grab the GPU texture created by our Autoload
	var texture_rd := Texture3DRD.new()
	texture_rd.texture_rd_rid = SmokeManager.texture_rid
	
	# --- CRITICAL FIX ---
	# Assign the texture to your exported material, 
	# AND assign that material to the actual node!
	if fog_material:
		fog_material.density_texture = texture_rd
		self.material = fog_material
