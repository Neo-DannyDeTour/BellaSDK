# Oh wait, the error is:
# ERROR: Uniforms were never supplied for set (0) at the time of drawing, which are required by the pipeline.
# In Godot, `rd.draw_list_draw(display_list, false, 1)` uses `display_pipeline`.
# Let's check `SunshineCloudsDisplay.glsl`!
