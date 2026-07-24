package h3d.impl.driver.vulkan.shader;

#if (hlsdl && gfx_vulkan)
import sdl.Vulkan;

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
