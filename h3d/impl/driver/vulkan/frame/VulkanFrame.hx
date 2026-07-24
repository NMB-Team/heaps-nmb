package h3d.impl.driver.vulkan.frame;

#if (hlsdl && gfx_vulkan)
import sdl.Vulkan;

class VulkanFrame {
	public var command : VkCommandBuffer;
	public var fence : VkFence;
	public var submit : VkSubmitInfo;
	public var imageAvailable : VkSemaphore;
	public var renderFinished : VkSemaphore;

	public function new() {
	}
}
#end
