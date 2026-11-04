//TARGETS=hldx12
//PARAM=-D dx12_descriptor_profile

#if !dx12_descriptor_profile
#error "Requires dx12_descriptor_profile"
#end

import h3d.impl.driver.dx12.descriptor.DescriptorHeapBase;

class Dx12DescriptorBenchmark extends hxd.App {
	var tick = 0;
	var textures:Array<h3d.mat.Texture> = [];
	var samples:Array<Dynamic> = [];

	function snapshot():Dynamic {
		final d:h3d.impl.driver.dx12.DX12Driver = cast engine.driver;
		var heaps:Array<DescriptorHeapBase> = [];
		var cacheGrowths = 0;
		var resets = 0;
		var resetSeconds = 0.;
		@:privateAccess {
			heaps = [d.cpuSrvHeap, d.cpuSamplerHeap, d.bindlessSrvHeap, d.bindlessSamplerHeap, d.renderTargetViews, d.depthStenciViews];
			for (f in d.frames) for (cache in [f.srvHeapCache, f.samplerHeapCache]) {
				for (h in cache.heaps) heaps.push(h);
				cacheGrowths += cache.growths;
				resets += cache.resets;
				resetSeconds += cache.resetSeconds;
			}
		}
		var details = [];
		for (h in heaps) {
			resets += h.resets;
			resetSeconds += h.resetSeconds;
			var used = 0;
			if (Std.isOfType(h, h3d.impl.driver.dx12.descriptor.BlockHeap)) {
				final b:h3d.impl.driver.dx12.descriptor.BlockHeap = cast h;
				used = h.size - b.available;
			} else {
				final b:h3d.impl.driver.dx12.descriptor.ScratchHeap = cast h;
				used = h.size - b.available;
			}
			details.push({capacity:h.size, used:used, unused:h.size-used, peak:h.peakUsage,
				allocations:h.allocations, descriptors:h.allocatedDescriptors, allocation_ms:h.allocationSeconds*1000});
		}
		return {frame:tick, creations:DescriptorHeapBase.totalCreations, growths:DescriptorHeapBase.totalGrowths,
			cache_growths:cacheGrowths, copies:DescriptorHeapBase.copyCalls, copied:DescriptorHeapBase.copiedDescriptors,
			copy_ms:DescriptorHeapBase.copySeconds*1000, resets:resets, reset_ms:resetSeconds*1000, heaps:details};
	}

	override function update(dt:Float) {
		s2d.removeChildren();
		for (t in textures) t.dispose();
		textures.resize(0);
		if (tick < 120) {
			for (i in 0...64) {
				final t = h3d.mat.Texture.fromPixels(new hxd.Pixels(1, 1, haxe.io.Bytes.ofHex("ff0000ff"), RGBA));
				t.getHandle();
				textures.push(t);
				final b = new h2d.Bitmap(h2d.Tile.fromTexture(t), s2d);
				b.x = i * 2;
			}
		}
		samples.push(snapshot());
		if (++tick < 180) return;
		final created = DescriptorHeapBase.totalCreations;
		final cache = new h3d.impl.driver.dx12.descriptor.ScratchHeapArray(CBV_SRV_UAV, 16);
		final released:Array<limen.graphics.renderer.d3d12.resource.Resources.Dx12Resource> = [];
		final started = haxe.Timer.stamp();
		var reserved = 0.;
		for (size in 17...257) {
			cache.checkSize(size, released);
			cache.next();
			cache.reset();
			for (r in released) r.release();
			released.resize(0);
			reserved = cache.getSize();
		}
		final growth = {creations:DescriptorHeapBase.totalCreations-created, ms:(haxe.Timer.stamp()-started)*1000, reserved_bytes:reserved};
		@:privateAccess for (h in cache.heaps) (h.heap : limen.graphics.renderer.d3d12.resource.Resources.Dx12Resource).release();
		sys.io.File.saveContent(Sys.args()[0], haxe.Json.stringify({samples:samples, growth: growth}, null, "\t"));
		engine.driver.dispose();
		Sys.exit(0);
	}

	static function main() {
		h3d.impl.driver.dx12.DX12Driver.DEBUG = Sys.args().indexOf("--debug") >= 0;
		h3d.impl.driver.Driver.requestFeature(Bindless);
		new Dx12DescriptorBenchmark();
	}
}
