package h3d.impl.driver.vulkan.pipeline;

#if (limen && gfx_vulkan)
import h3d.impl.driver.vulkan.shader.VulkanCompiledShader;
import limen.graphics.vulkan.Runtime;
import limen.graphics.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.vulkan.pipeline.Pipeline.VkComputePipeline;
import limen.graphics.vulkan.pipeline.Pipeline.VkComputePipelineCreateInfo;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineShaderStage;
import limen.graphics.vulkan.shader.ShaderModule.VkShaderStageFlag;

class VulkanComputePipeline {
	public final program:VulkanCompiledShader;
	public final layout:limen.graphics.vulkan.pipeline.Pipeline.VkPipelineLayout;
	public final handle:VkComputePipeline;
	public final cacheKey:String;
	public final debugName:String;
	public var lastSubmission:haxe.Int64 = 0;

	public function new(program:VulkanCompiledShader, handle:VkComputePipeline, cacheKey:String, debugName:String) {
		this.program = program;
		this.layout = program.layout;
		this.handle = handle;
		this.cacheKey = cacheKey;
		this.debugName = debugName;
	}
}

class VulkanComputePipelineManager {
	static final ENTRY_POINT = @:privateAccess "main".toUtf8();

	final context:VkContext;
	final pipelines:Map<String, VulkanComputePipeline> = new Map();
	public var createdCount(default, null) = 0;
	public var hitCount(default, null) = 0;

	public function new(context:VkContext) {
		this.context = context;
	}

	public function get(program:VulkanCompiledShader):VulkanComputePipeline {
		if (program.compute == null || program.vertex != null || program.fragment != null)
			throw "Vulkan compute pipeline requires one compute-only shader program";
		final key = '${program.cacheKey}:${program.abiVersion}:${program.pipelineLayoutIdentity}:specialization=none';
		final cached = pipelines.get(key);
		if (cached != null) {
			hitCount++;
			return cached;
		}
		final stage = new VkPipelineShaderStage();
		stage.stage.set(VkShaderStageFlag.COMPUTE);
		stage.module = program.compute.handle;
		stage.name = ENTRY_POINT;
		final info = new VkComputePipelineCreateInfo();
		info.stage = stage;
		info.layout = program.layout;
		final handle = context.createComputePipeline(info);
		if (handle == null)
			throw Runtime.error('Failed to create Vulkan compute pipeline for ${program.cacheKey}');
		final pipeline = new VulkanComputePipeline(program, handle, key, 'hxsl-compute-${program.cacheKey.substr(0, 16)}');
		pipelines.set(key, pipeline);
		createdCount++;
		return pipeline;
	}

	public function dispose() {
		for (pipeline in pipelines)
			context.destroyComputePipeline(pipeline.handle);
		pipelines.clear();
	}
}
#end
