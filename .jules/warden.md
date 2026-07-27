# Warden's Journal - Critical Learnings

- **Exposed Debug Commands**: Leaving debug commands (like `noclip` and `gamespeed`) exposed in client-side scripts, UI nodes, or hotkeys without verifying `OS.is_debug_build()` allows players in production builds to manipulate global state, bypass collision limits, and cheat. All debug commands must be wrapped in environmental checks.
