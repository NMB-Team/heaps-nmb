//TARGETS=hl,hldx11,hldx12,hlvulkan
private class UploadCounter extends h3d.impl.driver.ShaderParamCache {
	public var forceUploads = false;
	public var uploads = 0;
	override public function update(data:h3d.shader.Buffers.ShaderBufferData, count:Int, force = false) {
		var changed = super.update(data, count, force || forceUploads);
		if( changed ) uploads++;
		return changed;
	}
}

private class MaterialProbe extends hxsl.Shader {
	public var preparations = 0;
	static var SRC = {
		@const var flipped : Bool;
		@param var tint : Vec4;
		@param var weights : Array<Vec4, 20>;
		@param var weightIndex : Int;
		@param var tone : Mat4;
		var pixelColor : Vec4;
		function fragment() {
			pixelColor *= tint * weights[weightIndex];
			pixelColor = pixelColor * tone;
			if( flipped ) pixelColor.rgb = pixelColor.bgr;
		}
	};
	override function updateConstantsFinal(globals:hxsl.Globals) {
		preparations++;
		super.updateConstantsFinal(globals);
	}
}

private class GlobalProbe extends hxsl.Shader {
	public var preparations = 0;
	static var SRC = {
		@const @global var probeMode : Bool;
		var pixelColor : Vec4;
		function fragment() { if( probeMode ) pixelColor.rgb = pixelColor.bgr; }
	};
	override function updateConstantsFinal(globals:hxsl.Globals) {
		preparations++;
		super.updateConstantsFinal(globals);
	}
}

private class ChannelProbe extends hxsl.Shader {
	public var preparations = 0;
	static var SRC = {
		@param var source : Channel;
		var calculatedUV : Vec2;
		var pixelColor : Vec4;
		function fragment() { pixelColor *= source.get(calculatedUV); }
	};
	override function updateConstantsFinal(globals:hxsl.Globals) {
		preparations++;
		super.updateConstantsFinal(globals);
	}
}

private class NestedProbe extends hxsl.Shader {
	static var SRC = {
		@param var settings : { @const var flipped : Bool; };
		var pixelColor : Vec4;
		function fragment() { if( settings.flipped ) pixelColor.rgb = pixelColor.bgr; }
	};
}

private class ProbeOutput extends h3d.pass.Output {
	public var forceUploads = false;
	public var vertices : Array<UploadCounter> = [];
	public var fragments : Array<UploadCounter> = [];

	public function new() super("default");

	function counter(cache:h3d.impl.driver.ShaderParamCache, vertex:Bool) {
		var result = Std.downcast(cache, UploadCounter);
		if( result == null ) result = new UploadCounter();
		var list = vertex ? vertices : fragments;
		if( list.indexOf(result) < 0 ) {
			result = new UploadCounter();
			list.push(result);
		}
		result.forceUploads = forceUploads;
		return result;
	}

	override function setupShader(shader:hxsl.RuntimeShader) {
		super.setupShader(shader);
		var driver = ctx.engine.driver;
		#if gfx_dx12
		if( Std.isOfType(driver, h3d.impl.driver.dx12.DX12Driver) ) @:privateAccess {
			var d:h3d.impl.driver.dx12.DX12Driver = cast driver;
			var s = d.currentShader;
			s.vertexRegisters.paramsCache = counter(s.vertexRegisters.paramsCache, true);
			s.fragmentRegisters.paramsCache = counter(s.fragmentRegisters.paramsCache, false);
		}
		#end
		#if gfx_opengl
		if( Std.isOfType(driver, h3d.impl.driver.opengl.OpenGLDriver) ) @:privateAccess {
			var d:h3d.impl.driver.opengl.OpenGLDriver = cast driver;
			var s = d.curShader;
			s.vertex.paramsCache = counter(s.vertex.paramsCache, true);
			s.fragment.paramsCache = counter(s.fragment.paramsCache, false);
		}
		#end
		#if gfx_vulkan
		if( Std.isOfType(driver, h3d.impl.driver.vulkan.VulkanDriver) ) @:privateAccess {
			var d:h3d.impl.driver.vulkan.VulkanDriver = cast driver;
			var s = d.currentShader;
			var frame = d.frames[d.currentFrameIndex];
			for( block in s.programLayout.constantBlocks ) {
				if( block.frequency != h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanConstantFrequency.Params ) continue;
				var id = s.constantBlockIds.get(block);
				var upload = frame.shaderConstants.get(id);
				if( upload == null ) {
					upload = new h3d.impl.driver.vulkan.transfer.VulkanUploadManager.VulkanConstantUpload();
					frame.shaderConstants.set(id, upload);
				}
				upload.paramsCache = counter(upload.paramsCache, block.stage == h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanShaderStage.Vertex);
			}
		}
		#end
	}
}

private class ProbeRenderer extends h3d.scene.fwd.Renderer {
	public var probe : ProbeOutput;
	public function new() {
		super();
		probe = new ProbeOutput();
		defaultPass = probe;
		allPasses = [defaultPass, depth, normal, shadow];
	}
}

private class ProbeMesh extends h3d.scene.Mesh {
	public var owner : ShaderUploads;
	override function draw(ctx:h3d.scene.RenderContext) {
		owner.draws++;
		if( owner.mode == "dynamic" ) {
			owner.probe.tint.x = owner.draws % 2 == 0 ? 0.25 : 1.;
			ctx.uploadParams();
		}
		super.draw(ctx);
		if( owner.draws == 128 ) {
			switch( owner.mode ) {
			case "vector": owner.probe.tint.x = 0.25;
			case "matrix": owner.probe.tone._11 = 0.25;
			case "array": owner.probe.weights[3].y = 0.25;
				#if gfx_dx12
				case "heaps":
					var driver:h3d.impl.driver.dx12.DX12Driver = cast ctx.engine.driver;
					@:privateAccess driver.flushHeaps();
				#end
			default:
			}
		}
	}
}

class ShaderUploads extends hxd.App {
	public var draws = 0;
	public var mode = "static";
	public var probe = new MaterialProbe();
	var renderer : ProbeRenderer;
	var scene : h3d.scene.Scene;
	var material : h3d.mat.Material;
	var target : h3d.mat.Texture;
	var comparisons = 0;
	var cases = 0;

	static function require(value:Bool, message:String) {
		if( !value ) throw message;
	}

	function checkPreparation() {
		var globals = new hxsl.Globals();
		for( _ in 0...256 ) probe.updateConstants(globals);
		require(probe.preparations == 1, "Scalar constant preparation was repeated");
		probe.flipped = true;
		probe.updateConstants(globals);
		require(probe.preparations == 2, "Changed scalar constant was ignored");
		probe.setParamIndexValue(0, false);
		probe.updateConstants(globals);
		require(probe.preparations == 3 && !probe.flipped, "Indexed constant change was ignored");
		@:privateAccess var old = probe.instance;
		@:privateAccess require(probe.shader.applyChanges(probe.shader.data), "Shader reload failed");
		probe.updateConstants(globals);
		@:privateAccess require(probe.preparations == 4 && probe.instance != old, "Shader reload reused stale preparation");
		var clone:MaterialProbe = cast probe.clone();
		clone.updateConstants(globals);
		@:privateAccess require(clone.instance != null, "Cloned shader was not prepared");
		probe.flipped = true;

		var nested = new NestedProbe();
		var settings = nested.settings;
		nested.updateConstants(globals);
		@:privateAccess var nestedBefore = nested.instance;
		settings.flipped = true;
		nested.updateConstants(globals);
		@:privateAccess require(nested.instance != nestedBefore, "Nested constant mutation was ignored");

		var globalProbe = new GlobalProbe();
		globals.set("probeMode", false);
		globalProbe.updateConstants(globals);
		@:privateAccess var before = globalProbe.instance;
		globals.set("probeMode", true);
		globalProbe.updateConstants(globals);
		@:privateAccess require(globalProbe.preparations == 2 && globalProbe.instance != before, "Global constants were cached");

		var channel = new ChannelProbe();
		channel.source = h3d.mat.Texture.fromColor(0xFFFFFF);
		channel.sourceChannel = R;
		globals.resetChannels();
		channel.updateConstants(globals);
		@:privateAccess var first = channel.instance;
		globals.resetChannels();
		globals.allocChannelID(h3d.mat.Texture.fromColor(0x000000));
		channel.updateConstants(globals);
		@:privateAccess require(channel.preparations == 2 && channel.instance != first, "Channel allocation was cached");
	}

	function checkBits() {
		var data = new h3d.shader.Buffers.ShaderBufferData(4);
		var words:hl.BytesAccess<Int> = hl.Bytes.getArray(data.toData());
		var cache = new h3d.impl.driver.ShaderParamCache();
		words[0] = 0x7FC00001;
		require(cache.update(data, 4) && !cache.update(data, 4), "Identical NaN payload was uploaded again");
		words[0] = 0x7FC00002;
		require(cache.update(data, 4), "Changed NaN payload was ignored");
		words[1] = 0x80000000;
		require(cache.update(data, 4), "Signed zero was ignored");
		require(cache.update(data, 4, true), "Forced rebind was ignored");
	}

	override function init() {
		checkPreparation();
		checkBits();
		scene = new h3d.scene.Scene(false, false);
		renderer = new ProbeRenderer();
		scene.renderer = renderer;
		scene.camera.pos.set(0, 0, 10);
		scene.camera.target.set(0, 0, 0);
		scene.camera.up.set(0, 1, 0);
		scene.camera.orthoBounds = h3d.col.Bounds.fromValues(-2, -2, 0.1, 4, 4, 20);
		material = h3d.mat.Material.create();
		material.shadows = false;
		material.mainPass.enableLights = false;
		material.mainPass.addShader(probe);
		probe.weights = [for( _ in 0...20 ) new h3d.Vector4(1, 1, 1, 1)];
		probe.weightIndex = 3;
		var cube = new h3d.prim.Cube(0.12, 0.12, 0.12, true);
		cube.addNormals();
		for( i in 0...256 ) {
			var mesh = new ProbeMesh(cube, material, scene);
			mesh.owner = this;
			mesh.setPosition((i % 16) * 0.18 - 1.35, Std.int(i / 16) * 0.18 - 1.35, 0);
		}
		target = new h3d.mat.Texture(128, 128, [Target], RGBA);
		target.depthBuffer = new h3d.mat.Texture(128, 128, [Target], Depth24);
	}

	function capture(e:h3d.Engine, force:Bool) {
		draws = 0;
		probe.tint.set(1, 1, 1, 1);
		probe.tone.identity();
		probe.weights[3].set(1, 1, 1, 1);
		renderer.probe.forceUploads = force;
		renderer.probe.vertices = [];
		renderer.probe.fragments = [];
		scene.setOutputTarget(e, target);
		e.clear(0, 1);
		scene.render(e);
		scene.setOutputTarget();
		require(draws == 256, "Objects were skipped");
		return target.capturePixels();
	}

	function check(e:h3d.Engine, name:String, expectedUploads:Int) {
		mode = name;
		material.mainPass.dynamicParameters = mode == "dynamic";
		var reference = capture(e, true);
		var actual = capture(e, false);
		var visible = 0;
		for( y in 0...128 ) for( x in 0...128 ) {
			var a = actual.getPixel(x, y), b = reference.getPixel(x, y);
			if( b >>> 24 != 0 ) visible++;
			require(a == b, '$mode pixel mismatch at $x,$y');
			comparisons++;
		}
		require(visible > 0, "Reference image is empty");
		var uploads = 0;
		for( cache in renderer.probe.fragments ) uploads += cache.uploads;
		if( renderer.probe.fragments.length > 0 ) {
			require(uploads == expectedUploads, '$mode: fragment uploads $uploads, expected $expectedUploads');
			var vertices = 0;
			for( cache in renderer.probe.vertices ) vertices += cache.uploads;
			require(vertices == 256, '$mode: object transforms were not updated');
			Sys.println('$mode: material uploads 256 -> $uploads, transforms=$vertices, pixels match');
		} else {
			Sys.println('$mode: existing DX11 parameter reuse, pixels match');
		}
		reference.dispose();
		actual.dispose();
		cases++;
	}

	override function render(e:h3d.Engine) {
		try {
			check(e, "static", 1);
			check(e, "vector", 2);
			check(e, "matrix", 2);
			check(e, "array", 2);
			check(e, "dynamic", 256);
			#if gfx_dx12
			if( Std.isOfType(e.driver, h3d.impl.driver.dx12.DX12Driver) ) check(e, "heaps", 2);
			#end
			probe.flipped = false;
			check(e, "static", 1);
			scene.dispose();
			target.depthBuffer.dispose();
			target.dispose();
			e.mem.dispose();
			e.dispose();
			Sys.println('PASS cases=$cases pixels=$comparisons preparation, reload, channels and bitwise comparisons');
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
		new ShaderUploads();
	}
}
