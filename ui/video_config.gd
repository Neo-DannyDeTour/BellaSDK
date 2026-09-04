## Defines lookup dictionaries, constant defaults, and graphics preset configurations.
class_name VideoConfig
extends RefCounted

## The default application display mode.
const DEFAULT_DISPLAY: int = DisplayServer.WINDOW_MODE_FULLSCREEN
## The default framerate target.
const DEFAULT_FPS: int = 60
## The default FSR configuration string.
const DEFAULT_FSR_MODE: String = "Disabled (Native)"
## The default Anti-Aliasing configuration string.
const DEFAULT_AA_MODE: String = "Disabled"
## The default VSync state.
const DEFAULT_VSYNC: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED
## The default preset configuration string.
const DEFAULT_PRESET: String = "High"
## The default Tonemapping algorithm mode.
const DEFAULT_TONEMAP: String = "Filmic"
## The default Anisotropic filtering setting string.
const DEFAULT_ANISOTROPY: String = "4x"
## The default SSAO quality mode string.
const DEFAULT_SSAO: String = "Medium"
## The default SSIL quality mode string.
const DEFAULT_SSI: String = "Off"
## The default SSR quality mode string.
const DEFAULT_SSR: String = "Off"
## The default SDFGI quality mode string.
const DEFAULT_SDFGI: String = "Off"
## The default volumetric fog quality mode string.
const DEFAULT_FOG: String = "Off"
## The default glow quality mode string.
const DEFAULT_GLOW: String = "High"

## Map of window mode titles to their respective [enum DisplayServer.WindowMode] values.
const DISPLAY_MODES: Dictionary = {
	"Fullscreen": DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	"Borderless Windowed": DisplayServer.WINDOW_MODE_FULLSCREEN,
	"Windowed": DisplayServer.WINDOW_MODE_WINDOWED
}

## Map of rendering driver labels to their Godot project setting identifiers.
const RENDERER_MODES: Dictionary = {
	"Forward+ (Vulkan High-End)": "forward_plus",
	"Mobile (Vulkan Mobile)": "mobile",
	"Compatibility (OpenGL Low-End)": "gl_compatibility"
}

## Map of screen resolution labels to their respective pixel dimensions.
const RESOLUTIONS: Dictionary = {
	"1920 x 1080": Vector2i(1920, 1080),
	"1600 x 900": Vector2i(1600, 900),
	"1366 x 768": Vector2i(1366, 768),
	"1280 x 720": Vector2i(1280, 720),
	"1024 x 768": Vector2i(1024, 768),
	"800 x 600": Vector2i(800, 600),
	"640 x 480": Vector2i(640, 480)
}

## Map of selectable FPS limit labels to integer caps.
const FPS_LIMITS: Dictionary[String, int] = {
	"30 FPS": 30,
	"40 FPS": 40,
	"60 FPS": 60,
	"90 FPS": 90,
	"120 FPS": 120,
	"144 FPS": 144,
	"Unlimited": 0,
}

## Map of VSync option labels to [enum DisplayServer.VSyncMode] values.
const VSYNC_MODES: Dictionary = {
	"Enabled": DisplayServer.VSYNC_ENABLED,
	"Disabled": DisplayServer.VSYNC_DISABLED,
	"Adaptive": DisplayServer.VSYNC_ADAPTIVE
}

## Map of FSR 2 quality modes to their viewport 3D render scales.
const FSR_MODES: Dictionary = {
	"Disabled (Native)": 1.0, "Quality": 0.77, "Balanced": 0.59, "Performance": 0.50
}

## Map of anti-aliasing modes to MSAA, TAA, and FXAA configurations.
const AA_MODES: Dictionary = {
	"Disabled":
	{"msaa": Viewport.MSAA_DISABLED, "taa": false, "fxaa": Viewport.SCREEN_SPACE_AA_DISABLED},
	"FXAA (Fast)":
	{"msaa": Viewport.MSAA_DISABLED, "taa": false, "fxaa": Viewport.SCREEN_SPACE_AA_FXAA},
	"TAA (Smooth)":
	{"msaa": Viewport.MSAA_DISABLED, "taa": true, "fxaa": Viewport.SCREEN_SPACE_AA_DISABLED},
	"MSAA 2x": {"msaa": Viewport.MSAA_2X, "taa": false, "fxaa": Viewport.SCREEN_SPACE_AA_DISABLED},
	"MSAA 4x": {"msaa": Viewport.MSAA_4X, "taa": false, "fxaa": Viewport.SCREEN_SPACE_AA_DISABLED},
	"MSAA 8x (Heavy)":
	{"msaa": Viewport.MSAA_8X, "taa": false, "fxaa": Viewport.SCREEN_SPACE_AA_DISABLED},
	"MSAA 2x + TAA (High)":
	{"msaa": Viewport.MSAA_2X, "taa": true, "fxaa": Viewport.SCREEN_SPACE_AA_DISABLED}
}

## Map of shadow quality options to atlas sizes and filter settings.
const SHADOW_QUALITIES: Dictionary = {
	"Off": {"atlas_size": 0, "filter": 0},
	"Low (Fast)": {"atlas_size": 1024, "filter": 0},
	"Medium": {"atlas_size": 2048, "filter": 1},
	"High (Smooth)": {"atlas_size": 4096, "filter": 2}
}

## Map of Tonemapper option labels to configuration identifiers.
const TONEMAP_MODES: Dictionary = {
	"Linear": "linear",
	"Reinhard": "reinhard",
	"Filmic": "filmic",
	"ACES": "aces",
	"AgX": "agx",
	"AgX (Punchy)": "agx_punchy"
}

## Map of texture Anisotropic filtering levels to integer settings.
const ANISOTROPY_LEVELS: Dictionary = {"Disabled": 0, "2x": 1, "4x": 2, "8x": 3, "16x": 4}

## Map of SSAO quality tiers to engine rendering configurations.
const SSAO_MODES: Dictionary = {
	"Off": {"enabled": false, "quality": 0, "half_size": true},
	"Low": {"enabled": true, "quality": 0, "half_size": true},
	"Medium": {"enabled": true, "quality": 1, "half_size": false},
	"High": {"enabled": true, "quality": 2, "half_size": false}
}

## Map of SSIL quality tiers to engine rendering configurations.
const SSI_MODES: Dictionary = {
	"Off": {"enabled": false, "quality": 0, "half_size": true},
	"Low": {"enabled": true, "quality": 0, "half_size": true},
	"Medium": {"enabled": true, "quality": 1, "half_size": false},
	"High": {"enabled": true, "quality": 2, "half_size": false}
}

## Map of SSR quality tiers to ray step configurations.
const SSR_MODES: Dictionary = {
	"Off": {"enabled": false, "steps": 0},
	"Low": {"enabled": true, "steps": 32},
	"Medium": {"enabled": true, "steps": 64},
	"High": {"enabled": true, "steps": 128}
}

## Map of SDFGI quality tiers to cascade count configurations.
const SDFGI_MODES: Dictionary = {
	"Off": {"enabled": false, "cascades": 4},
	"Low": {"enabled": true, "cascades": 4},
	"Medium": {"enabled": true, "cascades": 6},
	"High": {"enabled": true, "cascades": 8}
}

## Map of volumetric fog quality tiers to volume depth configurations.
const FOG_MODES: Dictionary = {
	"Off": {"enabled": false, "depth": 64},
	"Low": {"enabled": true, "depth": 64},
	"Medium": {"enabled": true, "depth": 96},
	"High": {"enabled": true, "depth": 128}
}

## Map of glow quality tiers to filtering configurations.
const GLOW_MODES: Dictionary = {
	"Off": {"enabled": false, "bicubic": false},
	"Low": {"enabled": true, "bicubic": false},
	"High": {"enabled": true, "bicubic": true}
}

## Preset configurations mapping quality levels to specific feature states.
const PRESETS: Dictionary = {
	"Low":
	{
		"shadow_quality": "Low (Fast)",
		"ssao": "Off",
		"ssi": "Off",
		"ssr": "Off",
		"sdfgi": "Off",
		"volumetric_fog": "Off",
		"glow": "Off",
		"mesh_lod_threshold": 2.0
	},
	"Medium":
	{
		"shadow_quality": "Medium",
		"ssao": "Low",
		"ssi": "Off",
		"ssr": "Off",
		"sdfgi": "Off",
		"volumetric_fog": "Off",
		"glow": "Low",
		"mesh_lod_threshold": 1.5
	},
	"High":
	{
		"shadow_quality": "High (Smooth)",
		"ssao": "Medium",
		"ssi": "Low",
		"ssr": "Low",
		"sdfgi": "Low",
		"volumetric_fog": "Off",
		"glow": "High",
		"mesh_lod_threshold": 1.0
	},
	"Ultra":
	{
		"shadow_quality": "High (Smooth)",
		"ssao": "High",
		"ssi": "High",
		"ssr": "High",
		"sdfgi": "High",
		"volumetric_fog": "High",
		"glow": "High",
		"mesh_lod_threshold": 0.5
	}
}
