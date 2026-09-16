package h3d.impl.driver.vulkan.swapchain;

#if (limen && gfx_vulkan)
import limen.graphics.vulkan.command.Commands.VkFence;
import limen.graphics.vulkan.command.Commands.VkSemaphore;
import h3d.impl.driver.vulkan.resource.VulkanAllocation;
import limen.graphics.vulkan.memory.Memory.VkImage;
import limen.graphics.vulkan.memory.Memory.VkImageView;
import limen.graphics.vulkan.memory.Memory.VkImageLayout;
import h3d.impl.driver.vulkan.resource.VulkanImage.VulkanTexture;
import h3d.impl.driver.vulkan.attachment.VulkanRenderingTargetSet;

class VulkanSwapchainImage {
	public var img : VkImage;
	public var view : VkImageView;
	public var depth : VkImage;
	public var depthView : VkImageView;
	public var depthAllocation : VulkanAllocation;
	public var depthResource : VulkanTexture;
	public var colorLayout : VkImageLayout = UNDEFINED;
	public var fence : VkFence;
	public var renderFinished : VkSemaphore;
	public var initialized = false;
	public var defaultTargets:Array<VulkanRenderingTargetSet> = [];
	public var defaultDepthTexture:h3d.mat.Texture;

	public function new() {
	}
}
#end
