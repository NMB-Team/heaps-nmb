import h3d.mat.Data.Filter;
import h3d.mat.Data.MipMap;
import h3d.mat.Data.Wrap;

class VulkanSamplerCacheDiagnostic extends hxd.App {
	override function init() {
		final driver:h3d.impl.driver.vulkan.VulkanDriver = cast engine.driver;
		final cache = new h3d.impl.driver.vulkan.sampler.VulkanSamplerCache(
			@:privateAccess driver.ctx, @:privateAccess driver.limits, @:privateAccess driver.capabilities.samplerAnisotropy);
		final texture = new h3d.mat.Texture(1, 1);
		final states:Array<Int> = [];
		final keys = new Map<String, Bool>();
		final start = haxe.Timer.stamp();
		for (bias in 0...32) for (wrap in [Wrap.Clamp, Wrap.Repeat, Wrap.Mirror]) for (mip in [MipMap.None, MipMap.Nearest, MipMap.Linear])
			for (filter in [Filter.Nearest, Filter.Linear, Filter.AnisotropicNearest, Filter.AnisotropicLinear]) for (level in 1...17) {
				if (states.length == 2048) continue;
				texture.lodBias = Math.min(bias * 0.25, @:privateAccess driver.limits.maxSamplerLodBias);
				texture.wrap = wrap;
				texture.mipMap = mip;
				texture.filter = filter;
				texture.anisotropicMaxLevel = level;
				final handle = cache.get(texture, true);
				if (!keys.exists(handle.key)) {
					keys.set(handle.key, true);
					states.push(@:privateAccess texture.bits);
				}
			}
		final creationMs = (haxe.Timer.stamp() - start) * 1000;
		if (states.length != 2048) throw 'Only ${states.length} unique sampler states available';
		final hits = cache.cacheHitCount;
		final hitStart = haxe.Timer.stamp();
		for (_ in 0...10) for (bits in states) {
			@:privateAccess texture.bits = bits;
			cache.get(texture, true);
		}
		final hitMs = (haxe.Timer.stamp() - hitStart) * 1000;
		if (cache.creationCount != 2048 || cache.cacheHitCount - hits != 20480)
			throw "Sampler cache failed to reuse states";
		Sys.println(haxe.Json.stringify({liveSamplers: cache.creationCount, replayHits: cache.cacheHitCount - hits,
			creationMs: creationMs, hitMs: hitMs}));
		cache.dispose();
		texture.dispose();
		engine.dispose();
		Sys.println("PASS sampler cache stress");
		Sys.exit(0);
	}

	static function main() {
		hxd.GraphicsDriverConfig.setCurrent(Vulkan);
		limen.graphics.renderer.vulkan.internal.VulkanBindings.ENABLE_VALIDATION = true;
		new VulkanSamplerCacheDiagnostic();
	}
}
