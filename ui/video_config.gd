## Declarative configuration registry for video settings, mode mappings, and presets.
class_name VideoConfig
extends RefCounted

## Default window display mode (Borderless Windowed).
const DEFAULT_DISPLAY: int = DisplayServer.WINDOW_MODE_FULLSCREEN

## Default target framerate cap.
const DEFAULT_FPS: int = 60

## Default FSR 2 scaling mode label.
const DEFAULT_FSR_MODE: String = "Disabled (Native)"

## Default anti-aliasing mode label.
const DEFAULT_AA_MODE: String = "TAA (Smooth)"

## Default vertical synchronization mode.
const DEFAULT_VSYNC: int = DisplayServer.VSYNC_ENABLED

## Default master quality preset name.
const DEFAULT_PRESET: String = "High"

## Default tonemapping algorithm label.
const DEFAULT_TONEMAP: String = "Filmic"

## Default anisotropic filtering level label.
const DEFAULT_ANISOTROPY: String = "4x"

## Default screen-space ambient occlusion tier ("High" preset default).
const DEFAULT_SSAO: String = "Medium"

## Default screen-space indirect lighting tier ("High" preset default).
const DEFAULT_SSI: String = "Low"

## Default screen-space reflections tier ("High" preset default).
const DEFAULT_SSR: String = "Low"

## Default signed distance field global illumination tier ("High" preset default).
const DEFAULT_SDFGI: String = "Low"

## Default volumetric fog quality tier ("High" preset default).
const DEFAULT_FOG: String = "Off"

## Default glow/bloom quality tier ("High" preset default).
const DEFAULT_GLOW: String = "High"

## Default shadow quality tier ("High" preset default).
const DEFAULT_SHADOW_QUALITY: String = "High (Smooth)"

## Default dynamic light shadow casting state ("High" preset default).
const DEFAULT_DYNAMIC_LIGHT_SHADOWS: bool = true

## Default positional shadow filtering tier ("High" preset default).
const DEFAULT_SHADOW_FILTER: String = "Soft Medium"

## Default positional light shadow fade distance in meters ("High" preset default).
const DEFAULT_POSITIONAL_SHADOW_DISTANCE: float = 32.0

## Default directional light shadow max distance in meters ("High" preset default).
const DEFAULT_DIRECTIONAL_SHADOW_DISTANCE: float = 64.0

## Default occlusion culling state.
const DEFAULT_OCCLUSION_CULLING: bool = true

## Default Variable Rate Shading mode label.
const DEFAULT_VRS_MODE: String = "Disabled"

## Default canvas/texture filter mode label.
const DEFAULT_TEXTURE_FILTER: String = "Linear Mipmap"

## Default 3D resolution scale factor.
const DEFAULT_RESOLUTION_SCALE: float = 1.0

## Default tonemapper exposure multiplier.
const DEFAULT_EXPOSURE: float = 1.0

## Default Depth of Field enabled state ("High" preset default).
const DEFAULT_DOF: bool = true

## Default Depth of Field blur amount when enabled ("High" preset default).
const DEFAULT_DOF_AMOUNT: float = 0.15

## Default camera motion blur strength ("High" preset default).
const DEFAULT_MOTION_BLUR: float = 0.50

## Default mesh LOD threshold ("High" preset default).
const DEFAULT_MESH_LOD: float = 4.0

## Default color debanding state.
const DEFAULT_DEBANDING: bool = true

## Default user interface scale factor.
const DEFAULT_UI_SCALE: float = 1.0

## Default window resolution width in pixels.
const DEFAULT_RES_X: int = 1920

## Default window resolution height in pixels.
const DEFAULT_RES_Y: int = 1080

## Map of positional shadow filter labels to [enum RenderingServer.ShadowQuality] values.
const SHADOW_FILTER_MODES: Dictionary[String, RenderingServer.ShadowQuality] = {
	"Hard (Fast)": RenderingServer.SHADOW_QUALITY_HARD,
	"Soft Low": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
	"Soft Medium": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
	"Soft High": RenderingServer.SHADOW_QUALITY_SOFT_ULTRA,
}

## Map of VRS mode labels to [enum Viewport.VRSMode] values.
const VRS_MODES: Dictionary[String, Viewport.VRSMode] = {
	"Disabled": Viewport.VRS_DISABLED,
	"Texture": Viewport.VRS_TEXTURE,
}

## Map of texture filter labels to engine filter integers.
const TEXTURE_FILTER_MODES: Dictionary[String, int] = {
	"Nearest": 0,
	"Linear": 1,
	"Linear Mipmap": 2,
	"Nearest Mipmap": 3,
}

## Map of window display mode labels to [enum DisplayServer.WindowMode] values.
const DISPLAY_MODES: Dictionary[String, int] = {
	"Fullscreen": DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	"Borderless Windowed": DisplayServer.WINDOW_MODE_FULLSCREEN,
	"Windowed": DisplayServer.WINDOW_MODE_WINDOWED,
}

## Map of rendering driver labels to Godot project setting identifiers.
const RENDERER_MODES: Dictionary[String, String] = {
	"Forward+ (Vulkan High-End)": "forward_plus",
	"Mobile (Vulkan Mobile)": "mobile",
	"Compatibility (OpenGL Low-End)": "gl_compatibility",
}

## Map of screen resolution labels to pixel dimensions.
const RESOLUTIONS: Dictionary[String, Vector2i] = {
	"1920 x 1080": Vector2i(1920, 1080),
	"1600 x 900": Vector2i(1600, 900),
	"1366 x 768": Vector2i(1366, 768),
	"1280 x 720": Vector2i(1280, 720),
	"1024 x 768": Vector2i(1024, 768),
	"800 x 600": Vector2i(800, 600),
	"640 x 480": Vector2i(640, 480),
}

## Map of framerate cap labels to integer FPS limits.
const FPS_LIMITS: Dictionary[String, int] = {
	"30 FPS": 30,
	"40 FPS": 40,
	"60 FPS": 60,
	"90 FPS": 90,
	"120 FPS": 120,
	"144 FPS": 144,
	"Unlimited": 0,
}

## Map of VSync labels to [enum DisplayServer.VSyncMode] values.
const VSYNC_MODES: Dictionary[String, int] = {
	"Disabled": DisplayServer.VSYNC_DISABLED,
	"Enabled": DisplayServer.VSYNC_ENABLED,
	"Adaptive": DisplayServer.VSYNC_ADAPTIVE,
}

## Map of FSR 2 scaling labels to 3D render scale multipliers.
const FSR_MODES: Dictionary[String, float] = {
	"Disabled (Native)": 1.0,
	"Quality": 0.77,
	"Balanced": 0.59,
	"Performance": 0.50,
}

## Map of anti-aliasing labels to MSAA, TAA, and FXAA configuration dictionaries.
const AA_MODES: Dictionary = {
	"Disabled":
	{
		"msaa": Viewport.MSAA_DISABLED,
		"taa": false,
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED,
	},
	"FXAA (Fast)":
	{
		"msaa": Viewport.MSAA_DISABLED,
		"taa": false,
		"fxaa": Viewport.SCREEN_SPACE_AA_FXAA,
	},
	"TAA (Smooth)":
	{
		"msaa": Viewport.MSAA_DISABLED,
		"taa": true,
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED,
	},
	"TAA + FXAA (High)":
	{
		"msaa": Viewport.MSAA_DISABLED,
		"taa": true,
		"fxaa": Viewport.SCREEN_SPACE_AA_FXAA,
	},
	"MSAA 2x":
	{
		"msaa": Viewport.MSAA_2X,
		"taa": false,
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED,
	},
	"MSAA 4x":
	{
		"msaa": Viewport.MSAA_4X,
		"taa": false,
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED,
	},
	"MSAA 8x (Heavy)":
	{
		"msaa": Viewport.MSAA_8X,
		"taa": false,
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED,
	},
}

## Map of shadow quality labels to positional atlas sizes and filter indices.
const SHADOW_QUALITIES: Dictionary = {
	"Off": {"atlas_size": 0, "filter": 0},
	"Low (Fast)": {"atlas_size": 1024, "filter": 0},
	"Medium": {"atlas_size": 2048, "filter": 1},
	"High (Smooth)": {"atlas_size": 4096, "filter": 2},
}

## Map of tonemapper labels to [enum Environment.ToneMapper] values.
const TONEMAP_MODES: Dictionary[String, Environment.ToneMapper] = {
	"Linear": Environment.TONE_MAPPER_LINEAR,
	"Reinhard": Environment.TONE_MAPPER_REINHARDT,
	"Filmic": Environment.TONE_MAPPER_FILMIC,
	"ACES": Environment.TONE_MAPPER_ACES,
	"AgX": Environment.TONE_MAPPER_AGX,
}

## Map of anisotropic filtering labels to ProjectSettings integer indices.
const ANISOTROPY_LEVELS: Dictionary[String, int] = {
	"Disabled": 0,
	"2x": 1,
	"4x": 2,
	"8x": 3,
	"16x": 4,
}

## Map of SSAO quality tiers to engine rendering parameters.
const SSAO_MODES: Dictionary = {
	"Off": {"enabled": false, "quality": 0, "half_size": true},
	"Low": {"enabled": true, "quality": 0, "half_size": true},
	"Medium": {"enabled": true, "quality": 1, "half_size": false},
	"High": {"enabled": true, "quality": 2, "half_size": false},
}

## Map of SSIL quality tiers to engine rendering parameters.
const SSI_MODES: Dictionary = {
	"Off": {"enabled": false, "quality": 0, "half_size": true},
	"Low": {"enabled": true, "quality": 0, "half_size": true},
	"Medium": {"enabled": true, "quality": 1, "half_size": false},
	"High": {"enabled": true, "quality": 2, "half_size": false},
}

## Map of SSR quality tiers to raymarch step limits.
const SSR_MODES: Dictionary = {
	"Off": {"enabled": false, "steps": 0},
	"Low": {"enabled": true, "steps": 32},
	"Medium": {"enabled": true, "steps": 64},
	"High": {"enabled": true, "steps": 128},
}

## Map of SDFGI quality tiers to cascade counts.
const SDFGI_MODES: Dictionary = {
	"Off": {"enabled": false, "cascades": 2},
	"Low": {"enabled": true, "cascades": 2},
	"Medium": {"enabled": true, "cascades": 3},
	"High": {"enabled": true, "cascades": 4},
}

## Map of volumetric fog quality tiers to volume slice depth.
const FOG_MODES: Dictionary = {
	"Off": {"enabled": false, "depth": 64},
	"Low": {"enabled": true, "depth": 64},
	"Medium": {"enabled": true, "depth": 96},
	"High": {"enabled": true, "depth": 128},
}

## Map of glow/bloom quality tiers to upscale filtering flags.
const GLOW_MODES: Dictionary = {
	"Off": {"enabled": false, "bicubic": false},
	"Low": {"enabled": true, "bicubic": false},
	"Medium": {"enabled": true, "bicubic": false},
	"High": {"enabled": true, "bicubic": true},
}

## Master quality preset matrix mapping preset names to feature configurations.
const PRESETS: Dictionary = {
	"Low":
	{
		"shadow_quality": "Low (Fast)",
		"dynamic_light_shadows": false,
		"shadow_filter": "Hard (Fast)",
		"positional_shadow_distance": 16.0,
		"directional_shadow_distance": 32.0,
		"occlusion_culling": true,
		"vrs_mode": "Disabled",
		"texture_filter": "Linear",
		"fsr_mode": "Disabled (Native)",
		"resolution_scale": 0.70,
		"dof_enabled": false,
		"dof_amount": 0.0,
		"motion_blur": 0.0,
		"ssao": "Off",
		"ssi": "Off",
		"ssr": "Off",
		"sdfgi": "Off",
		"volumetric_fog": "Off",
		"glow": "Off",
		"mesh_lod_threshold": 32.0,
	},
	"Medium":
	{
		"shadow_quality": "Medium",
		"dynamic_light_shadows": true,
		"shadow_filter": "Soft Low",
		"positional_shadow_distance": 24.0,
		"directional_shadow_distance": 48.0,
		"occlusion_culling": true,
		"vrs_mode": "Disabled",
		"texture_filter": "Linear Mipmap",
		"fsr_mode": "Disabled (Native)",
		"resolution_scale": 1.0,
		"dof_enabled": false,
		"dof_amount": 0.0,
		"motion_blur": 0.25,
		"ssao": "Low",
		"ssi": "Off",
		"ssr": "Off",
		"sdfgi": "Off",
		"volumetric_fog": "Off",
		"glow": "Low",
		"mesh_lod_threshold": 16.0,
	},
	"High":
	{
		"shadow_quality": "High (Smooth)",
		"dynamic_light_shadows": true,
		"shadow_filter": "Soft Medium",
		"positional_shadow_distance": 32.0,
		"directional_shadow_distance": 64.0,
		"occlusion_culling": true,
		"vrs_mode": "Disabled",
		"texture_filter": "Linear Mipmap",
		"fsr_mode": "Disabled (Native)",
		"resolution_scale": 1.0,
		"dof_enabled": true,
		"dof_amount": 0.15,
		"motion_blur": 0.50,
		"ssao": "Medium",
		"ssi": "Low",
		"ssr": "Low",
		"sdfgi": "Low",
		"volumetric_fog": "Off",
		"glow": "High",
		"mesh_lod_threshold": 4.0,
	},
	"Ultra":
	{
		"shadow_quality": "High (Smooth)",
		"dynamic_light_shadows": true,
		"shadow_filter": "Soft High",
		"positional_shadow_distance": 40.0,
		"directional_shadow_distance": 80.0,
		"occlusion_culling": true,
		"vrs_mode": "Disabled",
		"texture_filter": "Linear Mipmap",
		"fsr_mode": "Disabled (Native)",
		"resolution_scale": 1.0,
		"dof_enabled": true,
		"dof_amount": 0.15,
		"motion_blur": 0.75,
		"ssao": "High",
		"ssi": "Medium",
		"ssr": "Medium",
		"sdfgi": "Medium",
		"volumetric_fog": "Medium",
		"glow": "High",
		"mesh_lod_threshold": 1.0,
	},
}


## Returns a complete default settings dictionary built from the "High" preset.
static func get_default_settings_dict() -> Dictionary:
	var base: Dictionary = {
		"display_mode": DEFAULT_DISPLAY,
		"screen_index": 0,
		"resolution_x": DEFAULT_RES_X,
		"resolution_y": DEFAULT_RES_Y,
		"vsync_mode": DEFAULT_VSYNC,
		"fps_limit": DEFAULT_FPS,
		"ui_scale": DEFAULT_UI_SCALE,
		"preset": DEFAULT_PRESET,
		"aa_mode": DEFAULT_AA_MODE,
		"anisotropy": DEFAULT_ANISOTROPY,
		"tonemap_mode": DEFAULT_TONEMAP,
		"exposure": DEFAULT_EXPOSURE,
		"debanding": DEFAULT_DEBANDING,
		"renderer": "forward_plus",
		"gpu_adapter_index": 0,
	}
	var high_preset: Dictionary = PRESETS["High"] as Dictionary
	for key: Variant in high_preset.keys():
		base[key] = high_preset[key]
	return base
