package h3d.impl.driver.vulkan.frame;

#if (limen && gfx_vulkan)
import limen.graphics.vulkan.command.Commands.VkCommandBuffer;
import limen.graphics.vulkan.command.Commands.VkFence;
import limen.graphics.vulkan.command.Commands.VkSemaphore;
import limen.graphics.vulkan.command.Commands.VkSubmitInfo;

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
