//TARGETS=hlvulkan
class VulkanTransientScopes extends hxd.App {
	var frame = 0;
	var peakUsed:haxe.Int64 = 0;
	var peakReserved:haxe.Int64 = 0;
	var peakAllocations = 0;
	var peakBlocks = 0;
	var started = 0.;
	var baseline = Sys.args().indexOf("--baseline") >= 0;

	override function render(engine:h3d.Engine) {
		if (frame == 0) started = haxe.Timer.stamp();
		var driver:h3d.impl.driver.vulkan.VulkanDriver = cast @:privateAccess engine.driver;
		var allocator = @:privateAccess driver.allocator;
		var size = frame % 2 == 0 ? 256 : 512;
		var targets = [for (i in 0...8) new h3d.mat.Texture(size, size, [Target, NoAlloc], RGBA)];
		var previousId = -1;
		function draw(i:Int, t:h3d.mat.Texture) {
			var native:h3d.impl.driver.vulkan.resource.VulkanImage.VulkanTexture = @:privateAccess t.t;
			if (!baseline && i > 0 && native.allocation.debugId != previousId) throw "Compatible targets did not alias";
			previousId = native.allocation.debugId;
			if (frame == 0 && i == 0) {
				var rejected = false;
				try driver.renderTransientTargets([t], (_, _) -> {}) catch (_:Dynamic) { rejected = true; }
				if (!rejected) throw "Active target lifetime was accepted for aliasing";
			}
			if (allocator.usedBytes > peakUsed) peakUsed = allocator.usedBytes;
			if (allocator.reservedBytes > peakReserved) peakReserved = allocator.reservedBytes;
			if (allocator.allocationCount > peakAllocations) peakAllocations = allocator.allocationCount;
			if (allocator.getBlockCount() > peakBlocks) peakBlocks = allocator.getBlockCount();
			driver.setRenderTarget(t, 0, 0, NotBound);
			driver.clear(new h3d.Vector4(1, 0, 0, 1));
			driver.setRenderTarget(null);
			driver.setRenderTarget(t, 0, 0, NotBound);
			if (frame % 10 == 0) {
				var pixels = driver.capturePixels(t, 0, 0);
				for (y in 0...size) for (x in 0...size) {
					var p = pixels.getPixelF(x, y);
					if (p.r != 1 || p.g != 0 || p.b != 0 || p.a != 1) throw "Transient pixel mismatch";
				}
				pixels.dispose();
			}
		}
		if (baseline) {
			for (t in targets) @:privateAccess t.t = driver.allocTexture(t);
			for (i in 0...targets.length) draw(i, targets[i]);
			driver.setRenderTarget(null);
			for (t in targets) driver.disposeTexture(t);
		} else driver.renderTransientTargets(targets, draw);
		if (frame == 0) {
			var incompatible = [new h3d.mat.Texture(32, 32, [Target, NoAlloc], RGBA),
				new h3d.mat.Texture(64, 64, [Target, NoAlloc], RGBA),
				new h3d.mat.Texture(64, 64, [Target, NoAlloc], RGBA16F)];
			var ids = [];
			driver.renderTransientTargets(incompatible, (i, t) -> {
				var image:h3d.impl.driver.vulkan.resource.VulkanImage.VulkanTexture = @:privateAccess t.t;
				if (ids.indexOf(image.allocation.debugId) >= 0) throw "Incompatible targets aliased";
				ids.push(image.allocation.debugId);
			});
			var failed = [new h3d.mat.Texture(32, 32, [Target, NoAlloc], RGBA)];
			try driver.renderTransientTargets(failed, (_, _) -> { throw "Expected callback failure"; })
			catch (error:Dynamic) { if (error != "Expected callback failure") throw error; }
			if (@:privateAccess failed[0].t != null) throw "Failed scope retained a texture";
		}
		frame++;
	}

	override function update(dt:Float) {
		if (frame == 60) {
			Sys.println('PASS baseline=$baseline frames=$frame used=$peakUsed reserved=$peakReserved allocations=$peakAllocations blocks=$peakBlocks seconds=${haxe.Timer.stamp() - started}');
			engine.dispose();
			Sys.exit(0);
		}
	}

	static function main() {
		limen.graphics.renderer.vulkan.internal.VulkanBindings.ENABLE_VALIDATION = true;
		new VulkanTransientScopes();
	}
}
