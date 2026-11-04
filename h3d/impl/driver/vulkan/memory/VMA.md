# Vulkan memory

Vulkan always uses VMA through Limen. No allocator-selection define is needed.
Build Limen with `LIMEN_BUILD_VMA=ON` and deploy matching `limen.hdll` and
`vulkan.limen`. Existing native caches may retain an old OFF setting.

Four allocator instances isolate device buffers, device images, uploads and
readbacks. Heaps owns Vulkan objects and submission tracking; destroy objects
before releasing their allocations. Allocator disposal rejects live allocations.
Host-visible allocations stay mapped until retirement. Mapped pointers and cache
ranges are allocation-relative; VMA handles non-coherent atom alignment.

Upload pages reset after frame completion, expiring after 120 frame-slot reuses
(8 for oversized pages). Readback buffers expire after 120 idle renderer frames;
the idle cache is capped at 32 MiB. Buffer capacities exclude VMA block slack.

Compile `tests/vulkan-memory-diagnostic.hxml`; run with `--stress` for 2,048
frames and `--validation` to require Khronos validation. The diagnostic checks
full upload/readback contents and explicitly shuts down the driver. For portable
layers set `VK_LAYER_PATH`; use `VK_LAYER_VALIDATE_SYNC=1` for synchronization
validation. Require the final frame summary and check stderr, not just exit status.

See Limen `GPU_MEMORY_ARCHITECTURE.md` for native ownership and limitations.
