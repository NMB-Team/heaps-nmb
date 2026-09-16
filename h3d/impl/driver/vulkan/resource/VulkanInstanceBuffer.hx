package h3d.impl.driver.vulkan.resource;

#if (limen && gfx_vulkan)
import haxe.Int64;
import h3d.impl.driver.vulkan.resource.VulkanBuffer.VulkanBufferState;
import limen.graphics.vulkan.memory.Memory.VkBuffer;
import limen.graphics.vulkan.memory.Memory.VkBufferUsageFlag;

class VulkanInstanceBuffer extends VulkanBuffer {
	public static inline final COMMAND_STRIDE = 20;
	public final capacity:Int;
	final firstInstances:Array<Int>;

	public function new(buffer:VkBuffer, allocation:VulkanAllocation, size:Int64, usage:haxe.EnumFlags<VkBufferUsageFlag>, state:VulkanBufferState,
		debugId:Int, debugName:String, capacity:Int) {
		super(buffer, allocation, size, usage, COMMAND_STRIDE, state, debugId, debugName);
		this.capacity = capacity;
		firstInstances = [for (_ in 0...capacity) 0];
	}

	public function updateMetadata(startCommand:Int, commandCount:Int, bytes:hl.Bytes, sourceOffset:Int) {
		for (index in 0...commandCount)
			firstInstances[startCommand + index] = bytes.getI32(sourceOffset + index * COMMAND_STRIDE + 16);
	}

	public function hasNonZeroFirstInstance(startCommand:Int, commandCount:Int):Bool {
		for (index in startCommand...startCommand + commandCount)
			if (firstInstances[index] != 0)
				return true;
		return false;
	}
}
#end
