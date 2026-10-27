## Declarative weather preset resource for [SunshineCloudsDriverGD] transitions.
@tool
class_name SunshineCloudsWeather
extends Resource

## Cloud coverage fraction in the [0.0, 1.0] range.
@export_range(0.0, 1.0) var clouds_coverage: float = 0.874

## Cloud density multiplier.
@export_range(0.0, 20.0) var clouds_density: float = 0.14

## Atmospheric scattering density multiplier.
@export_range(0.0, 2.0) var atmospheric_density: float = 0.503

## Optional vertical height gradient texture override (null keeps active gradient).
@export var height_gradient: Texture2D = null

## Wind speed for extra-large cloud structures.
@export var extra_large_structures_wind_speed: float = 140.0

## Wind speed for large cloud structures.
@export var large_structures_wind_speed: float = 100.0

## Wind speed for medium cloud structures.
@export var medium_structures_wind_speed: float = 40.0

## Wind speed for small detail cloud structures.
@export var small_structures_wind_speed: float = 12.0
