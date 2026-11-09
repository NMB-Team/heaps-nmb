package h3d.impl.driver.vulkan.resource;

#if (limen && gfx_vulkan)
import haxe.Int64;
import h3d.impl.driver.vulkan.memory.VulkanMemoryAllocator;
import limen.graphics.renderer.vulkan.memory.Memory.VkDeviceMemory;
import limen.graphics.renderer.vulkan.memory.Memory.VkMemoryPropertyFlag;
import limen.graphics.renderer.vulkan.memory.VmaMemoryAllocator as Vma;
import limen.graphics.renderer.vulkan.memory.VmaMemoryAllocator.AllocationHandle;
import limen.graphics.renderer.vulkan.internal.VulkanBindings.VkContext;

enum abstract VulkanMemoryClass(Int) {
	var DeviceBuffer;
	var DeviceImage;
	var Upload;
	var Readback;
}

class VulkanAllocation {
	@:allow(h3d.impl.driver.vulkan.memory.VulkanMemoryAllocator)
	final handle:AllocationHandle;
	public var memory(default, null):VkDeviceMemory;
	public var memoryType(default, null):Int;
	public var memoryProperties(default, null):Int;
	public var offset(default, null):Int64;
	public var size(default, null):Int64;
	public final debugId:Int;
	public final debugName:String;
	public var lastSubmission = 0;
	public var released(default, null) = false;

	@:allow(h3d.impl.driver.vulkan.memory.VulkanMemoryAllocator)
	final allocator:VulkanMemoryAllocator;
	var mapped:hl.Bytes;
	var owners = 1;

	public function new(allocator:VulkanMemoryAllocator, handle:AllocationHandle,
		context:VkContext, debugId:Int, debugName:String) {
		this.allocator = allocator;
		this.handle = handle;
		this.debugId = debugId;
		this.debugName = debugName;
		var type = 0;
		var memory:VkDeviceMemory = null;
		var offset:Int64 = 0, size:Int64 = 0;
		Vma.info(handle, type, memory, offset, size);
		this.memory = memory;
		this.memoryType = type;
		this.offset = offset;
		this.size = size;
		memoryProperties = context.getMemoryTypeProperties(type);
		Vma.setName(handle, debugName);
		if ((memoryProperties & (1 << Type.enumIndex(VkMemoryPropertyFlag.HOST_VISIBLE))) != 0) {
			var result = 0;
			mapped = Vma.map(handle, result);
			if (mapped == null)
				throw 'VMA mapping failed for $debugName: $result';
		}
	}

	public function mappedBytes(relativeOffset:Int, length:Int):hl.Bytes {
		if (released || relativeOffset < 0 || length < 0 || Int64.ofInt(relativeOffset) + length > size
			|| Int64.ofInt(relativeOffset) + length > 0x7FFFFFFF)
			throw 'Invalid HashLink mapped range for Vulkan allocation $debugName';
		if (mapped == null)
			throw 'Vulkan allocation $debugName is not host visible';
		return mapped.offset(relativeOffset);
	}

	public function writeMapped(relativeOffset:Int, source:hl.Bytes, sourceOffset:Int, length:Int):Void {
		if (released || relativeOffset < 0 || length < 0 || Int64.ofInt(relativeOffset) + length > size
			|| Int64.ofInt(relativeOffset) + length > 0x7FFFFFFF)
			throw 'Invalid HashLink mapped range for Vulkan allocation $debugName';
		if (mapped == null)
			throw 'Vulkan allocation $debugName is not host visible';
		mapped.blit(relativeOffset, source, sourceOffset, length);
	}

	public function flush(relativeOffset:Int, length:Int) {
		allocator.flush(this, Int64.ofInt(relativeOffset), Int64.ofInt(length));
	}

	public function invalidate(relativeOffset:Int, length:Int) {
		allocator.invalidate(this, Int64.ofInt(relativeOffset), Int64.ofInt(length));
	}

	@:allow(h3d.impl.driver.vulkan.VulkanDriver)
	function retain() {
		if (released) throw "Cannot retain released Vulkan memory";
		owners++;
	}

	public function dispose() {
		if (!released && --owners == 0)
			allocator.free(this);
	}

	@:allow(h3d.impl.driver.vulkan.memory.VulkanMemoryAllocator)
	function markReleased() {
		if (mapped != null) {
			Vma.unmap(handle);
			mapped = null;
		}
		Vma.release(handle);
		released = true;
	}
}
#end
