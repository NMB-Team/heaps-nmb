package h3d.impl.driver.vulkan.swapchain;

#if (hlsdl && gfx_vulkan)
import sdl.Vulkan;

class VulkanSwapchainImage {
	public var img : VkImage;
	public var view : VkImageView;
	public var depth : VkImage;
	public var depthView : VkImageView;
	public var depthMem : VkDeviceMemory;
	public var framebuffer : VkFramebuffer;
	public var fence : VkFence;

	public function new() {
	}
}
#end
