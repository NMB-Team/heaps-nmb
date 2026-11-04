# D3D12 transfer benchmark

Compile `samples/Dx12TransferBenchmark.hx` with `gfx_dx12`, `default_gfx_dx12`,
`gpu_memory_benchmark`, `limen`, `heaps` and `hl_ver=1.16.0`. Run:
`hl transfer.hl result.json [--trim] [--debug]`. Add gfx_d3d12ma for managed resources.
The historical A/B transfer-policy define was removed; use the earlier revision
for its baseline. Synchronization fixes remain in the current implementation.

Upload pages stay committed and persistently mapped. Pending-copy byte accounting
is incremental. Async readback caches at most 16 MiB and expires after 120 idle
frames; oversized resources are released after completion. UPLOAD_CACHE_IDLE_FRAMES
is zero by default; --trim sets 120. Trimming waits until frame-fenced blocks are free.

The 300-frame workload checks synchronous buffer/texture contents and ten asynchronous
readbacks, uploads 128 buffers/textures per active frame, and streams a 576 MiB burst.
It retains source resources until callbacks complete and shuts down the driver.

## Recorded results

Windows x64, RTX 4070 Ti, driver 32.0.16.1742; three sequential processes per policy.
Refresh/power/CPU/OS were uncontrolled; no debug-layer cleanliness was established.
All byte comparisons passed. Native upload-page creations stayed at eight. Async
resource creations/destructions fell from 10/10 to 1/1. Timing medians:

| Policy | Upload CPU ms | Mean frame ms | P99 frame ms |
|---|---:|---:|---:|
| Comparison | 348.884 | 6.057 | 6.082 |
| Final default | 335.690 | 6.038 | 6.354 |

Default upload reservation remained 496 MiB after the burst. Opt-in trimming settled
at 16 MiB but increased median P99 to 9.206 ms (comparison: 6.082 ms); one capture
attributed a 30.187 ms frame to page release. This is why trimming remains disabled.
Dynamic buffers retained 32 MiB; the async cache expired to zero.

Frame times include polling, destruction and diagnostics. These short captures do
not prove a speedup, long-term stability or correctness during concurrent source
writes/disposal, resize or device loss.
