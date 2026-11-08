//TARGETS=hl
private class TileReferenceShader extends hxsl.Shader {
	static var SRC = {
		var pixelColor : Vec4;
		function fragment() { pixelColor *= 1.; }
	};
}

private class TileLocalShader extends hxsl.Shader {
	static var SRC = {
		var spritePosition : Vec4;
		var pixelColor : Vec4;
		function fragment() { pixelColor.rgb *= vec3(spritePosition.xy, 1.); }
	};
}

class TileBatching extends hxd.App {
	var texture : h3d.mat.Texture;
	var target : h3d.mat.Texture;
	var referenceShader = new TileReferenceShader();
	var cases = 0;
	var comparisons = 0;

	override function init() {
		var pixels = hxd.Pixels.alloc(4, 4, RGBA);
		for( y in 0...4 ) for( x in 0...4 )
			pixels.setPixel(x, y, [0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFFFF][(x + y) % 4]);
		texture = h3d.mat.Texture.fromPixels(pixels);
		pixels.dispose();
		target = new h3d.mat.Texture(128, 128, [Target], RGBA);
	}

	function bitmap(parent:h2d.Object, x:Float, y:Float, size = 16.) {
		var tile = h2d.Tile.fromTexture(texture);
		tile.scaleToSize(size, size);
		var b = new h2d.Bitmap(tile, parent);
		b.setPosition(x, y);
		return b;
	}

	function check(e:h3d.Engine, name:String, setup:h2d.Scene->Void, expectedDraws = -1) {
		var scene = new h2d.Scene();
		scene.scaleMode = Stretch(128, 128);
		setup(scene);
		e.pushTarget(target);
		e.clear(0);
		var start = e.drawCalls;
		scene.render(e);
		var batchedDraws = e.drawCalls - start;
		e.popTarget();
		var batched = target.capturePixels();

		scene.renderer.addGlobalShader(referenceShader);
		e.pushTarget(target);
		e.clear(0);
		start = e.drawCalls;
		scene.render(e);
		var referenceDraws = e.drawCalls - start;
		e.popTarget();
		var reference = target.capturePixels();
		var visiblePixels = 0;
		for( y in 0...128 ) for( x in 0...128 ) {
			var got = batched.getPixel(x, y);
			var want = reference.getPixel(x, y);
			if( want >>> 24 != 0 ) visiblePixels++;
			for( shift in [0, 8, 16, 24] )
				if( Math.abs(((got >>> shift) & 255) - ((want >>> shift) & 255)) > 1 )
					throw '$name pixel $x,$y: ${StringTools.hex(got)} != ${StringTools.hex(want)}';
			comparisons++;
		}
		if( visiblePixels == 0 ) throw '$name: reference image is empty';
		if( expectedDraws >= 0 && batchedDraws != expectedDraws )
			throw '$name: expected $expectedDraws draws, got $batchedDraws';
		Sys.println('$name: draws $referenceDraws -> $batchedDraws, pixels match');
		batched.dispose();
		reference.dispose();
		scene.dispose();
		cases++;
	}

	override function render(e:h3d.Engine) {
		check(e, "shared texture", scene -> {
			for( i in 0...1000 ) bitmap(scene, i % 100, Std.int(i / 100));
		}, 1);
		check(e, "bounded batch", scene -> {
			for( i in 0...8200 ) bitmap(scene, i % 100, Std.int(i / 100));
		}, 3);
		check(e, "offscreen culling", scene -> {
			bitmap(scene, 10, 10);
			bitmap(scene, -1000, 0);
			bitmap(scene, 1000, 0).rotation = 0.4;
		}, 1);
		check(e, "sampler changes", scene -> {
			for( i in 0...4 ) {
				var b = bitmap(scene, i * 28, 4, 24);
				b.smooth = i % 2 == 1;
				b.tileWrap = i >= 2;
				b.tile.scrollDiscrete(2, 2);
			}
		}, 4);
		check(e, "texture boundaries", scene -> {
			bitmap(scene, 0, 0, 48);
			var b = new h2d.Bitmap(h2d.Tile.fromColor(0x2080FF, 48, 48), scene);
			b.setPosition(20, 20);
			bitmap(scene, 40, 40, 48);
		}, 3);
		check(e, "rejected tile", scene -> {
			bitmap(scene, 0, 0, 48);
			var rejected = bitmap(scene, 20, 20, 48);
			bitmap(scene, 40, 40, 48);
			scene.renderer.onBeginDraw = obj -> obj != rejected;
		}, 1);
		check(e, "alpha color and blend order", scene -> {
			var parent = new h2d.Object(scene);
			parent.alpha = 0.6;
			for( i in 0...6 ) {
				var b = bitmap(parent, 8 + i * 12, 8 + i * 8, 48);
				b.color.set(0.3 + i * 0.1, 0.8, 0.5, 0.7);
				b.alpha = 0.8;
				b.blendMode = i < 2 ? Alpha : i < 4 ? Add : Multiply;
			}
		}, 3);
		check(e, "rotated flipped atlas tiles", scene -> {
			for( i in 0...4 ) {
				var b = bitmap(scene, 8 + i * 26, 8, 24);
				@:privateAccess b.tile.rotated = i % 2 == 0;
				@:privateAccess b.tile.updateUVs();
				if( i >= 2 ) b.tile.flipX();
				b.tile.dx = -3;
				b.tile.dy = 2;
				b.rotation = 0.2;
			}
		}, 1);
		check(e, "clip boundaries", scene -> {
			bitmap(scene, 0, 0, 80);
			var mask = new h2d.Mask(32, 32, scene);
			mask.setPosition(16, 16);
			bitmap(mask, 0, 0, 64);
			bitmap(scene, 60, 60, 48);
		}, 3);
		check(e, "filters and nested alpha", scene -> {
			bitmap(scene, 0, 0, 32);
			var parent = new h2d.Object(scene);
			parent.setPosition(20, 20);
			parent.alpha = 0.5;
			parent.filter = new h2d.filter.Blur(2, 1);
			bitmap(parent, 0, 0, 48);
			var nested = bitmap(parent, 12, 12, 48);
			nested.alpha = 0.6;
			nested.filter = new h2d.filter.Blur(1, 1);
			bitmap(scene, 88, 88, 24);
		});
		check(e, "filtered drawable color", scene -> {
			var b = bitmap(scene, 20, 20, 48);
			b.color.set(0.5, 0.8, 0.2, 0.6);
			b.alpha = 0.7;
			b.filter = new h2d.filter.Blur(2, 1);
		});
		check(e, "custom shader boundary", scene -> {
			bitmap(scene, 0, 0, 48);
			bitmap(scene, 20, 20, 48).addShader(new h3d.shader.ColorAdd(0x220000));
			bitmap(scene, 40, 40, 48);
		}, 3);
		check(e, "shader added by draw callback", scene -> {
			bitmap(scene, 0, 0, 48);
			var highlighted = bitmap(scene, 20, 20, 48);
			bitmap(scene, 40, 40, 48);
			scene.renderer.onBeginDraw = obj -> {
				if( obj == highlighted && obj.getShader(TileLocalShader) == null )
					obj.addShader(new TileLocalShader());
				return true;
			};
		}, 3);
		check(e, "tile group boundary", scene -> {
			bitmap(scene, 0, 0, 48);
			var group = new h2d.TileGroup(h2d.Tile.fromTexture(texture), scene);
			group.add(20, 20, h2d.Tile.fromTexture(texture));
			bitmap(scene, 40, 40, 48);
		}, 3);
		check(e, "reverse drawing order", scene -> {
			scene.renderer.front2back = true;
			for( i in 0...4 ) bitmap(scene, i * 10, i * 10, 64).alpha = 0.5;
		}, 1);
		check(e, "camera transform", scene -> {
			scene.camera.x = 8;
			scene.camera.y = 12;
			scene.camera.rotation = 0.2;
			scene.camera.scaleX = 1.25;
			scene.camera.scaleY = 0.75;
			for( i in 0...4 ) bitmap(scene, 16 + i * 20, 16 + i * 10, 24);
		}, 1);
		texture.dispose();
		target.dispose();
		e.mem.dispose();
		e.dispose();
		Sys.println('PASS cases=$cases pixels=$comparisons');
		Sys.exit(0);
	}

	static function main() {
		hxd.GraphicsDriverConfig.setCurrent(switch( Sys.args()[0] ) {
			case "dx11": Dx11;
			case "dx12": Dx12;
			case "vulkan": Vulkan;
			default: OpenGL;
		});
		new TileBatching();
	}
}
