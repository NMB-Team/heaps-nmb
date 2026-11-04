//TARGETS=hl,hldx11,hldx12,hlvulkan
//PARAM=-D gpu_memory_benchmark

#if !gpu_memory_benchmark
#error "Build with -D gpu_memory_benchmark"
#end

class GpuMemoryBaseline extends hxd.App {

	var scenario = 0;
	var frame = -60;
	var previous = 0.;
	var times:Array<Float> = [];
	var buffers:Array<h3d.Buffer> = [];
	var textures:Array<h3d.mat.Texture> = [];
	var rows:Array<Dynamic> = [];
	var samples:Array<Dynamic> = [];
	var allocations = 0;
	var deallocations = 0;
	var allocationMs = 0.;
	var peakUsed:Null<Float>;
	var peakReserved:Null<Float>;
	var peakOs:Null<Float>;
	var initial:Dynamic;
	final names = ["small_buffers", "small_textures", "large_textures", "repeated", "churn"];

	function snapshot(queryOs = true):Dynamic {
		var used:Null<Float> = null;
		var reserved:Null<Float> = null;
		var os:Null<Float> = null;
		var budget:Null<Float> = null;
		var blocks:Null<Int> = null;
		var destroyed:Null<Int> = null;
		var live:Null<Int> = null;
		var liveBlocks:Null<Int> = null;
		var scope = "unavailable";
		#if gfx_vulkan
		if (Std.isOfType(engine.driver, h3d.impl.driver.vulkan.VulkanDriver)) {
			final d:h3d.impl.driver.vulkan.VulkanDriver = cast engine.driver;
			final a = @:privateAccess d.allocator;
			used = hxd.Math.int64ToFloat(a.usedBytes);
			reserved = hxd.Math.int64ToFloat(a.reservedBytes);
			live = a.allocationCount;
			liveBlocks = a.getBlockCount();
			scope = "vulkan_all_memory_classes";
			final ctx = @:privateAccess d.ctx;
			if (queryOs && ctx.hasMemoryBudget()) {
				os = 0.;
				budget = 0.;
				for (i in 0...ctx.getMemoryHeapCount()) {
					if ((ctx.getMemoryHeapFlags(i) & 1) == 0) continue;
					final info = new limen.graphics.renderer.vulkan.memory.Memory.VkMemoryHeapBudgetInfo();
					ctx.getMemoryHeapBudget(i, info);
					os += hxd.Math.int64ToFloat((info.usage : haxe.Int64));
					budget += hxd.Math.int64ToFloat((info.budget : haxe.Int64));
				}
			}
		}
		#end
		#if gfx_dx12
		if (Std.isOfType(engine.driver, h3d.impl.driver.dx12.DX12Driver)) {
			final d:h3d.impl.driver.dx12.DX12Driver = cast engine.driver;
			#if (gfx_d3d12ma && !console)
			final stats = d.getManagedMemoryStatistics();
			used = hxd.Math.int64ToFloat(stats.allocationBytes);
			reserved = hxd.Math.int64ToFloat(stats.blockBytes);
			live = stats.allocations;
			liveBlocks = stats.blocks;
			scope = "dx12_d3d12ma_buffers_and_sampled_textures";
			#else
			final a = @:privateAccess d.textureAlloc;
			if (a != null) {
				used = a.getUsedSize();
				reserved = a.getTotalSize();
			}
			blocks = @:privateAccess h3d.impl.driver.dx12.memory.TextureMemoryType.benchmarkHeapCreations;
			destroyed = @:privateAccess h3d.impl.driver.dx12.memory.TextureMemoryType.benchmarkHeapDestructions;
			scope = "dx12_placed_texture_pool_only";
			#end
			#if !xbox
			if (queryOs) {
				final info = new limen.graphics.renderer.d3d12.internal.D3D12Bindings.QueryVideoMemoryInfo();
				limen.graphics.renderer.d3d12.internal.D3D12Bindings.queryVideoMemoryInfo(0, info);
				os = hxd.Math.int64ToFloat(info.currentUsage);
				budget = hxd.Math.int64ToFloat(info.budget);
			}
			#end
		}
		#end
		return {managed_scope: scope, managed_used_bytes: used, managed_reserved_bytes: reserved,
			os_local_usage_bytes: os, os_local_budget_bytes: budget, native_block_creations: blocks, native_block_destructions: destroyed, native_live_allocations: live, native_live_blocks: liveBlocks};
	}

	function sample(queryOs = false) {
		final s = snapshot(queryOs);
		if (s.managed_used_bytes != null && (peakUsed == null || s.managed_used_bytes > peakUsed)) peakUsed = s.managed_used_bytes;
		if (s.managed_reserved_bytes != null && (peakReserved == null || s.managed_reserved_bytes > peakReserved)) peakReserved = s.managed_reserved_bytes;
		if (s.os_local_usage_bytes != null && (peakOs == null || s.os_local_usage_bytes > peakOs)) peakOs = s.os_local_usage_bytes;
		return s;
	}

	function create(count:Int, size:Int, buffer:Bool) {
		for (_ in 0...count) {
			final start = haxe.Timer.stamp();
			if (buffer) buffers.push(new h3d.Buffer(256, hxd.BufferFormat.POS3D));
			else textures.push(new h3d.mat.Texture(size, size, [], RGBA));
			allocationMs += (haxe.Timer.stamp() - start) * 1000.;
			allocations++;
			sample();
		}
	}

	function release() {
		for (b in buffers) { b.dispose(); deallocations++; }
		for (t in textures) { t.dispose(); deallocations++; }
		buffers = [];
		textures = [];
	}

	override function update(dt:Float) {
		final now = haxe.Timer.stamp();
		if (frame > 0) times.push((now - previous) * 1000.);
		previous = now;
		if (frame < 0) { frame++; return; }
		if (frame == 0) initial = snapshot();
		if (frame < 180) {
			switch (scenario) {
				case 0: if (frame == 0) create(2048, 0, true);
				case 1: if (frame == 0) create(1024, 32, false);
				case 2: if (frame == 0) create(8, 2048, false);
				case 3: if (frame % 30 == 0) { release(); create(256, 64, false); }
				case 4: release(); create(32, 0, true); create(32, 64, false);
			}
		} else if (frame == 180) release();
		final s = sample(true);
		samples.push({frame: frame, memory: s});
		if (frame++ < 240) return;
		var sum = 0.;
		for (t in times) sum += t;
		times.sort(Reflect.compare);
		rows.push({scenario: names[scenario], frames: times.length, frame_average_ms: sum / times.length,
			frame_p99_ms: times[Math.ceil(times.length * 0.99) - 1], resource_allocations: allocations,
			resource_deallocations: deallocations, resource_allocation_cpu_ms: allocationMs,
			peak_managed_used_bytes: peakUsed, peak_managed_reserved_bytes: peakReserved, peak_os_local_usage_bytes: peakOs,
			initial: initial, final_memory: s, samples: samples});
		if (++scenario == names.length) {
			final args = Sys.args();
			final output = args.length == 0 ? "gpu-memory-baseline.json" : args[0];
			sys.io.File.saveContent(output, haxe.Json.stringify({schema_version: 1, backend: engine.driver.getDriverName(true), scenarios: rows}, null, "\t"));
			Sys.println('Saved $output');
			Sys.exit(0);
		}
		frame = -60;
		times = [];
		samples = [];
		allocations = deallocations = 0;
		allocationMs = 0.;
		peakUsed = peakReserved = peakOs = null;
	}

	static function main() {
		new GpuMemoryBaseline();
	}
}
