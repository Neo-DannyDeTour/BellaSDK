for file in core/FrameSpikeDetector.gd core/GestureInputManager.gd core/KeycardSystem.gd core/chunk_manager.gd core/dev_metrics.gd core/frame_graph.gd core/global_settings.gd core/graphics_manager.gd core/save_manager.gd core/save_slot.gd; do
  echo "========== $file =========="
  cat $file
done
