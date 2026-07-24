package h3d.impl.driver.vulkan.shader;

#if (hlsdl && gfx_vulkan)
import sdl.Vulkan;

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
