# ############################################################################ #
# Copyright © 2018-present Paul Joannon
# Copyright © 2019-present Frédéric Maquin <fred@ephread.com>
# Licensed under the MIT License.
# See LICENSE in the project root for license information.
# ############################################################################ #

tool
extends Node

class_name InkPlayer

# ############################################################################ #
# Imports
# ############################################################################ #

var ErrorType = preload("res://addons/inkgd/runtime/enums/error.gd").ErrorType

var InkRuntime = load("res://addons/inkgd/runtime.gd")
var InkResource = load("res://addons/inkgd/editor/import_plugins/ink_resource.gd")
var InkStory = load("res://addons/inkgd/runtime/story.gd")
var InkFunctionResult = load("res://addons/inkgd/runtime/extra/function_result.gd")


# ############################################################################ #
# Signals
# ############################################################################ #

## Emitted when the ink runtime encountered an exception. Exception are
## usually not recoverable as they corrupt the state. `stack_trace` is
## an optional PoolStringArray containing a stack trace, for logging purposes.
signal exception_raised(message, stack_trace)

## Emitted when the _story encountered an error. These errors are usually
## recoverable.
signal error_encountered(message, type)

## Emitted with `true` when the runtime had loaded the JSON file and created
## the _story. If an error was encountered, `successfully` will be `false` and
## and error will appear Godot's output.
signal loaded(successfully)

## Emitted with the text and tags of the current line when the _story
## successfully continued.
signal continued(text, tags)

## Emitted when the player should pick a choice.
signal prompt_choices(choices)

## Emitted when a choice was reported back to the runtime.
signal choice_made(choice)

## Emitted when an external function is about to evaluate.
signal function_evaluating(function_name, arguments)

## Emitted when an external function evaluated.
signal function_evaluated(function_name, arguments, function_result)

## Emitted when a valid path string was choosen.
signal path_choosen(path, arguments)

## Emitted when the _story ended.
signal ended()


# ############################################################################ #
# Exported Properties
# ############################################################################ #

## The compiled Ink file (.json) to play.
export var ink_file: Resource

## When `true` the _story will be created in a separate threads, to
## prevent the UI from freezing if the _story is too big. Note that
## on platforms where threads aren't available, the value of this
## property is ignored.
export var loads_in_background: bool = true

## `true` to allow external function fallbacks, `false` otherwise. If this
## property is `false` and the appropriate function hasn't been binded, the
## _story will output an error.
export var allow_external_function_fallbacks: bool setget set_aeff, get_aeff
func set_aeff(value: bool):
	if _story == null:
		_push_null_story_error()
		return

	_story.allow_external_function_fallbacks = value
func get_aeff() -> bool:
	if _story == null:
		_push_null_story_error()
		return false

	return _story.allow_external_function_fallbacks

# skips saving global values that remain equal to the initial values that were
# declared in Ink.
export var do_not_save_default_values: bool setget set_dnsdv, get_dnsdv
func set_dnsdv(value: bool):
	var ink_runtime = _ink_runtime.get_ref()
	if ink_runtime == null:
		_push_null_runtime_error()
		return false

	ink_runtime.dont_save_default_values = value
func get_dnsdv() -> bool:
	var ink_runtime = _ink_runtime.get_ref()
	if ink_runtime == null:
		_push_null_runtime_error()
		return false

	return ink_runtime.dont_save_default_values

## Uses `assert` instead of `push_error` to report critical errors, thus
## making them more explicit during development.
export var stop_execution_on_exception: bool setget set_seoex, get_seoex
func set_seoex(value: bool):
	var ink_runtime = _ink_runtime.get_ref()
	if ink_runtime == null:
		_push_null_runtime_error()
		return

	ink_runtime.stop_execution_on_exception = value

# ############################################################################ #
# Properties
# ############################################################################ #

func get_seoex() -> bool:
	var ink_runtime = _ink_runtime.get_ref()
	if ink_runtime == null:
		_push_null_runtime_error()
		return false

	return ink_runtime.stop_execution_on_exception

## Uses `assert` instead of `push_error` to report _story errors, thus
## making them more explicit during development.
export var stop_execution_on_error: bool setget set_seoer, get_seoer
func set_seoer(value: bool):
	var ink_runtime = _ink_runtime.get_ref()
	if ink_runtime == null:
		_push_null_runtime_error()
		return

	ink_runtime.stop_execution_on_error = value

func get_seoer() -> bool:
	var ink_runtime = _ink_runtime.get_ref()
	if ink_runtime == null:
		_push_null_runtime_error()
		return false

	return ink_runtime.stop_execution_on_error


# ############################################################################ #
# Read-only Properties
# ############################################################################ #

## `true` if the _story can continue (i. e. is not expecting a choice to be
## choosen and hasn't reached the end).
var can_continue: bool setget , get_can_continue
func get_can_continue() -> bool:
	if _story == null:
		_push_null_story_error()
		return false

	return _story.can_continue


## The content of the current line.
var current_text: String setget , get_current_text
func get_current_text() -> String:
	if _story == null:
		_push_null_story_error()
		return ""

	if _story.current_text == null:
		_push_null_state_error("current_choices")
		return ""

	return _story.current_text


## The current choices. Empty is there are no choices for the current line.
var current_choices: Array setget , get_current_choices
func get_current_choices() -> Array:
	if _story == null:
		_push_null_story_error()
		return []

	if _story.current_choices == null:
		_push_null_state_error("current_choices")
		return []

	var text_choices = []
	for choice in _story.current_choices:
		text_choices.append(choice.text)

	return text_choices


## The current tags. Empty is there are no tags for the current line.
var current_tags: Array setget , get_current_tags
func get_current_tags() -> Array:
	if _story == null:
		_push_null_story_error()
		return []

	if _story.current_tags == null:
		_push_null_state_error("current_tags")
		return []

	return _story.current_tags


## The global tags for the _story. Empty if none have been declared.
var global_tags: Array setget , get_global_tags
func get_global_tags() -> Array:
	if _story == null:
		_push_null_story_error()
		return []

	return _story.global_tags

## `true` if the _story currently has choices, `false` otherwise.
var has_choices: bool setget , get_has_choices
func get_has_choices() -> bool:
	return !self.current_choices.empty()

## The name of the current flow.
var current_flow_name: String setget , get_current_flow_name
func get_current_flow_name() -> String:
	return _story.state.current_flow_name

# ############################################################################ #
# Private Properties
# ############################################################################ #

var _ink_runtime: WeakRef = WeakRef.new()
var _story: InkStory = null
var _thread: Thread
var _manages_runtime: bool = false


# ############################################################################ #
# Overrides
# ############################################################################ #

func _ready():
	call_deferred("_add_runtime")

func _exit_tree():
	call_deferred("_remove_runtime")


# ############################################################################ #
# Methods
# ############################################################################ #

## Creates the _story, based on the value of `ink_file`. The result of this
## method is reported through the 'story_loaded' signal.
func create_story() -> void:
	if ink_file == null:
		_push_error("'ink_file' is null, did Godot import the resource correctly?", ErrorType.ERROR)
		call_deferred("emit_signal", "loaded", false)
		return

	if !("json" in ink_file) || typeof(ink_file.json) != TYPE_STRING:
		_push_error(
				"'ink_file' doesn't have the appropriate resource type." + \
				"Are you sure you imported a JSON file?",
				ErrorType.ERROR
		)
		call_deferred("emit_signal", "loaded", false)
		return

	if loads_in_background && _current_platform_supports_threads():
		_thread = Thread.new()
		var error = _thread.start(self, "_async_create_story", ink_file.json)
		if error != OK:
			printerr("Could not start the thread: error code %d", error)
			emit_signal("loaded", true)
	else:
		_create_story(ink_file.json)
		_finalise_story_creation()


## Reset the Story back to its initial state as it was when it was
## first constructed.
func reset() -> void:
	if _story == null:
		_push_null_story_error()
		return

	_story.reset_state()


# ############################################################################ #
# Methods | Story Flow
# ############################################################################ #

## Continues the _story.
func continue_story() -> String:
	if _story == null:
		_push_null_story_error()
		return ""

	var text: String = ""
	if self.can_continue:
		_story.continue()

		text = self.current_text

	elif self.has_choices:
		emit_signal("prompt_choices", self.current_choices)
	else:
		emit_signal("ended")

	return text


## Chooses a choice. If the _story is not currently expected choices or
## the index is out of bounds, this method does nothing.
func choose_choice_index(index: int) -> void:
	if _story == null:
		_push_null_story_error()
		return

	if index >= 0 && index < self.current_choices.size():
		_story.choose_choice_index(index);


## Moves the _story to the specified knot/stitch/gather. This method
## will throw an error through the 'exception' signal if the path string
## does not match any known path.
func choose_path(path: String) -> void:
	if _story == null:
		_push_null_story_error()
		return

	_story.choose_path_string(path)


## Switches the flow, creating a new flow if it doesn't exist.
func switch_flow(flow_name: String) -> void:
	if _story == null:
		_push_null_story_error()
		return

	_story.switch_flow(flow_name)


## Switches the the default flow.
func switch_to_default_flow() -> void:
	if _story == null:
		_push_null_story_error()
		return

	_story.switch_to_default_flow()


## Remove the given flow.
func remove_flow(flow_name: String) -> void:
	if _story == null:
		_push_null_story_error()
		return

	_story.remove_flow(flow_name)


# ############################################################################ #
# Methods | Tags
# ############################################################################ #

## Returns the tags declared at the given path.
func tags_for_content_at_path(path: String) -> Array:
	if _story == null:
		_push_null_story_error()
		return []

	return _story.tags_for_content_at_path(path)


# ############################################################################ #
# Methods | Visit Count
# ############################################################################ #

## Returns the visit count of the given path.
func visit_count_at_path(path: String) -> int:
	if _story == null:
		_push_null_story_error()
		return 0

	return _story.visit_count_at_path(path)


# ############################################################################ #
# Methods | State Management
# ############################################################################ #

## Gets the current state as a JSON string. It can then be saved somewhere.
func get_state() -> String:
	if _story == null:
		_push_null_story_error()
		return ""

	return _story.state.to_json()


## Sets the state from a JSON string.
func set_state(state: String):
	if _story == null:
		_push_null_story_error()
		return

	_story.state.load_json(state)


## Saves the current state to the given path.
func save_state_to_path(path: String):
	if _story == null:
		_push_null_story_error()
		return

	if !path.begins_with("res://") && !path.begins_with("user://"):
		path = "user://%s" % path

	var file = File.new()
	file.open(path, File.WRITE)
	save_state_to_file(file)
	file.close()


## Saves the current state to the file.
func save_state_to_file(file: File):
	if _story == null:
		_push_null_story_error()
		return

	if file.is_open():
		file.store_string(get_state())


## Loads the state from the given path.
func load_state_from_path(path: String):
	if _story == null:
		_push_null_story_error()
		return

	if !path.begins_with("res://") && !path.begins_with("user://"):
		path = "user://%s" % path

	var file = File.new()
	file.open(path, File.READ)
	load_state_from_file(file)
	file.close()


## Loads the state from the given file.
func load_state_from_file(file: File):
	if _story == null:
		_push_null_story_error()
		return

	if !file.is_open():
		return

	file.seek(0);
	if file.get_len() > 0:
		_story.state.load_json(file.get_as_text())


# ############################################################################ #
# Methods | Variables
# ############################################################################ #

## Returns the value of variable named 'name' or 'null' if it doesn't exist.
func get_variable(name: String):
	if _story == null:
		_push_null_story_error()
		return null

	return _story.variables_state.get(name)


## Sets the value of variable named 'name'.
func set_variable(name: String, value):
	if _story == null:
		_push_null_story_error()
		return

	_story.variables_state.set(name, value)


# ############################################################################ #
# Methods | Variable Observers
# ############################################################################ #

## Registers an observer for the given variables.
func observe_variables(variable_names: Array, object: Object, method_name: String):
	if _story == null:
		_push_null_story_error()
		return

	_story.observe_variables(variable_names, object, method_name)


## Registers an observer for the given variable.
func observe_variable(variable_name: String, object: Object, method_name: String):
	if _story == null:
		_push_null_story_error()
		return

	_story.observe_variable(variable_name, object, method_name)


## Removes an observer for the given variable name. This method is highly
## specific and will only remove one observer.
func remove_variable_observer(object: Object, method_name: String, specific_variable_name: String):
	if _story == null:
		_push_null_story_error()
		return

	_story.remove_variable_observer(object, method_name, specific_variable_name)


## Removes all observers registered with the couple object/method_name,
## regardless of which variable they observed.
func remove_variable_observer_for_all_variable(object: Object, method_name: String):
	if _story == null:
		_push_null_story_error()
		return

	_story.remove_variable_observer(object, method_name)


## Removes all observers observing the given variable.
func remove_all_variable_observers(specific_variable_name: String):
	if _story == null:
		_push_null_story_error()
		return

	_story.remove_variable_observer(specific_variable_name)


# ############################################################################ #
# Methods | External Functions
# ############################################################################ #

## Binds an external function.
func bind_external_function(
		func_name: String,
		object: Object,
		method_name: String,
		lookahead_safe = false
):
	if _story == null:
		_push_null_story_error()
		return

	_story.bind_external_function(func_name, object, method_name, lookahead_safe)


## Unbinds an external function.
func unbind_external_function(func_name: String):
	if _story == null:
		_push_null_story_error()
		return

	_story.unbind_external_function(func_name)


# ############################################################################ #
# Methods | Functions
# ############################################################################ #

## Evaluate a given ink function, returning its return value (but not
## its output).
func evaluate_function(function_name: String, arguments = []) -> InkFunctionResult:
	if _story == null:
		_push_null_story_error()
		return null

	var result = _story.evaluate_function(function_name, arguments, true)
	return InkFunctionResult.new(result["output"], result["result"])

# ############################################################################ #
# Methods | Ink List Creation
# ############################################################################ #

## Creates a new empty InkList that's intended to hold items from a particular
## origin list definition.
func create_ink_list_with_origin(single_origin_list_name: String) -> InkList:
	return InkList.new_with_origin(single_origin_list_name, _story)

## Creates a new InkList from the name of a preexisting item.
func create_ink_list_from_item_name(item_name: String) -> InkList:
	return InkList.from_string(item_name, _story)


# ############################################################################ #
# Private Methods | Signal Forwarding
# ############################################################################ #

func _exception_raised(message, stack_trace):
	emit_signal("exception_raised", message, stack_trace)


func _on_error(message, type):
	if get_signal_connection_list("error_encountered").size() == 0:
		_push_error(message, type)
	else:
		emit_signal("error_encountered", message, type)


func _on_did_continue():
	emit_signal("continued", self.current_text, self.current_tags)


func _on_make_choice(choice):
	emit_signal("choice_made", choice.text)


func _on_evaluate_function(function_name, arguments):
	emit_signal("function_evaluating", function_name, arguments)


func _on_complete_evaluate_function(function_name, arguments, text_output, return_value):
	var function_result = InkFunctionResult.new(text_output, return_value)
	emit_signal("function_evaluated", function_name, arguments, function_result)


func _on_choose_path_string(path, arguments):
	emit_signal("path_choosen", path, arguments)


# ############################################################################ #
# Private Methods
# ############################################################################ #

func _create_story(json_story):
	_story = InkStory.new(json_story)


func _async_create_story(json_story):
	_create_story(json_story)
	call_deferred("_async_creation_completed")


func _async_creation_completed():
	_thread.wait_to_finish()
	_thread = null

	_finalise_story_creation()


func _finalise_story_creation():
	_story.connect("on_error", self, "_on_error")
	_story.connect("on_did_continue", self, "_on_did_continue")
	_story.connect("on_make_choice", self, "_on_make_choice")
	_story.connect("on_evaluate_function", self, "_on_evaluate_function")
	_story.connect("on_complete_evaluate_function", self, "_on_complete_evaluate_function")
	_story.connect("on_choose_path_string", self, "_on_choose_path_string")

	var ink_runtime = _ink_runtime.get_ref()
	if ink_runtime == null:
		_push_null_runtime_error()
		return

	emit_signal("loaded", true)


func _add_runtime():
	# The InkRuntime is normaly an auto-loaded singleton,
	# but if it's not present, it's added here.
	var runtime = get_tree().root.get_node("__InkRuntime")
	if runtime == null:
		_manages_runtime = true
		runtime = InkRuntime.init(get_tree().root)

	runtime.connect("exception_raised", self, "_exception_raised")

	_ink_runtime = weakref(runtime)


func _remove_runtime():
	if _manages_runtime:
		InkRuntime.deinit(get_tree().root)


func _current_platform_supports_threads():
	return OS.get_name() != "HTML5"


func _push_null_runtime_error():
	_push_error(
			"InkRuntime could not found, did you remove it from the tree?",
			ErrorType.ERROR
	)


func _push_null_story_error():
	_push_error("The _story is 'Nil', was it loaded properly?", ErrorType.ERROR)


func _push_null_state_error(variable: String):
	var message = (
			"'%s' is 'Nil', the internal state is corrupted or missing, " +
			"this is an unrecoverable error."
	)
	_push_error(message % variable, ErrorType.ERROR)


func _push_error(message: String, type: int):
	if Engine.editor_hint:
		match type:
			ErrorType.ERROR: printerr(message)
			ErrorType.WARNING: print(message)
			ErrorType.AUTHOR: print(message)
	else:
		match type:
			ErrorType.ERROR: push_error(message)
			ErrorType.WARNING: push_warning(message)
			ErrorType.AUTHOR: push_warning(message)
