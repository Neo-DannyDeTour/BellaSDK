# Warden's Journal - Critical Learnings

- **Exposed Debug Commands**: Leaving debug commands (like `noclip` and `gamespeed`) exposed in client-side scripts, UI nodes, or hotkeys without verifying `OS.is_debug_build()` allows players in production builds to manipulate global state, bypass collision limits, and cheat. All debug commands must be wrapped in environmental checks.
- **Exposed Debug Commands in UI**: Leaving debug commands like Godmode exposed in UI panels (such as `gameplay_panel.gd`) without verifying `OS.has_feature("debug")` allows players in production builds to enable Godmode and cheat. UI toggles for debug mechanics must be hidden and their effects blocked if `OS.has_feature("debug")` is false to prevent client-side overrides of game state.
