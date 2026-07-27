package h3d.impl.driver.vulkan.swapchain;

#if (limen && gfx_vulkan)
import limen.graphics.vulkan.command.Commands.VkFence;
import limen.graphics.vulkan.memory.Memory.VkDeviceMemory;
import limen.graphics.vulkan.memory.Memory.VkImage;
import limen.graphics.vulkan.memory.Memory.VkImageView;
import limen.graphics.vulkan.render.RenderPass.VkFramebuffer;

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
