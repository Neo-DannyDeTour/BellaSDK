sed -i 's/var dock/var dock: Node/' ./addons/KGB_Agent/kgb_plugin.gd
sed -i 's/var data/var data: Dictionary/' ./addons/renderdoc_launcher/renderdoc_launcher.gd
sed -i 's/func _on_http_request_completed(result, response_code, _headers, body) -> void:/func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:/' ./addons/KGB_Agent/kgb_dock.gd
