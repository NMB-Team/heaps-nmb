# GPU allocator comparison — 2026-11-04

Historical comparison: the legacy Vulkan implementation was subsequently removed
by explicit user decision after validation. Current Vulkan builds always use VMA;
reproducing the legacy rows requires the earlier revision. Measurements and their
limitations below are unchanged; removal does not establish a performance win.

## Decision

Keep both optional allocators disabled by default and preserve both legacy paths. No production allocation policy was changed. These exploratory runs do not establish a performance win.

## Environment and method

Windows x64; NVIDIA GeForce RTX 4070 Ti, Windows driver 32.0.16.1742 (reported by D3D12). Vulkan reports API 1.4.351, vendor 0x10DE, device 0x2782, encoded driver -1706393600. Native Release builds use Visual Studio 18 2026/MSVC, C/C++23 and the existing Release optimization/LTO settings. Limen revision 2874ec4; heaps-nmb revision a6054362 plus the benchmark reporting fix. VMA 3.3.0 and D3D12MA 3.1.0. Haxe uses hl_ver=1.16.0 and gpu_memory_benchmark, the appropriate gfx/default_gfx backend defines and optionally gfx_vma or gfx_d3d12ma.

Three fresh processes per path ran the existing GpuMemoryBaseline workloads: 2,048 3-KiB buffers; 1,024 32x32 RGBA8 textures; eight 2048x2048 textures; 256 64x64 textures recreated every 30 frames; 32 buffers plus 32 64x64 textures recreated every frame. Each scenario uses 60 warmup, 180 workload and 61 observation frames, in the original order. No uploads/shading workload was added. Presentation/window/power settings were left at application/system defaults and were not independently captured. CPU/OS build and refresh/power details were not captured. Builds overlapped these runs: timings are exploratory, unsuitable for acceptance decisions.

Local raw results: `I:/Projects/hlsdl-nmb/build/allocator-review-runtime/{dx12,dx12ma,vulkan,vma}-{1,2,3}.json`. Pre-existing untracked baseline JSON files were preserved and excluded. Median of three runs is shown, MiB = 1,048,576 bytes. OS usage is a sampled budget-query value, not physical VRAM residency.

## Results

| Path | Scenario | Peak used MiB | Peak reserved MiB | Peak OS local MiB | Constructor CPU ms | Resources/s | Mean frame ms | P99 frame ms |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| dx12 | small_buffers | 0.000 | 0.000 | 31.504 | 477.850 | 4285.862 | 8.357 | 5.875 |
| dx12 | small_textures | 4.000 | 16.000 | 39.504 | 11.105 | 92214.172 | 5.555 | 6.095 |
| dx12 | large_textures | 0.000 | 16.000 | 167.504 | 6.713 | 1191.648 | 5.556 | 8.606 |
| dx12 | repeated | 4.000 | 16.000 | 39.504 | 16.327 | 94075.099 | 5.645 | 11.022 |
| dx12 | churn | 0.500 | 16.000 | 39.879 | 1459.629 | 7892.416 | 11.057 | 16.368 |
| dx12ma | small_buffers | 128.250 | 136.000 | 39.254 | 529.058 | 3871.033 | 8.796 | 6.254 |
| dx12ma | small_textures | 4.250 | 8.000 | 31.254 | 15.978 | 64088.685 | 5.671 | 6.889 |
| dx12ma | large_textures | 128.250 | 168.000 | 191.254 | 7.125 | 1122.860 | 5.555 | 7.376 |
| dx12ma | repeated | 4.250 | 40.000 | 63.254 | 21.304 | 72097.888 | 5.556 | 7.797 |
| dx12ma | churn | 6.750 | 14.000 | 31.629 | 1489.273 | 7735.317 | 11.344 | 18.436 |
| vulkan | small_buffers | 20.109 | 44.000 | 77.680 | 3.853 | 531555.358 | 5.557 | 6.614 |
| vulkan | small_textures | 18.109 | 44.000 | 77.680 | 6.070 | 168688.084 | 5.559 | 7.040 |
| vulkan | large_textures | 142.109 | 204.000 | 237.680 | 1.117 | 7163.628 | 5.557 | 7.325 |
| vulkan | repeated | 18.109 | 76.000 | 109.680 | 6.505 | 236142.913 | 5.556 | 7.967 |
| vulkan | churn | 14.703 | 76.000 | 109.680 | 43.965 | 262027.430 | 5.556 | 8.270 |
| vma | small_buffers | 20.109 | 96.000 | 100.117 | 5.258 | 389530.863 | 5.555 | 6.917 |
| vma | small_textures | 18.109 | 96.000 | 100.117 | 6.323 | 161958.117 | 5.606 | 17.334 |
| vma | large_textures | 142.109 | 288.000 | 292.117 | 0.934 | 8564.174 | 5.559 | 17.615 |
| vma | repeated | 18.109 | 160.000 | 164.117 | 7.987 | 192317.709 | 5.557 | 17.931 |
| vma | churn | 14.703 | 96.000 | 100.117 | 40.690 | 283114.967 | 5.555 | 17.765 |

## Interpretation and limits

Legacy D3D12 managed bytes cover only its placed texture pool. D3D12MA covers managed buffers and ordinary sampled textures, including deferred releases; comparing those byte totals directly is invalid. Large legacy committed textures and buffers are absent from legacy pool totals. VMA and legacy Vulkan cover all four memory classes, making their managed totals comparable. VMA reserved more memory in these workloads; its four independent allocator instances and their retained blocks warrant a controlled pool-size investigation. No automatic defragmentation or aliasing was enabled.

CPU times include resource constructors and bookkeeping, not isolated allocator search time. Throughput is successful constructors divided by constructor CPU time; frame timings include presentation, diagnostics and scheduling. D3D12MA statistics additionally traverse managed textures, and VMA statistics traverse allocator state several times per snapshot. Instrumentation differs in cost. Apparent timing changes cannot be attributed solely to allocator implementation. Native cumulative block creation/destruction counts are unavailable for VMA/D3D12MA. Live block snapshots are now supported; the first D3D12MA run predates that additive field and is excluded from block-count comparisons.

## Native block observations

Peak live block counts per run, median across available runs. D3D12MA uses runs 2–3; VMA uses three runs. Legacy Vulkan binaries were compiled before the live-block field was added, so that field is unavailable in these captures. Legacy D3D12 cumulative heap counters cannot substitute for live counts.

| Scenario | Vulkan legacy | VMA | D3D12MA |
|---|---:|---:|---:|
| small_buffers | unavailable | 3 | 2049 |
| small_textures | unavailable | 3 | 1 |
| large_textures | unavailable | 5 | 4 |
| repeated | unavailable | 4 | 2 |
| churn | unavailable | 3 | 97 |

D3D12MA small buffers reached 2,049 native blocks despite only about 128 MiB used. Inspect committed-versus-placed decisions and heap compatibility in a controlled capture before changing allocation flags. This observation is a follow-up target, not evidence for a particular policy fix.
