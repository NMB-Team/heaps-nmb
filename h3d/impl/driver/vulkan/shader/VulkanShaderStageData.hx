package h3d.impl.driver.vulkan.shader;

#if (limen && gfx_vulkan)
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanShaderStage;
import h3d.impl.driver.vulkan.shader.VulkanShaderCompilerService.VulkanCompiledStageSource;
import limen.graphics.vulkan.shader.ShaderModule;
import limen.graphics.vulkan.shader.ShaderModule.VkShaderModule;

class VulkanShaderStageData {
	public final stage:VulkanShaderStage;
	public final source:VulkanCompiledStageSource;
	public final module:ShaderModule;
	public var handle(get, never):VkShaderModule;

	public function new(stage:VulkanShaderStage, source:VulkanCompiledStageSource, module:ShaderModule) {
		this.stage = stage;
		this.source = source;
		this.module = module;
	}

	inline function get_handle() {
		return module.handle;
	}

	public function dispose() {
		module.dispose();
	}
}
#end
