//TARGETS=hl,hldx11,hldx12,hlvulkan
private class UploadReferenceShader extends hxsl.Shader {
	static var SRC = {
		var pixelColor : Vec4;
		function fragment() { pixelColor *= 1.; }
	};
}

class TileBatchUploads extends hxd.App {
	static inline var FRAMES = 72;
	var frame = 0;
	var scene : h2d.Scene;
	var sprites : Array<h2d.Bitmap> = [];
	var targets : Array<h3d.mat.Texture> = [];
	var texture : h3d.mat.Texture;
	var referenceShader = new UploadReferenceShader();
	var baseline : Bool;
	var initialBufferMemory : Float;
	var allocations = 0;
	var recreations = 0;
	var comparisons = 0;
	var renderTimes : Array<Float> = [];

	override function init() {
		baseline = Sys.args().indexOf("--baseline") >= 0;
		hxd.Window.getInstance().presentMode = Immediate;
		initialBufferMemory = engine.mem.bufferMemory;
		texture = h3d.mat.Texture.fromColor(0xFFFFFF);
		for( _ in 0...4 ) targets.push(new h3d.mat.Texture(128, 128, [Target], RGBA));
		scene = new h2d.Scene();
		scene.scaleMode = Stretch(128, 128);
		for( i in 0...512 ) {
			var b = new h2d.Bitmap(h2d.Tile.fromTexture(texture), scene);
			b.tile.scaleToSize(8, 8);
			b.tileWrap = i % 2 == 0;
			sprites.push(b);
		}
	}

	function renderPass(e:h3d.Engine, pass:Int, phase:Int, measure:Bool) {
		for( i in 0...sprites.length ) {
			var b = sprites[i];
			b.setPosition((i % 32) * 4 + (phase % 3) * 0.25, Std.int(i / 32) * 8);
			b.color.set(((i + phase) % 7) / 7, ((i + phase * 3) % 11) / 11, 0.5, 0.6);
		}
		e.pushTarget(targets[pass]);
		e.clear(0);
		var before = e.drawCalls;
		var start = haxe.Timer.stamp();
		scene.render(e);
		if( measure ) renderTimes.push((haxe.Timer.stamp() - start) * 1000);
		var expected = frame == 1 && pass < 2 ? 1 : sprites.length;
		if( e.drawCalls - before != expected ) throw 'Frame $frame pass $pass: unexpected draw count';
		e.popTarget();
	}

	function compare(actual:h3d.mat.Texture, reference:h3d.mat.Texture) {
		var got = actual.capturePixels();
		var want = reference.capturePixels();
		var visiblePixels = 0;
		for( y in 0...128 ) for( x in 0...128 ) {
			var a = got.getPixel(x, y), b = want.getPixel(x, y);
			if( b >>> 24 != 0 ) visiblePixels++;
			for( shift in [0, 8, 16, 24] )
				if( Math.abs(((a >>> shift) & 255) - ((b >>> shift) & 255)) > 1 )
					throw 'Frame $frame pixel $x,$y: ${StringTools.hex(a)} != ${StringTools.hex(b)}';
			comparisons++;
		}
		if( visiblePixels == 0 ) throw 'Frame $frame: reference image is empty';
		got.dispose();
		want.dispose();
	}

	override function render(e:h3d.Engine) {
		if( frame <= 2 )
			for( i in 0...sprites.length ) sprites[i].tileWrap = frame != 1 && i % 2 == 0;
		var invalidated = false;
		if( frame == 36 ) {
			var buffer:h3d.Buffer = Reflect.field(scene.renderer, "uploadBuffer");
			if( buffer != null ) {
				buffer.dispose();
				invalidated = true;
			}
		}
		var before = h3d.Buffer.GUID;
		var measure = frame >= 8 && frame != 36;
		renderPass(e, 0, frame * 2, measure);
		renderPass(e, 1, frame * 2 + 1, measure);
		if( frame <= 2 || frame % 8 == 0 || frame == 36 || frame == FRAMES - 1 ) {
			scene.renderer.addGlobalShader(referenceShader);
			renderPass(e, 2, frame * 2, false);
			renderPass(e, 3, frame * 2 + 1, false);
			scene.renderer.removeGlobalShader(referenceShader);
			compare(targets[0], targets[2]);
			compare(targets[1], targets[3]);
		}
		var created = h3d.Buffer.GUID - before;
		if( frame >= 8 ) {
			if( invalidated ) recreations += created else allocations += created;
			if( !baseline && created != (invalidated ? 1 : 0) )
				throw 'Frame $frame: unexpected buffer allocations: $created';
		}
		if( ++frame < FRAMES ) return;

		scene.dispose();
		if( e.mem.bufferMemory != initialBufferMemory )
			throw 'Buffer leak: ${e.mem.bufferMemory - initialBufferMemory} bytes';
		for( target in targets ) target.dispose();
		renderTimes.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		Sys.println(haxe.Json.stringify({
			api: Sys.args()[0],
			backend: e.driverName(),
			baseline: baseline,
			frames: frame,
			measuredAllocations: allocations,
			forcedRecreations: recreations,
			renderCpuMedianMs: renderTimes[renderTimes.length >> 1],
			comparedPixels: comparisons
		}));
		e.mem.dispose();
		e.dispose();
		Sys.println(baseline ? "PASS baseline rendering and disposal" : "PASS upload reuse, range wrapping, repeated renders, buffer recreation and disposal");
		Sys.exit(0);
	}

	static function main() {
		hxd.GraphicsDriverConfig.setCurrent(switch( Sys.args()[0] ) {
			case "dx11": Dx11;
			case "dx12": Dx12;
			case "vulkan": Vulkan;
			default: OpenGL;
		});
		new TileBatchUploads();
	}
}
