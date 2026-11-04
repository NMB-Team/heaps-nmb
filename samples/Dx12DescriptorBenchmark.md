# D3D12 descriptor benchmark

Compile `samples/Dx12DescriptorBenchmark.hx` with `gfx_dx12`, `default_gfx_dx12`,
`dx12_descriptor_profile`, `limen`, `heaps` and `hl_ver=1.16.0`. Run:
`hl descriptors.hl result.json [--debug]`. Matching native modules are required.

The workload draws/retire 64 textures per frame for 120 frames, then idles for 60.
Sampler slots remain owned by the shared cache, preventing duplicate frees.
Scratch caches grow geometrically; shader-visible samplers are capped at 2,048.
Profiling compiles out without dx12_descriptor_profile.

## Recorded results

Windows HashLink/Limen, single-run observations with timer overhead. Bindless
handle allocation is exercised, but shader-side bindless indexing is not validated.

| Metric | Before | After |
|---|---:|---:|
| Native heap creations (render workload) | 10 | 10 |
| Heap resizes / cache growths (render workload) | 0 / 0 | 0 / 0 |
| Allocation calls / descriptors allocated | 31,084 / 31,084 | 31,084 / 31,084 |
| Allocation CPU time, total ms | 1.259 | 1.274 |
| Descriptor copy calls | 48,430 | 40,750 |
| Descriptors copied | 355,330 | 347,650 |
| Descriptor copy CPU time, total ms | 2.476 | 2.020 |
| Reset calls | 1,078 | 1,078 |
| Reset CPU time, total ms | 0.0446 | 0.0479 |
| Reserved descriptor slots at end | 14,336 | 14,336 |
| Unused slots at end | Invalid: 17,914 (duplicate frees) | 10,234 |
| Maximum individual heap high-water mark | 1,088 | 1,088 |

Separate native growth workload: a shader-visible SRV cache starts at 16 slots;
minimum capacity increases from 17 to 256. These heaps are never GPU-submitted.

| Metric | Exact growth | Geometric growth |
|---|---:|---:|
| Heap creations | 240 | 7 |
| CPU time including creation/release, ms | 92.836 | 2.873 |
| Final reserved bytes | 8,192 | 8,672 |

Counters are process-local and sampled before shutdown. Per-heap snapshots exclude
discarded caches; global creation totals include them. Peak cursor includes reserved
bindless slots, not just live resources. Reset timing excludes GPU waits.

Debug-requested runs completed, but the binding does not expose info-queue retrieval.
Resize, exhaustion and shader-side bindless use remain unverified. These captures
do not establish a representative frame-time improvement.
