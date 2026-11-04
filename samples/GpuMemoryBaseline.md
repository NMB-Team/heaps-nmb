# GPU allocation benchmark

```powershell
haxe -lib heaps -cp . -cp samples -lib limen -D gfx_vulkan -D default_gfx_vulkan -D gpu_memory_benchmark -D hl_ver=1.16.0 -main GpuMemoryBaseline -hl gpu-memory-vulkan.hl
hl gpu-memory-vulkan.hl baseline-vulkan.json
haxe -lib heaps -cp . -cp samples -lib limen -D gfx_dx12 -D default_gfx_dx12 -D gpu_memory_benchmark -D hl_ver=1.16.0 -main GpuMemoryBaseline -hl gpu-memory-dx12.hl
hl gpu-memory-dx12.hl baseline-dx12.json
```

Vulkan requires a VMA-enabled Limen runtime. D3D12 defaults to legacy allocation;
add `gfx_d3d12ma` for the managed path and use matching native modules.

Five workloads run in order: 2,048 3-KiB buffers; 1,024 32x32 RGBA8 textures;
eight 2048x2048 textures; 256 64x64 textures recreated every 30 frames; and
32 buffers plus 32 textures recreated every frame. Each has 60 warmup, 180
workload and 61 observation frames. No asset upload or shading is measured.

Run fresh processes at least three times with identical GPU/driver, presentation,
power and background load. Record revisions and environment; require completed JSON.
Keep raw results/binaries out of Git. Historical Vulkan legacy comparisons require
an earlier revision. See GpuAllocatorComparison.md for recorded measurements.

Managed used/reserved bytes cover allocator ranges/backing, including deferred
owners. Legacy D3D12 reports only its placed-texture pool; managed D3D12 covers
more resources, so those totals are not equivalent. OS usage is sampled budget
usage, not physical residency. Peaks are sampled, not guaranteed instantaneous maxima.

Constructor CPU time includes engine/native creation, excluding snapshots, disposal
and GPU completion. Throughput is constructor count divided by that time. Mean/P99
frames include presentation and diagnostics. Statistics traversal affects timing.
Unavailable cumulative native block counters are null; live blocks are snapshots.
