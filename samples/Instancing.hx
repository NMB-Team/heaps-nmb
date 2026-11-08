//TARGETS=hl,hldx11,hldx12,hlvulkan
private class InstanceAllocator extends hxd.impl.Allocator {
	public var floatAllocations = 0;
	override public function allocFloats(count:Int) {
		floatAllocations++;
		return super.allocFloats(count);
	}
}

private class MaterialCube extends h3d.prim.Cube {
	var selectedMaterial = 0;
	public function new() {
		super(0.4, 0.4, 0.4, true);
		addNormals();
	}
	override public function getMaterialIndexStart(material:Int, lod = 0) return material * 12;
	override public function getMaterialIndexCount(material:Int, lod = 0) return 12;
	override public function selectMaterial(material:Int, lod:Int) selectedMaterial = material;
	override public function render(e:h3d.Engine) {
		if( buffer == null || buffer.isDisposed() ) alloc(e);
		var indices = indexes == null ? e.mem.getTriIndexes(triCount() * 3) : indexes;
		if( buffers == null ) e.renderIndexed(buffer, indices, selectedMaterial * 4, 4);
		else e.renderMultiBuffers(formats, buffers, indices, selectedMaterial * 4, 4);
	}
}

class Instancing extends hxd.App {
	var allocator = new InstanceAllocator();
	var previousAllocator : hxd.impl.Allocator;
	var frame = 0;
	var cpuScene : h3d.scene.Scene;
	var gpuScene : h3d.scene.Scene;
	var referenceScene : h3d.scene.Scene;
	var cpu : h3d.scene.MeshBatch;
	var gpu : h3d.scene.GPUMeshBatch;
	var reference : Array<h3d.scene.Mesh> = [];
	var targets : Array<h3d.mat.Texture> = [];
	var submeshes : Bool;
	var gpuSupported : Bool;
	var textured : Bool;
	var batchTexture : h3d.mat.Texture;
	var count = 64;
	var comparisons = 0;
	var steadyAllocations = 0;
	var steadyFloatAllocations = 0;
	var initialBufferMemory : Float;

	function scene() {
		var s = new h3d.scene.Scene();
		s.camera.pos.set(0, 0, 10);
		s.camera.target.set(0, 0, 0);
		s.camera.up.set(0, 1, 0);
		s.camera.orthoBounds = h3d.col.Bounds.fromValues(-3, -3, 0.1, 6, 6, 20);
		return s;
	}

	function materials() {
		return [for( color in (submeshes ? [0xFF4040, 0x40FF40, 0x4040FF] : [0x80C0FF]) ) {
			var m = h3d.mat.Material.create(batchTexture);
			m.shadows = false;
			m.mainPass.enableLights = false;
			m.mainPass.culling = None;
			m.color.setColor(0xFF000000 | color);
			m;
		}];
	}

	override function init() {
		previousAllocator = hxd.impl.Allocator.get();
		hxd.impl.Allocator.set(allocator);
		hxd.Window.getInstance().presentMode = Immediate;
		initialBufferMemory = engine.mem.bufferMemory;
		submeshes = Sys.args().indexOf("--submeshes") >= 0;
		textured = Sys.args().indexOf("--textures") >= 0;
		if( textured ) batchTexture = h3d.mat.Texture.fromColor(0xFFFFFF);
		for( _ in 0...3 ) {
			var target = new h3d.mat.Texture(128, 128, [Target], RGBA);
			target.depthBuffer = new h3d.mat.Texture(128, 128, [Target], Depth24);
			targets.push(target);
		}
		cpuScene = scene();
		gpuScene = scene();
		referenceScene = scene();
		var primitive:h3d.prim.MeshPrimitive;
		if( submeshes ) primitive = new MaterialCube(); else {
			var cube = new h3d.prim.Cube(0.4, 0.4, 0.4, true);
			cube.addNormals();
			primitive = cube;
		}
		if( textured ) (cast primitive : h3d.prim.Cube).addUVs();
		var cpuMaterials = materials();
		cpu = new h3d.scene.MeshBatch(primitive, cpuMaterials[0], cpuScene);
		cpu.materials = cpuMaterials;
		if( textured ) cpu.enablePerInstanceTexture();
		if( Sys.args().indexOf("--storage") >= 0 ) cpu.enableStorageBuffer();
		gpuSupported = engine.driver.hasFeature(ComputeShaders);
		if( gpuSupported ) {
			var gpuMaterials = materials();
			gpu = new h3d.scene.GPUMeshBatch(primitive, gpuMaterials[0], gpuScene);
			gpu.materials = gpuMaterials;
			if( textured ) gpu.enablePerInstanceTexture();
			gpu.enableGpuCulling();
		}
		if( submeshes && gpuSupported ) {
			var sub = new h3d.scene.MeshBatch.SubMesh();
			sub.bounds = primitive.getBounds();
			sub.lodCount = 2;
			sub.lodConfig = [0.0];
			sub.subParts = [];
			for( i in 0...4 ) {
				var part = new h3d.scene.MeshBatch.SubPart();
				part.matIndex = i < 2 ? 0 : i - 1;
				part.indexStart = i < 2 ? i * 6 : (i - 1) * 12;
				part.indexCount = i < 2 ? 6 : 12;
				part.lodIndexStart = [part.indexStart];
				part.lodIndexCount = [part.indexCount];
				sub.subParts.push(part);
			}
			gpu.primitiveSubMeshes = [sub];
		}
		var referenceMaterials = materials();
		for( _ in 0...count ) reference.push(new h3d.scene.MultiMaterial(primitive, referenceMaterials, referenceScene));
	}

	function emit() {
		cpu.begin(frame == 0 ? 0 : count);
		if( gpuSupported ) gpu.begin(frame == 0 ? 0 : count);
		if( frame == 0 && gpuSupported ) gpu.flush();
		for( i in 0...reference.length ) reference[i].visible = i < count;
		for( i in 0...count ) {
			var m = reference[i];
			m.setPosition((i % 8) * 0.6 - 2.1, Std.int(i / 8) * 0.6 - 2.1, 0);
			if( i >= count >> 1 ) m.x += 100;
			m.setRotation(0, 0, frame * 0.003);
			var position = m.getAbsPos();
			cpu.worldPosition = position;
			cpu.emitInstance();
			if( gpuSupported ) {
				gpu.worldPosition = position;
				gpu.curSubMesh = 0;
				gpu.emitInstance();
			}
		}
	}

	function draw(e:h3d.Engine, s:h3d.scene.Scene, target:h3d.mat.Texture) {
		s.setOutputTarget(e, target);
		e.clear(0, 1);
		var before = e.drawCalls;
		s.render(e);
		var calls = e.drawCalls - before;
		s.setOutputTarget();
		return calls;
	}

	function compare(name:String, actual:h3d.mat.Texture, expected:h3d.mat.Texture) {
		var a = actual.capturePixels(), b = expected.capturePixels();
		var visiblePixels = 0;
		for( y in 0...128 ) for( x in 0...128 ) {
			var got = a.getPixel(x, y), want = b.getPixel(x, y);
			if( want >>> 24 != 0 ) visiblePixels++;
			for( shift in [0, 8, 16, 24] )
				if( Math.abs(((got >>> shift) & 255) - ((want >>> shift) & 255)) > 1 )
					throw '$name frame $frame pixel $x,$y: ${StringTools.hex(got)} != ${StringTools.hex(want)}';
			comparisons++;
		}
		if( visiblePixels == 0 ) throw "Reference image is empty";
		a.dispose();
		b.dispose();
	}

	override function render(e:h3d.Engine) {
		try run(e) catch( error : Dynamic ) {
			Sys.println('FAIL: $error');
			Sys.exit(1);
		}
	}

	function run(e:h3d.Engine) {
		count = 64 - (frame % 3) * 16;
		if( frame == 8 && submeshes && gpuSupported ) gpu.enableGpuLod();
		if( frame == 12 ) {
			cpu.shadersChanged = true;
			if( gpuSupported ) gpu.shadersChanged = true;
		}
		if( frame == 21 && gpuSupported ) @:privateAccess {
			gpu.commandBuffer.dispose();
			gpu.gpuCounter.dispose();
			gpu.subPartsInfos.dispose();
			if( submeshes ) {
				gpu.subMeshesInfos.dispose();
				gpu.gpuInstancesInfos.dispose();
			}
		}
		var before = h3d.Buffer.GUID;
		var floatsBefore = allocator.floatAllocations;
		emit();
		var referenceCalls = draw(e, referenceScene, targets[0]);
		var cpuCalls = draw(e, cpuScene, targets[1]);
		var gpuCalls = gpuSupported ? draw(e, gpuScene, targets[2]) : 0;
		var expectedCalls = submeshes ? 3 : 1;
		if( cpuCalls != expectedCalls || (gpuSupported && gpuCalls != expectedCalls) || referenceCalls != count * expectedCalls )
			throw 'Unexpected draws: reference=$referenceCalls cpu=$cpuCalls gpu=$gpuCalls';
		if( frame > 2 && frame != 8 && frame != 12 && frame != 21 ) {
			var allocated = h3d.Buffer.GUID - before;
			var floatsAllocated = allocator.floatAllocations - floatsBefore;
			steadyAllocations += allocated;
			steadyFloatAllocations += floatsAllocated;
			if( allocated != 0 ) throw 'Frame $frame: $allocated unexpected buffer allocations';
			if( floatsAllocated != 0 ) throw 'Frame $frame: $floatsAllocated unexpected float-buffer allocations';
		}
		if( textured ) @:privateAccess {
			for( batch in (gpuSupported ? [cpu, gpu] : [cpu]) ) {
				var pass = batch.dataPasses;
				while( pass != null ) {
					if( pass.textureHandles.length != count ) throw 'Retained texture handles from earlier frames';
					pass = pass.next;
				}
			}
		}
		if( frame % 8 == 0 || frame == 12 || frame == 21 || frame == 31 ) {
			compare("CPU", targets[1], targets[0]);
			if( gpuSupported ) {
				var visible = gpu.gpuCounter.getAll();
				for( i in 0...visible.length ) {
					var expected = (count >> 1) * (submeshes && i == 0 ? 2 : 1);
					if( visible[i] != expected ) throw 'Material $i: ${visible[i]} visible commands, expected $expected';
				}
				compare("GPU", targets[2], targets[0]);
			}
		}
		if( ++frame < 32 ) return;
		var instanceBuffers = [];
		@:privateAccess var pass = cpu.dataPasses;
		while( pass != null ) {
			for( buffer in pass.buffers ) instanceBuffers.push(buffer);
			pass = pass.next;
		}
		cpu.begin(0);
		cpu.disposeBuffers();
		for( buffer in instanceBuffers ) if( !buffer.isDisposed() ) throw "Empty batch retained instance buffers";
		cpuScene.dispose();
		gpuScene.dispose();
		referenceScene.dispose();
		if( batchTexture != null ) batchTexture.dispose();
		for( target in targets ) {
			target.depthBuffer.dispose();
			target.dispose();
		}
		if( e.mem.bufferMemory != initialBufferMemory ) throw 'Buffer leak: ${e.mem.bufferMemory - initialBufferMemory} bytes';
		Sys.println(haxe.Json.stringify({api: Sys.args()[0], gpu: gpuSupported, submeshes: submeshes, textured: textured,
			frames: frame, pixels: comparisons, steadyAllocations: steadyAllocations, steadyFloatAllocations: steadyFloatAllocations}));
		hxd.impl.Allocator.set(previousAllocator);
		e.mem.dispose();
		e.dispose();
		Sys.println(gpuSupported ? "PASS CPU/GPU instancing, culling, LOD, shader rebuild and resource reuse" : "PASS CPU instancing, shader rebuild and resource reuse");
		Sys.exit(0);
	}

	static function main() {
		hxd.GraphicsDriverConfig.setCurrent(switch( Sys.args()[0] ) {
			case "dx11": Dx11;
			case "dx12": Dx12;
			case "vulkan": Vulkan;
			default: OpenGL;
		});
		if( Sys.args().indexOf("--textures") >= 0 && !h3d.impl.driver.Driver.requestFeature(Bindless) )
			throw "Bindless textures are unavailable";
		new Instancing();
	}
}
