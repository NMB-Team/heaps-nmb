package h3d.impl.driver.vulkan.resource;

#if (limen && gfx_vulkan)
import limen.graphics.renderer.vulkan.internal.VulkanBindings.VkContext;

private class VulkanRetiredResource {
	public var serial:Int;
	public var destroy:Void->Void;

	public function new(serial:Int, destroy:Void->Void) {
		this.serial = serial;
		this.destroy = destroy;
	}
}

class VulkanDeferredDestroyQueue {
	final retired:Array<VulkanRetiredResource> = [];
	final buffers:Array<VulkanBuffer> = [];

	public var pendingCount(get, never):Int;

	inline function get_pendingCount():Int {
		return retired.length + buffers.length;
	}

	public function new() {}

	public function retire(serial:Int, destroy:Void->Void) {
		retired.push(new VulkanRetiredResource(serial, destroy));
	}

	public function retireBuffer(buffer:VulkanBuffer) {
		buffers.push(buffer);
	}

	public function collect(completedSerial:Int, context:VkContext) {
		var readIndex = 0;
		var writeIndex = 0;
		while (readIndex < retired.length) {
			final resource = retired[readIndex++];
			if (resource.serial <= completedSerial) {
				resource.destroy();
			} else {
				retired[writeIndex++] = resource;
			}
		}
		retired.resize(writeIndex);

		writeIndex = 0;
		for (buffer in buffers) {
			if (buffer.lastSubmission <= completedSerial) {
				context.destroyBuffer(buffer.buffer);
				buffer.allocation.dispose();
			} else
				buffers[writeIndex++] = buffer;
		}
		buffers.resize(writeIndex);
	}

	public function drain(context:VkContext) {
		for (resource in retired)
			resource.destroy();
		retired.resize(0);

		for (buffer in buffers) {
			context.destroyBuffer(buffer.buffer);
			buffer.allocation.dispose();
		}
		buffers.resize(0);
	}
}
#end
