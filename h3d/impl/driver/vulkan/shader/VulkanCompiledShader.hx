package h3d.impl.driver.vulkan.shader;

#if (limen && gfx_vulkan)
import limen.graphics.vulkan.VulkanCore.ArrayStruct;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSet;
import limen.graphics.vulkan.pipeline.Pipeline.VkGraphicsPipeline;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineLayout;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineShaderStage;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineVertexInput;

class VulkanCompiledShader {
	public var shader : hxsl.RuntimeShader;
	public var vertex : VulkanShaderStageData;
	public var fragment : VulkanShaderStageData;
	public var stages : ArrayStruct<VkPipelineShaderStage>;
	public var input : VkPipelineVertexInput;
	public var format : hxd.BufferFormat;
	public var layout : VkPipelineLayout;
	public var samplerSets : hl.NativeArray<VkDescriptorSet>;
	public var samplerTextures : Array<h3d.mat.Texture>;
	public var pipelines : Map<Int,VkGraphicsPipeline> = new Map();

	public function new(shader) {
		this.shader = shader;
	}
}
#end
