# ------------------------------------------------------------------------------
# Interface and some basic functionality for all printers.
# ------------------------------------------------------------------------------
class GutPrinter:
	var _format_enabled: bool = true
	var _disabled: bool = false
	var _printer_name: String = "NOT SET"
	var _show_name: Variant = false  # used for debugging, set manually

	func get_format_enabled() -> Variant:
		return _format_enabled

	func set_format_enabled(format_enabled: Variant) -> void:
		_format_enabled = format_enabled

	func send(text: Variant, fmt: Variant = null) -> void:
		if _disabled:
			return

		var formatted: Variant = text
		if fmt != null and _format_enabled:
			formatted = format_text(text, fmt)

		if _show_name:
			formatted = str("(", _printer_name, ")") + formatted

		_output(formatted)

	func get_disabled() -> Variant:
		return _disabled

	func set_disabled(disabled: Variant) -> void:
		_disabled = disabled

	# --------------------
	# Virtual Methods (some have some default behavior)
	# --------------------
	func _output(text: Variant) -> void:
		pass

	func format_text(text: Variant, fmt: Variant) -> Variant:
		return text


# ------------------------------------------------------------------------------
# Responsible for sending text to a GUT gui.
# ------------------------------------------------------------------------------
class GutGuiPrinter:
	extends GutPrinter
	var _textbox: Variant = null

	var _colors: Variant = {
		red = Color.RED, yellow = Color.YELLOW, green = Color.GREEN, blue = Color.BLUE
	}

	func _init() -> void:
		_printer_name = "gui"

	func _wrap_with_tag(text: Variant, tag: Variant) -> Variant:
		return str("[", tag, "]", text, "[/", tag, "]")

	func _color_text(text: Variant, c_word: Variant) -> Variant:
		return "[color=" + c_word + "]" + text + "[/color]"

	# Remember, we have to use push and pop because the output from the tests
	# can contain [] in it which can mess up the formatting.  There is no way
	# as of 3.4 that you can get the bbcode out of RTL when using push and pop.
	#
	# The only way we could get around this is by adding in non-printable
	# whitespace after each "[" that is in the text.  Then we could maybe do
	# this another way and still be able to get the bbcode out, or generate it
	# at the same time in a buffer (like we tried that one time).
	#
	# Since RTL doesn't have good search and selection methods, and those are
	# really handy in the editor, it isn't worth making bbcode that can be used
	# there as well.
	#
	# You'll try to get it so the colors can be the same in the editor as they
	# are in the output.  Good luck, and I hope I typed enough to not go too
	# far that rabbit hole before finding out it's not worth it.
	func format_text(text: Variant, fmt: Variant) -> Variant:
		if _textbox == null:
			return

		if fmt == "bold":
			_textbox.push_bold()
		elif fmt == "underline":
			_textbox.push_underline()
		elif _colors.has(fmt):
			_textbox.push_color(_colors[fmt])
		else:
			# just pushing something to pop.
			_textbox.push_normal()

		_textbox.add_text(text)
		_textbox.pop()

		return ""

	func _output(text: Variant) -> void:
		if _textbox == null:
			return

		_textbox.add_text(text)

	func get_textbox() -> Variant:
		return _textbox

	func set_textbox(textbox: Variant) -> void:
		_textbox = textbox

	# This can be very very slow when the box has a lot of text.
	func clear_line() -> void:
		_textbox.remove_line(_textbox.get_line_count() - 1)
		_textbox.queue_redraw()

	func get_bbcode() -> Variant:
		return _textbox.text

	func get_disabled() -> Variant:
		return _disabled and _textbox != null


# ------------------------------------------------------------------------------
# This AND TerminalPrinter should not be enabled at the same time since it will
# result in duplicate output.  printraw does not print to the console so i had
# to make another one.
# ------------------------------------------------------------------------------
class GutConsolePrinter:
	extends GutPrinter
	var _buffer: String = ""

	func _init() -> void:
		_printer_name = "console"

	# suppresses output until it encounters a newline to keep things
	# inline as much as possible.
	func _output(text: Variant) -> void:
		if text.ends_with("\n"):
			print(_buffer + text.left(text.length() - 1))
			_buffer = ""
		else:
			_buffer += text


# ------------------------------------------------------------------------------
# Prints text to terminal, formats some words.
# ------------------------------------------------------------------------------
class GutTerminalPrinter:
	extends GutPrinter

	var escape: PackedByteArray = PackedByteArray([0x1b]).get_string_from_ascii()
	var cmd_colors: Variant = {
		red = escape + "[31m",
		yellow = escape + "[33m",
		green = escape + "[32m",
		blue = escape + "[34m",
		underline = escape + "[4m",
		bold = escape + "[1m",
		default = escape + "[0m",
		clear_line = escape + "[2K"
	}

	func _init() -> void:
		_printer_name = "terminal"

	func _output(text: Variant) -> void:
		# Note, printraw does not print to the console.
		printraw(text)

	func format_text(text: Variant, fmt: Variant) -> Variant:
		return cmd_colors[fmt] + text + cmd_colors.default

	func clear_line() -> void:
		send(cmd_colors.clear_line)

	func back(n: Variant) -> void:
		send(escape + str("[", n, "D"))

	func forward(n: Variant) -> void:
		send(escape + str("[", n, "C"))
