//TARGETS=hl,hldx11,hldx12,hlvulkan
private class SortVariant extends hxsl.Shader {
	static var SRC = {
		@const var variant : Int;
		var pixelColor : Vec4;
		function fragment() {
			if( variant == 0 ) pixelColor.rgb *= vec3(1., 0.75, 0.5);
			else if( variant == 1 ) pixelColor.rgb *= vec3(0.5, 1., 0.75);
			else if( variant == 2 ) pixelColor.rgb *= vec3(0.75, 0.5, 1.);
			else pixelColor.rgb *= vec3(0.75, 0.75, 0.75);
		}
	};
}

private class SortingRenderer extends h3d.scene.pbr.Renderer {
	public var strict = false;
	public var switches = 0;
	public var sortMs = 0.;
	public var opaqueOrder : Array<String>;
	public var alphaOrder : Array<String>;
	public var checkBuckets = true;
	var requestedSort : h3d.pass.PassList -> Void;
	var measuredSort : h3d.pass.PassList -> Void;
	var measuringOpaque : Bool;

	public function new() {
		super();
		measuredSort = measureSort;
		@:privateAccess enableFXAA = false;
		shadows = false;
	}

	override function renderPass(p:h3d.pass.Output, passes:h3d.pass.PassList, ?sort:h3d.pass.PassList->Void) {
		if( !passes.isEmpty() ) @:privateAccess {
			var name = passes.current.pass.name;
			if( name == "default" || name == "alpha" || name == "forwardAlpha" ) {
				measuringOpaque = name == "default";
				requestedSort = strict && measuringOpaque ? frontToBack : sort;
				var before = ctx.engine.shaderSwitches;
				super.renderPass(p, passes, measuredSort);
				if( measuringOpaque ) switches = ctx.engine.shaderSwitches - before;
				return;
			}
		}
		super.renderPass(p, passes, sort);
	}

	function measureSort(passes:h3d.pass.PassList) {
		var start = haxe.Timer.stamp();
		requestedSort(passes);
		if( measuringOpaque ) {
			sortMs = (haxe.Timer.stamp() - start) * 1000;
			opaqueOrder = [for( p in passes ) p.obj.name];
			var layer = -0x7FFFFFFF;
			var bucket = -1;
			for( p in passes ) {
				if( p.pass.layer < layer ) throw "Opaque layers were reordered";
				if( p.pass.layer != layer ) bucket = -1;
				if( !strict && checkBuckets ) @:privateAccess {
					if( p.depthBucket < bucket || p.depthBucket < 0 || p.depthBucket >= 32 )
						throw "Opaque depth buckets were reordered";
					bucket = p.depthBucket;
				}
				layer = p.pass.layer;
			}
		} else {
			for( p in passes ) alphaOrder.push(p.obj.name);
		}
	}

	public function albedo() {
		return @:privateAccess textures.albedo.capturePixels();
	}
}

class PbrSorting extends hxd.App {
	var scene : h3d.scene.Scene;
	var renderer : SortingRenderer;
	var meshes : Array<h3d.scene.Mesh> = [];
	var target : h3d.mat.Texture;
	var textures : Array<h3d.mat.Texture> = [];
	var cases = 0;
	var comparisons = 0;

	override function init() {
		h3d.mat.PbrMaterialSetup.set();
		scene = new h3d.scene.Scene(false);
		renderer = new SortingRenderer();
		scene.renderer = renderer;
		scene.camera.pos.set(0, 0, 10);
		scene.camera.target.set(0, 0, 0);
		scene.camera.up.set(0, 1, 0);
		scene.camera.zNear = 0.1;
		scene.camera.zFar = 100;
		scene.camera.fovY = 45;
		new h3d.scene.pbr.DirLight(new h3d.Vector(0, 0, -1), scene);
		target = new h3d.mat.Texture(128, 128, [Target], RGBA);
		target.depthBuffer = new h3d.mat.Texture(128, 128, [Target], Depth24);
		for( color in [0xFFFFFF, 0x80C0FF] ) textures.push(h3d.mat.Texture.fromColor(color));
		var cube = new h3d.prim.Cube(0.11, 0.11, 0.11, true);
		cube.unindex();
		cube.addNormals();
		cube.addUVs();
		for( i in 0...512 ) {
			var material = h3d.mat.Material.create(textures[(i >> 3) & 1]);
			material.shadows = false;
			material.mainPass.culling = (i & 4) == 0 ? None : Back;
			var shader = new SortVariant();
			shader.variant = i % 4;
			material.mainPass.addShader(shader);
			var mesh = new h3d.scene.Mesh(cube, material, scene);
			mesh.name = 'opaque_$i';
			meshes.push(mesh);
		}
		for( i in 0...4 ) {
			var material:h3d.mat.PbrMaterial = cast h3d.mat.Material.create();
			var props:h3d.mat.PbrMaterial.PbrProps = cast material.props;
			props.blend = Alpha;
			material.refreshProps();
			if( i >= 2 ) material.mainPass.setPassName("forwardAlpha");
			material.mainPass.enableLights = false;
			material.shadows = false;
			material.color.set(i % 2, 1 - (i % 2), 0.5, 0.5);
			var mesh = new h3d.scene.Mesh(cube, material, scene);
			mesh.name = 'alpha_$i';
			mesh.setScale(8);
			mesh.setPosition(0, 0, 3 + i * 0.1);
		}
	}

	function draw(e:h3d.Engine, strict:Bool) {
		renderer.strict = strict;
		renderer.alphaOrder = [];
		scene.setOutputTarget(e, target);
		e.clear(0, scene.camera.reverseDepth ? 0 : 1);
		scene.render(e);
		scene.setOutputTarget();
		return renderer.albedo();
	}

	function compare(name:String, actual:hxd.Pixels, expected:hxd.Pixels) {
		var visible = 0;
		for( y in 0...128 ) for( x in 0...128 ) {
			var got = actual.getPixel(x, y), want = expected.getPixel(x, y);
			if( (want & 0xFFFFFF) != 0 ) visible++;
			for( shift in [0, 8, 16, 24] )
				if( Math.abs(((got >>> shift) & 255) - ((want >>> shift) & 255)) > 1 )
					throw '$name pixel $x,$y: ${StringTools.hex(got)} != ${StringTools.hex(want)}';
			comparisons++;
		}
		if( visible == 0 ) throw '$name: empty reference image';
	}

	function check(e:h3d.Engine, name:String, rightHanded = false, reverse = false, ortho = false, equalDepth = false, overlap = false, fallback = "") {
		scene.camera.rightHanded = rightHanded;
		scene.camera.reverseDepth = reverse;
		scene.camera.orthoBounds = ortho ? h3d.col.Bounds.fromValues(-3, -3, 0.1, 6, 6, 100) : null;
		renderer.checkBuckets = fallback == "";
		for( i in 0...meshes.length ) {
			var mesh = meshes[i];
			mesh.setPosition(overlap ? 0 : (i % 32) * 0.16 - 2.48, overlap ? 0 : Std.int(i / 32) * 0.16 - 1.2,
				2 - (equalDepth ? 0 : i * 0.002));
			mesh.material.mainPass.layer = name == "layers" ? i % 3 : 0;
		}
		var pass = meshes[0].material.mainPass;
		switch( fallback ) {
		case "depthWrite": pass.depthWrite = false;
		case "blend": pass.blend(SrcAlpha, OneMinusSrcAlpha);
		case "stencil": pass.stencil = new h3d.mat.Stencil();
		case "colorMask": pass.colorMask = 7;
		case "depthTest": pass.depthTest = Always;
		default:
		}
		var baseline = draw(e, true);
		var baselineSwitches = renderer.switches;
		var baselineSortMs = renderer.sortMs;
		var baselineOrder = renderer.opaqueOrder.join(",");
		var alphaOrder = renderer.alphaOrder.join(",");
		var actual = draw(e, false);
		compare(name, actual, baseline);
		if( renderer.alphaOrder.join(",") != alphaOrder ) throw '$name: transparent order changed';
		if( fallback != "" ) {
			if( renderer.opaqueOrder.join(",") != baselineOrder ) throw '$name: fallback order changed';
		} else if( renderer.switches >= baselineSwitches ) {
			throw '$name: shader switches did not decrease ($baselineSwitches -> ${renderer.switches})';
		}
		Sys.println('$name: shader switches $baselineSwitches -> ${renderer.switches}, sort CPU ms $baselineSortMs -> ${renderer.sortMs}, pixels and transparency match');
		pass.depthWrite = true;
		pass.blend(One, Zero);
		pass.stencil = null;
		pass.colorMask = 15;
		pass.depthTest = Less;
		baseline.dispose();
		actual.dispose();
		cases++;
	}

	override function render(e:h3d.Engine) {
		try {
			check(e, "perspective");
			check(e, "orthographic", false, false, true);
			check(e, "reverse depth", false, true);
			check(e, "right handed", true);
			check(e, "right handed reverse", true, true);
			check(e, "equal depth", false, false, false, true);
			check(e, "overlap", false, false, false, false, true);
			check(e, "layers");
			for( fallback in ["depthWrite", "blend", "stencil", "colorMask", "depthTest"] )
				check(e, fallback, false, false, false, false, false, fallback);
			scene.dispose();
			for( texture in textures ) texture.dispose();
			target.depthBuffer.dispose();
			target.dispose();
			e.mem.dispose();
			e.dispose();
			Sys.println('PASS cases=$cases pixels=$comparisons');
			Sys.exit(0);
		} catch( error : Dynamic ) {
			Sys.println('FAIL: $error');
			Sys.exit(1);
		}
	}

	static function main() {
		hxd.GraphicsDriverConfig.setCurrent(switch( Sys.args()[0] ) {
			case "dx11": Dx11;
			case "dx12": Dx12;
			case "vulkan": Vulkan;
			default: OpenGL;
		});
		new PbrSorting();
	}
}
