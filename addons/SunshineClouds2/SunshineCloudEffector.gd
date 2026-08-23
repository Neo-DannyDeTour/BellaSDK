## Volumetric cloud density effector for local displacement carving and puffing.
##
## Place as a child [Node3D] in the scene tree to locally add density or carve hollows
## in the volumetric cloud field.
@tool
class_name SunshineCloudsEffector
extends Node3D

## Effective sphere radius in world units affected by this effector.
@export_range(0.01, 100000.0, 1.0, "suffix:m") var radius: float = 1000.0

## Density influence multiplier. Positive values add density; negative values carve hollows.
@export_range(-100.0, 100.0, 0.1) var power: float = 5.0

## Radial distance attenuation exponent controlling edge falloff smoothness.
@export_range(0.01, 10.0, 0.05) var attenuation: float = 1.0
