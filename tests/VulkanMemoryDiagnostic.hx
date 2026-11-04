import h3d.mat.Texture;
import hxd.GraphicsDriverConfig;

class VulkanMemoryDiagnostic extends hxd.App {
	static var frameCount = 64;

	var frame = 0;
	var previous:Texture;
	var bitmap:h2d.Bitmap;
	var started:Float;

	override function init() {
		started = haxe.Timer.stamp();
		bitmap = new h2d.Bitmap(null, s2d);
	}

	override function update(dt:Float) {
		try {
			if (frame == frameCount) {
				bitmap.remove();
				previous.dispose();
				final driver:h3d.impl.driver.vulkan.VulkanDriver = cast engine.driver;
				final usage = @:privateAccess driver.getMemoryUsage();
				if (usage == null || usage.allocated < 0 || usage.total < 0)
					throw "Invalid memory usage statistics";
				@:privateAccess driver.dispose();
				Sys.println(haxe.Json.stringify({frames: frame, seconds: haxe.Timer.stamp() - started, usage: usage}));
				Sys.exit(0);
			}
			final size = frame % 16 == 0 ? 4096 : 64 + (frame % 64) * 4;
			final pixels = hxd.Pixels.alloc(size, size, RGBA);
			pixels.bytes.fill(0, pixels.bytes.length, frame & 255);
			final texture = Texture.fromPixels(pixels, RGBA);
			final captured = texture.capturePixels();
			if (captured.bytes.compare(pixels.bytes) != 0)
				throw 'Readback mismatch on frame $frame';
			captured.dispose();
			pixels.dispose();
			bitmap.tile = h2d.Tile.fromTexture(texture);
			if (previous != null)
				previous.dispose();
			previous = texture;
			frame++;
		} catch (error:Dynamic) {
			Sys.stderr().writeString('Vulkan memory diagnostic failed: $error\n');
			Sys.exit(1);
		}
	}

	static function main() {
		GraphicsDriverConfig.setCurrent(Vulkan);
		final args = Sys.args();
		if (args.indexOf("--stress") >= 0)
			frameCount = 2048;
		limen.graphics.renderer.vulkan.internal.VulkanBindings.ENABLE_VALIDATION = args.indexOf("--validation") >= 0;
		try {
			new VulkanMemoryDiagnostic();
		} catch (error:Dynamic) {
			Sys.stderr().writeString('Vulkan memory diagnostic initialization failed: $error\n');
			Sys.exit(1);
		}
	}
}
