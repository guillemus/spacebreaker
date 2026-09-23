package main_web

import game "../game"
import "base:runtime"
import "core:mem"

@(private = "file")
web_context: runtime.Context

main :: proc() {}

@(export)
main_start :: proc "c" (width, height: i32) {
	context = runtime.default_context()
	context.allocator = web_allocator()
	runtime.init_global_temporary_allocator(4 * mem.Megabyte)
	web_context = context
	game.init(width, height)
}

@(export)
main_update :: proc "c" () {
	context = web_context
	game.frame()
}

@(export)
main_blur :: proc "c" () {
	context = web_context
	game.on_blur()
}
