package h3d.impl.driver.vulkan.shader;

#if (limen && gfx_vulkan)
import limen.graphics.vulkan.shader.ShaderModule.VkShaderModule;
import limen.graphics.vulkan.shader.ShaderModule.VkShaderStageFlag;

class VulkanShaderStageData {
	public var vertex : Bool;
	public var module : VkShaderModule;
	public var stageFlags : haxe.EnumFlags<VkShaderStageFlag>;
	public var pushConstantsOffset : Int;
	public var globalsOffset : Int;

	public function new() {
	}
}
#end
