//TARGETS=hlvulkan
import h3d.impl.driver.vulkan.pipeline.VulkanGraphicsPipeline;
import h3d.impl.driver.vulkan.shader.VulkanCompiledShader;

private class LifetimeCompute extends hxsl.Shader {
	static var SRC = { function compute() {} };
}

@:access(h3d.impl.driver.vulkan.VulkanDriver)
class VulkanPipelineLifetimeDiagnostic extends hxd.App {
	var frame = 0;
	static function check(value:Bool, message:String) {
		if (!value) throw message;
	}
	override function init() {
		var cube = new h3d.prim.Cube();
		cube.addNormals();
		cube.addUVs();
		new h3d.scene.Mesh(cube, s3d);
	}
	override function update(dt:Float) {
		if (++frame != 3) return;
		try {
			final d:h3d.impl.driver.vulkan.VulkanDriver = cast engine.driver;
			final desc = d.pipelineDescription.snapshot();
			final count = 2048;
			final start = haxe.Timer.stamp();
			final graphics = d.pipelineManager;
			final compute = d.computePipelineManager;
			final beforeGraphics = graphics.createdCount;
			final shader = new LifetimeCompute();
			shader.updateConstants(new hxsl.Globals());
			final runtime = hxsl.Cache.get().link(new hxsl.ShaderList(shader), Compute);
			d.selectShader(runtime);
			final base = d.currentShader;
			final programs:Array<VulkanCompiledShader> = [];
			for (i in 0...count) {
				final p = new VulkanCompiledShader(base.shader, 'lifetime-$i', base.abi, null, null, base.compute,
					base.stages, base.descriptorSetLayouts, base.layout, base.pipelineLayoutIdentity);
				programs.push(p);
				compute.get(p, d.currentSubmissionSerial);
				compute.get(p, d.currentSubmissionSerial);
				desc.update(desc.program, new VulkanVertexLayout([for (b in desc.vertexLayout.bindings) new VulkanVertexBinding(b.binding, i)], desc.vertexLayout.attributes),
					desc.colorFormats, desc.depthFormat, desc.stencilFormat, desc.samples, desc.blend, desc.colorMasks,
					desc.stencil, desc.depthClamp, desc.wireframe);
				graphics.get(desc, d.currentSubmissionSerial);
				graphics.get(desc, d.currentSubmissionSerial);
			}
			check(graphics.createdCount >= beforeGraphics + count - 1, 'graphics variant count');
			check(compute.createdCount == count, 'compute variant count');
			final createdSeconds = haxe.Timer.stamp() - start;
			graphics.reclaimUnused(hxd.Timer.frameCount + 1, d.completedSubmissionSerial, d.deferredDestroy);
			compute.reclaimUnused(hxd.Timer.frameCount + 1, d.completedSubmissionSerial, d.deferredDestroy);
			check(compute.reclaimedCount == 0, 'in-flight compute retained');
			d.ctx.waitIdle();
			graphics.reclaimUnused(hxd.Timer.frameCount + 1, d.currentSubmissionSerial, d.deferredDestroy);
			compute.reclaimUnused(hxd.Timer.frameCount + 1, d.currentSubmissionSerial, d.deferredDestroy);
			d.deferredDestroy.collect(d.currentSubmissionSerial);
			check(compute.reclaimedCount == count, 'compute reclamation');
			final before = graphics.createdCount;
			graphics.get(desc, d.currentSubmissionSerial);
			compute.get(programs[0], d.currentSubmissionSerial);
			check(graphics.createdCount == before + 1 && compute.createdCount == count + 1, 'recreation');
			Sys.println(haxe.Json.stringify({variantsPerKind:count, createSeconds:createdSeconds,
				graphicsReclaimed:graphics.reclaimedCount, computeReclaimed:compute.reclaimedCount,
				graphicsHits:graphics.hitCount, computeHits:compute.hitCount}));
			engine.dispose();
			Sys.exit(0);
		} catch (error:Dynamic) {
			Sys.stderr().writeString('Pipeline lifetime diagnostic failed: $error\n');
			Sys.exit(1);
		}
	}
	static function main() {
		hxd.GraphicsDriverConfig.setCurrent(Vulkan);
		limen.graphics.renderer.vulkan.internal.VulkanBindings.ENABLE_VALIDATION = Sys.args().indexOf('--validation') >= 0;
		new VulkanPipelineLifetimeDiagnostic();
	}
}
