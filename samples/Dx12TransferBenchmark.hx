#if !(gfx_dx12 && gpu_memory_benchmark)
#error "Requires gfx_dx12 and gpu_memory_benchmark"
#end

class Dx12TransferBenchmark extends hxd.App {
	var tick = -30;
	var source:h3d.Buffer;
	var dynamicBuffer:h3d.Buffer;
	var data:haxe.io.Bytes;
	var output:haxe.io.Bytes;
	var pending = false;
	var completed = 0;
	var times:Array<Float> = [];
	var samples:Array<Dynamic> = [];
	var previous = 0.;
	var textures:Array<h3d.mat.Texture> = [];
	var uploadMs = 0.;

	override function init() {
		data = haxe.io.Bytes.alloc(4096);
		for (i in 0...data.length) data.set(i, i % 251);
		output = haxe.io.Bytes.alloc(data.length);
		source = new h3d.Buffer(256, hxd.BufferFormat.VEC4_DATA);
		dynamicBuffer = new h3d.Buffer(256, hxd.BufferFormat.VEC4_DATA, [Dynamic]);
		source.uploadBytes(data, 0, 256);
		source.readBytes(output, 0, 256);
		if (output.compare(data) != 0) throw "Synchronous readback mismatch";
		final texture = h3d.mat.Texture.fromPixels(new hxd.Pixels(32, 32, data, RGBA));
		final captured = texture.capturePixels();
		if (captured.bytes.compare(data) != 0) throw "Texture readback mismatch";
		captured.dispose();
		texture.dispose();
	}

	function snapshot():Dynamic {
		final d:h3d.impl.driver.dx12.DX12Driver = cast engine.driver;
		var dynamicBytes = 0.;
		@:privateAccess for (f in d.frames) dynamicBytes += f.dynamicBufferAlloc.getTotalSize();
		return {
			frame: tick,
			upload_pages_created: @:privateAccess h3d.impl.driver.dx12.memory.BufferMemoryType.benchmarkResourceCreations,
			upload_pages_destroyed: @:privateAccess h3d.impl.driver.dx12.memory.BufferMemoryType.benchmarkResourceDestructions,
			async_resources_created: @:privateAccess d.benchmarkReadbackCreations,
			async_resources_destroyed: @:privateAccess d.benchmarkReadbackDestructions,
			upload_reserved: @:privateAccess d.uploadBufferAlloc.getTotalSize(),
			dynamic_reserved: dynamicBytes,
			async_reserved: @:privateAccess d.asyncReadbackBufferSize,
			completed: completed
		};
	}

	override function update(dt:Float) {
		final now = haxe.Timer.stamp();
		if (tick > 0) times.push((now - previous) * 1000);
		final previousFrameTime = previous;
		previous = now;
		if (tick < 0) { tick++; return; }
		for (t in textures) t.dispose();
		textures.resize(0);
		if (tick < 120) {
			final start = haxe.Timer.stamp();
			for (_ in 0...128) dynamicBuffer.uploadBytes(data, 0, 256);
			final pixels = new hxd.Pixels(32, 32, data, RGBA);
			for (_ in 0...128) textures.push(h3d.mat.Texture.fromPixels(pixels));
			uploadMs += (haxe.Timer.stamp() - start) * 1000;
			if (tick % 12 == 0 && !pending) {
				pending = true;
				source.readBytesAsync(output, 0, 256, 0, () -> {
					if (output.compare(data) != 0) throw "Asynchronous readback mismatch";
					completed++;
					pending = false;
				});
			}
		}
		if (tick == 120) {
			final pixels = new hxd.Pixels(2048, 2048, haxe.io.Bytes.alloc(2048 * 2048 * 4), RGBA);
			final start = haxe.Timer.stamp();
			for (_ in 0...36) textures.push(h3d.mat.Texture.fromPixels(pixels));
			uploadMs += (haxe.Timer.stamp() - start) * 1000;
		}
		final sample = snapshot();
		sample.previous_frame_ms = (now - previousFrameTime) * 1000;
		samples.push(sample);
		if (++tick < 300 || pending) return;
		var sum = 0.;
		for (t in times) sum += t;
		times.sort(Reflect.compare);
		final result = {backend: engine.driver.getDriverName(true),
			mean_ms: sum / times.length, p99_ms: times[Math.ceil(times.length * 0.99) - 1],
			upload_cpu_ms: uploadMs, samples: samples};
		sys.io.File.saveContent(Sys.args()[0], haxe.Json.stringify(result, null, "\t"));
		source.dispose();
		dynamicBuffer.dispose();
		engine.driver.dispose();
		Sys.exit(0);
	}

	static function main() {
		h3d.impl.driver.dx12.DX12Driver.DEBUG = Sys.args().indexOf("--debug") >= 0;
		if (Sys.args().indexOf("--trim") >= 0)
			h3d.impl.driver.dx12.DX12Driver.UPLOAD_CACHE_IDLE_FRAMES = 120;
		new Dx12TransferBenchmark();
	}
}
