package h3d.impl.driver.vulkan.resource;

#if (limen && gfx_vulkan)
import haxe.Int64;
import h3d.impl.driver.vulkan.memory.VulkanMemoryAllocator;
import limen.graphics.vulkan.memory.Memory.VkDeviceMemory;

enum abstract VulkanMemoryClass(Int) {
	var DeviceBuffer;
	var DeviceImage;
	var Upload;
	var Readback;
}

class VulkanMemoryRange {
	public var offset:Int64;
	public var size:Int64;

	public function new(offset:Int64, size:Int64) {
		this.offset = offset;
		this.size = size;
	}
}

class VulkanMemoryBlock {
	public var id(default, null):Int;
	public var memory(default, null):VkDeviceMemory;
	public var size(default, null):Int64;
	public var memoryType(default, null):Int;
	public var memoryProperties(default, null):Int;
	public var memoryClass(default, null):VulkanMemoryClass;
	public var mapped(default, null):hl.Bytes;
	public var dedicated(default, null):Bool;
	public var freeRanges:Array<VulkanMemoryRange>;
	public var liveAllocations = 0;

	public function new(id:Int, memory:VkDeviceMemory, size:Int64, memoryType:Int, memoryProperties:Int, memoryClass:VulkanMemoryClass, mapped:hl.Bytes, dedicated:Bool) {
		this.id = id;
		this.memory = memory;
		this.size = size;
		this.memoryType = memoryType;
		this.memoryProperties = memoryProperties;
		this.memoryClass = memoryClass;
		this.mapped = mapped;
		this.dedicated = dedicated;
		freeRanges = dedicated ? [] : [new VulkanMemoryRange(0, size)];
	}
}

class VulkanAllocation {
	public var memory(get, never):VkDeviceMemory;
	public var memoryType(get, never):Int;
	public var memoryProperties(get, never):Int;
	public var blockId(get, never):Int;
	public var offset(default, null):Int64;
	public var size(default, null):Int64;
	public var dedicated(get, never):Bool;
	public var debugId(default, null):Int;
	public var debugName(default, null):String;
	public var lastSubmission = 0;
	public var released(default, null) = false;

	final allocator:VulkanMemoryAllocator;
	final block:VulkanMemoryBlock;

	public function new(allocator:VulkanMemoryAllocator, block:VulkanMemoryBlock, offset:Int64, size:Int64, debugId:Int, debugName:String) {
		this.allocator = allocator;
		this.block = block;
		this.offset = offset;
		this.size = size;
		this.debugId = debugId;
		this.debugName = debugName;
		block.liveAllocations++;
	}

	inline function get_memory():VkDeviceMemory {
		return block.memory;
	}

	inline function get_memoryType():Int {
		return block.memoryType;
	}

	inline function get_memoryProperties():Int {
		return block.memoryProperties;
	}

	inline function get_blockId():Int {
		return block.id;
	}

	inline function get_dedicated():Bool {
		return block.dedicated;
	}

	public function mappedBytes(relativeOffset:Int, length:Int):hl.Bytes {
		if (released)
			throw 'Vulkan allocation $debugName has already been released';
		if (block.mapped == null)
			throw 'Vulkan allocation $debugName is not host visible';
		if (relativeOffset < 0 || length < 0 || Int64.ofInt(relativeOffset) + length > size)
			throw 'Mapped range [$relativeOffset, ${relativeOffset + length}) exceeds Vulkan allocation $debugName ($size bytes)';
		final absolute = offset + relativeOffset;
		if (absolute.high != 0)
			throw 'Mapped Vulkan allocation offset exceeds the HashLink byte-addressable range: $absolute';
		return block.mapped.offset(absolute.low);
	}

	public function flush(relativeOffset:Int, length:Int) {
		allocator.flush(this, Int64.ofInt(relativeOffset), Int64.ofInt(length));
	}

	public function invalidate(relativeOffset:Int, length:Int) {
		allocator.invalidate(this, Int64.ofInt(relativeOffset), Int64.ofInt(length));
	}

	public function dispose() {
		if (!released)
			allocator.free(this);
	}

	@:allow(h3d.impl.driver.vulkan.memory.VulkanMemoryAllocator)
	function markReleased() {
		released = true;
		block.liveAllocations--;
	}

	@:allow(h3d.impl.driver.vulkan.memory.VulkanMemoryAllocator)
	inline function getBlock():VulkanMemoryBlock {
		return block;
	}
}
#end
