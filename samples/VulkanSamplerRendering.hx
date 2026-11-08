//TARGETS=hlvulkan
private class SampleShader extends hxsl.Shader {
	static var SRC = {
		@param var source : Sampler2D;
		@param var uv : Vec2;
		var pixelColor : Vec4;
		function fragment() { pixelColor = source.get(uv); }
	};
}
private class BindlessSampleShader extends hxsl.Shader {
	static var SRC = {
		@param var source : TextureHandle;
		@param var uv : Vec2;
		var pixelColor : Vec4;
		function fragment() {
			var texture : Sampler2D;
			resolveSampler(source, texture);
			pixelColor = texture.get(uv);
		}
	};
}
class VulkanSamplerRendering extends hxd.App {
	var frame = 0;
	var comparisons = 0;
	var regular = new SampleShader();
	var indexed = new BindlessSampleShader();
	var bitmap:h2d.Bitmap;
	var target:h3d.mat.Texture;
	var texture:h3d.mat.Texture;
	var bindless:Bool;
	var colors = [0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFFFF];

	override function init() {
		bindless = Sys.args().indexOf('--bindless') >= 0;
		target = new h3d.mat.Texture(64, 64, [Target], RGBA);
		bitmap = new h2d.Bitmap(h2d.Tile.fromColor(0xFFFFFF, 64, 64), s2d);
		bitmap.addShader(bindless ? cast indexed : cast regular);
	}

	function reference(u:Float, v:Float, linear:Bool, repeat:Bool):Int {
		function texel(x:Int, y:Int):Int {
			x = repeat ? ((x % 2) + 2) % 2 : (x < 0 ? 0 : x > 1 ? 1 : x);
			y = repeat ? ((y % 2) + 2) % 2 : (y < 0 ? 0 : y > 1 ? 1 : y);
			return colors[y * 2 + x];
		}
		if (!linear) return texel(Math.floor(u * 2), Math.floor(v * 2));
		final x = u * 2 - 0.5;
		final y = v * 2 - 0.5;
		final ix = Math.floor(x), iy = Math.floor(y);
		final fx = x - ix, fy = y - iy;
		var result = 0xFF000000;
		for (shift in [0, 8, 16]) {
			final a = ((texel(ix, iy) >>> shift) & 255) * (1 - fx) + ((texel(ix + 1, iy) >>> shift) & 255) * fx;
			final b = ((texel(ix, iy + 1) >>> shift) & 255) * (1 - fx) + ((texel(ix + 1, iy + 1) >>> shift) & 255) * fx;
			result |= Math.round(a * (1 - fy) + b * fy) << shift;
		}
		return result;
	}

	override function render(e:h3d.Engine) {
		final driver:h3d.impl.driver.vulkan.VulkanDriver = cast e.driver;
		if (texture != null) texture.dispose();
		final pixels = hxd.Pixels.alloc(2, 2, RGBA);
		for (i in 0...4) pixels.setPixel(i % 2, Std.int(i / 2), colors[i]);
		texture = h3d.mat.Texture.fromPixels(pixels);
		pixels.dispose();
		final expected:Array<Int> = [];
		e.pushTarget(target);
		e.clear(0);
		for (draw in 0...4) {
			final linear = draw % 2 == 1;
			final repeat = draw >= 2;
			texture.filter = linear ? Linear : Nearest;
			texture.wrap = repeat ? Repeat : Clamp;
			texture.lodBias = (frame % 16) * 0.5;
			final u = [-0.125, 0.375, 0.625, 1.125][frame % 4];
			final v = [-0.125, 0.375, 0.625, 1.125][Std.int(frame / 4) % 4];
			expected.push(reference(u, v, linear, repeat));
			if (bindless) {
				indexed.source = driver.getTextureHandle(texture);
				indexed.uv.set(u, v);
			} else {
				regular.source = texture;
				regular.uv.set(u, v);
			}
			bitmap.x = draw * 16;
			bitmap.scaleX = 0.25;
			s2d.render(e);
		}
		e.popTarget();
		if (frame % 17 == 0 || frame == 511) {
			final actual = target.capturePixels();
			for (y in 0...64) for (x in 0...64) {
				final want = expected[Std.int(x / 16)];
				final got = actual.getPixel(x, y);
				for (shift in [0, 8, 16, 24])
					if (Math.abs(((got >>> shift) & 255) - ((want >>> shift) & 255)) > 1)
						throw 'Frame $frame pixel $x,$y: ${StringTools.hex(got)} != ${StringTools.hex(want)}';
				comparisons++;
			}
			actual.dispose();
		}
		super.render(e);
		if (++frame == 512) {
			final stats = driver.getDrawDebugStats();
			if (stats.samplerCreations < 64 || stats.samplerCacheHits == 0) throw "Missing sampler churn/cache coverage";
			Sys.println(haxe.Json.stringify(stats));
			if (bindless) {
				final slots = driver.getBindlessDebugStats();
				if (slots.generations != 2 || slots.slotReuses == 0) throw "Missing slot/generation coverage";
				Sys.println(haxe.Json.stringify(slots));
			}
			final validation = limen.graphics.renderer.vulkan.internal.VulkanBindings.validationEnabled();
			if (!validation) throw "Vulkan validation is unavailable";
			e.dispose();
			Sys.println('PASS bindless=$bindless frames=$frame draws=2048 comparisons=$comparisons validation=' + validation);
			Sys.exit(0);
		}
	}
	static function main() {
		hxd.GraphicsDriverConfig.setCurrent(Vulkan);
		if (Sys.args().indexOf('--bindless') >= 0) h3d.impl.driver.Driver.requestFeature(Bindless);
		limen.graphics.renderer.vulkan.internal.VulkanBindings.ENABLE_VALIDATION = true;
		new VulkanSamplerRendering();
	}
}
