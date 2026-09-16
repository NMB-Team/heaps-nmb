package h3d.impl.driver.vulkan.memory;

#if (limen && gfx_vulkan)
import haxe.Int64;
import h3d.impl.driver.vulkan.resource.VulkanAllocation;
import h3d.impl.driver.vulkan.resource.VulkanAllocation.VulkanMemoryBlock;
import h3d.impl.driver.vulkan.resource.VulkanAllocation.VulkanMemoryClass;
import h3d.impl.driver.vulkan.resource.VulkanAllocation.VulkanMemoryRange;
import limen.graphics.vulkan.Runtime;
import limen.graphics.vulkan.device.DeviceLimits.VkPhysicalDeviceLimits;
import limen.graphics.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.vulkan.memory.Memory.VkBuffer;
import limen.graphics.vulkan.memory.Memory.VkImage;
import limen.graphics.vulkan.memory.Memory.VkMemoryPropertyFlag;
import limen.graphics.vulkan.memory.Memory.VkMemoryRequirementsInfo;

class VulkanAllocatorConfig {
	public var deviceBufferPageSize:Int64;
	public var deviceImagePageSize:Int64;
	public var uploadPageSize:Int64;
	public var readbackPageSize:Int64;
	public var dedicatedThreshold:Int64;

	public function new(deviceBufferPageSize:Int64 = 4 << 20, deviceImagePageSize:Int64 = 8 << 20, uploadPageSize:Int64 = 2 << 20, readbackPageSize:Int64 = 1 << 20,
		dedicatedThreshold:Int64 = 32 << 20) {
		this.deviceBufferPageSize = deviceBufferPageSize;
		this.deviceImagePageSize = deviceImagePageSize;
		this.uploadPageSize = uploadPageSize;
		this.readbackPageSize = readbackPageSize;
		this.dedicatedThreshold = dedicatedThreshold;
	}
}

class VulkanMemoryAllocator {
	public var cleanupCallback:Void->Bool;
	public var reservedBytes(default, null):Int64 = 0;
	public var usedBytes(default, null):Int64 = 0;
	public var allocationCount(default, null) = 0;
	public var blockCreationCount(default, null) = 0;
	public var blockDestructionCount(default, null) = 0;

	final context:VkContext;
	final limits:VkPhysicalDeviceLimits;
	final config:VulkanAllocatorConfig;
	final blocks:Array<VulkanMemoryBlock> = [];
	final nextPageSizes:Array<Int64>;
	var nextBlockId = 1;
	var nextAllocationId = 1;
	var disposed = false;

	static final HOST_VISIBLE = 1 << Type.enumIndex(VkMemoryPropertyFlag.HOST_VISIBLE);
	static final HOST_COHERENT = 1 << Type.enumIndex(VkMemoryPropertyFlag.HOST_COHERENT);

	public function new(context:VkContext, limits:VkPhysicalDeviceLimits, ?config:VulkanAllocatorConfig) {
		this.context = context;
		this.limits = limits;
		this.config = config == null ? new VulkanAllocatorConfig() : config;
		if (this.config.deviceBufferPageSize <= 0 || this.config.deviceImagePageSize <= 0 || this.config.uploadPageSize <= 0 || this.config.readbackPageSize <= 0 || this.config.dedicatedThreshold <= 0)
			throw "Vulkan allocator page sizes and dedicated threshold must be positive";
		nextPageSizes = [this.config.deviceBufferPageSize, this.config.deviceImagePageSize, this.config.uploadPageSize, this.config.readbackPageSize];
	}

	public function allocate(requirements:VkMemoryRequirementsInfo, memoryClass:VulkanMemoryClass, requiredProperties:Int, preferredProperties:Int, ?dedicatedBuffer:VkBuffer,
		?dedicatedImage:VkImage, ?debugName:String):VulkanAllocation {
		if (disposed)
			throw "Cannot allocate from a disposed Vulkan memory allocator";
		final size:Int64 = requirements.size;
		final alignment:Int64 = requirements.alignment;
		if (size <= 0 || alignment <= 0)
			throw 'Invalid Vulkan memory requirements: size=$size alignment=$alignment';
		final memoryType = selectMemoryType(requirements.memoryTypeBits, requiredProperties, preferredProperties);
		final pageSize = nextPageSizes[cast memoryClass];
		final requiredDedicated = (cast requirements.requiresDedicatedAllocation : Int) != 0;
		final preferredDedicated = (cast requirements.prefersDedicatedAllocation : Int) != 0;
		final preferredThreshold:Int64 = memoryClass == DeviceBuffer ? 32 << 20 : maxPageSizeFor(memoryClass) / 2;
		final dedicated = requiredDedicated || size >= config.dedicatedThreshold || preferredDedicated && size >= preferredThreshold;
		final name = debugName == null ? 'allocation-${nextAllocationId}' : debugName;
		final block = dedicated
			? createBlock(size, memoryType, memoryClass, dedicatedBuffer, dedicatedImage, true, name)
			: findOrCreateBlock(size, alignment, memoryType, memoryClass, pageSize, name);
		final offset = dedicated ? Int64.ofInt(0) : reserveRange(block, size, alignment);
		final allocation = new VulkanAllocation(this, block, offset, size, nextAllocationId++, name);
		usedBytes += size;
		allocationCount++;
		return allocation;
	}

	function findOrCreateBlock(size:Int64, alignment:Int64, memoryType:Int, memoryClass:VulkanMemoryClass, pageSize:Int64, debugName:String):VulkanMemoryBlock {
		for (block in blocks)
			if (!block.dedicated && block.memoryType == memoryType && block.memoryClass == memoryClass && hasRange(block, size, alignment))
				return block;
		final blockSize = size > pageSize ? alignUp(size, alignment) : pageSize;
		final block = createBlock(blockSize, memoryType, memoryClass, null, null, false, '$debugName-page');
		final maxPageSize = maxPageSizeFor(memoryClass);
		if (pageSize < maxPageSize)
			nextPageSizes[cast memoryClass] = pageSize > maxPageSize / 2 ? maxPageSize : pageSize * 2;
		return block;
	}

	function createBlock(size:Int64, memoryType:Int, memoryClass:VulkanMemoryClass, dedicatedBuffer:VkBuffer, dedicatedImage:VkImage, dedicated:Bool, debugName:String):VulkanMemoryBlock {
		var memory = context.allocateMemory64((size : hl.I64), memoryType, dedicatedBuffer, dedicatedImage);
		if (memory == null && cleanupCallback != null && cleanupCallback())
			memory = context.allocateMemory64((size : hl.I64), memoryType, dedicatedBuffer, dedicatedImage);
		if (memory == null)
			throw Runtime.error('Vulkan allocation failed for $debugName: size=$size, memoryType=$memoryType, class=$memoryClass, dedicated=$dedicated');
		final blockId = nextBlockId++;
		final memoryName = 'allocator-$memoryClass-block-$blockId-$debugName';
		context.setMemoryName(memory, @:privateAccess memoryName.toUtf8());
		final properties = context.getMemoryTypeProperties(memoryType);
		var mapped:hl.Bytes = null;
		if ((properties & HOST_VISIBLE) != 0) {
			mapped = context.mapMemory64(memory, (Int64.ofInt(0) : hl.I64), (size : hl.I64), 0);
			if (mapped == null) {
				context.freeMemory(memory);
				throw Runtime.error('Failed to persistently map Vulkan allocation $debugName: size=$size, memoryType=$memoryType');
			}
		}
		final block = new VulkanMemoryBlock(blockId, memory, size, memoryType, properties, memoryClass, mapped, dedicated);
		blocks.push(block);
		reservedBytes += size;
		blockCreationCount++;
		return block;
	}

	function selectMemoryType(allowed:Int, required:Int, preferred:Int):Int {
		var selected = -1;
		var selectedScore = -1;
		for (index in 0...context.getMemoryTypeCount()) {
			if ((allowed & (1 << index)) == 0)
				continue;
			final properties = context.getMemoryTypeProperties(index);
			if ((properties & required) != required)
				continue;
			final score = bitCount(properties & preferred);
			if (score > selectedScore) {
				selected = index;
				selectedScore = score;
			}
		}
		if (selected < 0)
			throw 'No Vulkan memory type satisfies allowed=0x${StringTools.hex(allowed)}, required=0x${StringTools.hex(required)}, preferred=0x${StringTools.hex(preferred)}';
		return selected;
	}

	static function bitCount(value:Int):Int {
		var bits = value;
		var count = 0;
		while (bits != 0) {
			bits &= bits - 1;
			count++;
		}
		return count;
	}

	static function hasRange(block:VulkanMemoryBlock, size:Int64, alignment:Int64):Bool {
		for (range in block.freeRanges) {
			final alignedOffset = alignUp(range.offset, alignment);
			if (alignedOffset - range.offset + size <= range.size)
				return true;
		}
		return false;
	}

	static function reserveRange(block:VulkanMemoryBlock, size:Int64, alignment:Int64):Int64 {
		for (index in 0...block.freeRanges.length) {
			final range = block.freeRanges[index];
			final alignedOffset = alignUp(range.offset, alignment);
			final prefix = alignedOffset - range.offset;
			if (prefix + size > range.size)
				continue;
			final suffix = range.size - prefix - size;
			block.freeRanges.splice(index, 1);
			if (suffix > 0)
				block.freeRanges.insert(index, new VulkanMemoryRange(alignedOffset + size, suffix));
			if (prefix > 0)
				block.freeRanges.insert(index, new VulkanMemoryRange(range.offset, prefix));
			return alignedOffset;
		}
		throw "Vulkan allocator free-range selection became inconsistent";
	}

	public function free(allocation:VulkanAllocation) {
		if (allocation.released)
			return;
		final block = allocation.getBlock();
		allocation.markReleased();
		usedBytes -= allocation.size;
		allocationCount--;
		if (block.dedicated) {
			destroyBlock(block);
			return;
		}
		block.freeRanges.push(new VulkanMemoryRange(allocation.offset, allocation.size));
		block.freeRanges.sort((left, right) -> Int64.compare(left.offset, right.offset));
		var index = 0;
		while (index + 1 < block.freeRanges.length) {
			final current = block.freeRanges[index];
			final next = block.freeRanges[index + 1];
			if (current.offset + current.size == next.offset) {
				current.size += next.size;
				block.freeRanges.splice(index + 1, 1);
			} else
				index++;
		}
		if (block.liveAllocations == 0)
			for (other in blocks)
				if (other != block && !other.dedicated && other.memoryClass == block.memoryClass && other.memoryType == block.memoryType && other.liveAllocations == 0) {
					destroyBlock(block.size < other.size ? other : block);
					break;
				}
	}

	public function flush(allocation:VulkanAllocation, relativeOffset:Int64, size:Int64) {
		mappedOperation(allocation, relativeOffset, size, false);
	}

	public function invalidate(allocation:VulkanAllocation, relativeOffset:Int64, size:Int64) {
		mappedOperation(allocation, relativeOffset, size, true);
	}

	function mappedOperation(allocation:VulkanAllocation, relativeOffset:Int64, size:Int64, invalidate:Bool) {
		if (allocation.released)
			throw 'Vulkan allocation ${allocation.debugName} has already been released';
		if ((allocation.memoryProperties & HOST_VISIBLE) == 0)
			throw 'Vulkan allocation ${allocation.debugName} is not host visible';
		if ((allocation.memoryProperties & HOST_COHERENT) != 0)
			return;
		if (relativeOffset < 0 || size <= 0 || relativeOffset + size > allocation.size)
			throw 'Mapped range [$relativeOffset, ${relativeOffset + size}) exceeds Vulkan allocation ${allocation.debugName} (${allocation.size} bytes)';
		final block = allocation.getBlock();
		final atomSize:Int64 = limits.nonCoherentAtomSize;
		final start = allocation.offset + relativeOffset;
		final end = start + size;
		final alignedStart = start - start % atomSize;
		var alignedEnd = alignUp(end, atomSize);
		if (alignedEnd > block.size)
			alignedEnd = block.size;
		final result = invalidate
			? context.invalidateMappedMemory(block.memory, (alignedStart : hl.I64), (alignedEnd - alignedStart : hl.I64))
			: context.flushMappedMemory(block.memory, (alignedStart : hl.I64), (alignedEnd - alignedStart : hl.I64));
		if (result != 0)
			throw Runtime.error('${invalidate ? "vkInvalidateMappedMemoryRanges" : "vkFlushMappedMemoryRanges"} failed for ${allocation.debugName}');
	}

	function destroyBlock(block:VulkanMemoryBlock) {
		blocks.remove(block);
		if (block.mapped != null)
			context.unmapMemory(block.memory);
		context.freeMemory(block.memory);
		reservedBytes -= block.size;
		blockDestructionCount++;
		if (!block.dedicated) {
			final maxPageSize = maxPageSizeFor(block.memoryClass);
			var largestPageSize:Int64 = 0;
			for (other in blocks)
				if (!other.dedicated && other.memoryClass == block.memoryClass && other.size > largestPageSize)
					largestPageSize = other.size;
			var nextPageSize = initialPageSizeFor(block.memoryClass);
			if (largestPageSize > 0) {
				final grownPageSize = largestPageSize >= maxPageSize / 2 ? maxPageSize : largestPageSize * 2;
				if (grownPageSize > nextPageSize)
					nextPageSize = grownPageSize;
			}
			nextPageSizes[cast block.memoryClass] = nextPageSize;
		}
	}

	public function dispose() {
		if (disposed)
			return;
		disposed = true;
		for (block in blocks.copy())
			destroyBlock(block);
		usedBytes = 0;
		allocationCount = 0;
	}

	public function getBlockCount(?memoryClass:VulkanMemoryClass):Int {
		var count = 0;
		for (block in blocks)
			if (memoryClass == null || block.memoryClass == memoryClass)
				count++;
		return count;
	}

	public function getReservedBytesForHeap(heapIndex:Int):Int64 {
		var total:Int64 = 0;
		for (block in blocks)
			if (context.getMemoryTypeHeapIndex(block.memoryType) == heapIndex)
				total += block.size;
		return total;
	}

	public function getReservedBytesForClass(memoryClass:VulkanMemoryClass):Int64 {
		var total:Int64 = 0;
		for (block in blocks)
			if (block.memoryClass == memoryClass)
				total += block.size;
		return total;
	}

	inline function initialPageSizeFor(memoryClass:VulkanMemoryClass):Int64 {
		return switch (memoryClass) {
			case DeviceBuffer: config.deviceBufferPageSize;
			case DeviceImage: config.deviceImagePageSize;
			case Upload: config.uploadPageSize;
			case Readback: config.readbackPageSize;
		}
	}

	static inline function maxPageSizeFor(memoryClass:VulkanMemoryClass):Int64 {
		return switch (memoryClass) {
			case DeviceBuffer: 32 << 20;
			case DeviceImage: 64 << 20;
			case Upload: 16 << 20;
			case Readback: 8 << 20;
		}
	}

	static inline function alignUp(value:Int64, alignment:Int64):Int64 {
		final remainder = value % alignment;
		return remainder == 0 ? value : value + alignment - remainder;
	}
}
#end
