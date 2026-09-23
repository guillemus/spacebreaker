package main_web

import "core:c"
import "core:mem"

// Odin's default js allocator grows wasm memory on its own, which would fight
// emscripten's sbrk. Route everything through emscripten's libc instead.
@(default_calling_convention = "c")
foreign {
	@(link_name = "calloc")
	c_calloc :: proc(num, size: c.size_t) -> rawptr ---
	@(link_name = "malloc")
	c_malloc :: proc(size: c.size_t) -> rawptr ---
	@(link_name = "realloc")
	c_realloc :: proc(ptr: rawptr, size: c.size_t) -> rawptr ---
	@(link_name = "free")
	c_free :: proc(ptr: rawptr) ---
}

web_allocator :: proc "contextless" () -> mem.Allocator {
	return mem.Allocator{web_allocator_proc, nil}
}

web_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	switch mode {
	case .Alloc:
		ptr := c_calloc(1, c.size_t(size))
		if ptr == nil {
			return nil, .Out_Of_Memory
		}
		return mem.byte_slice(ptr, size), nil
	case .Alloc_Non_Zeroed:
		ptr := c_malloc(c.size_t(size))
		if ptr == nil {
			return nil, .Out_Of_Memory
		}
		return mem.byte_slice(ptr, size), nil
	case .Free:
		c_free(old_memory)
		return nil, nil
	case .Resize, .Resize_Non_Zeroed:
		ptr := c_realloc(old_memory, c.size_t(size))
		if ptr == nil {
			return nil, .Out_Of_Memory
		}
		if mode == .Resize && size > old_size {
			mem.zero(rawptr(uintptr(ptr) + uintptr(old_size)), size - old_size)
		}
		return mem.byte_slice(ptr, size), nil
	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Resize, .Resize_Non_Zeroed, .Query_Features}
		}
		return nil, nil
	case .Free_All, .Query_Info:
		return nil, .Mode_Not_Implemented
	}
	return nil, .Mode_Not_Implemented
}
