package h3d.impl.driver.vulkan.memory;

#if (limen && gfx_vulkan)
import haxe.Int64;
import h3d.impl.driver.vulkan.resource.VulkanAllocation;
import h3d.impl.driver.vulkan.resource.VulkanAllocation.VulkanMemoryClass;
import limen.graphics.renderer.vulkan.memory.VmaMemoryAllocator as Vma;
import limen.graphics.renderer.vulkan.memory.VmaMemoryAllocator.AllocatorHandle;
import limen.graphics.renderer.vulkan.Vulkan as VulkanRuntime;
import limen.graphics.renderer.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.renderer.vulkan.memory.Memory.VkBuffer;
import limen.graphics.renderer.vulkan.memory.Memory.VkImage;
import limen.graphics.renderer.vulkan.memory.Memory.VkMemoryPropertyFlag;

class VulkanMemoryAllocator {
	public var cleanupCallback:Void->Bool;
	public var reservedBytes(get, never):Int64;
	public var usedBytes(get, never):Int64;
	public var allocationCount(get, never):Int;

	final context:VkContext;
	final handles:Array<AllocatorHandle> = [];
	final allocations:Array<VulkanAllocation> = [];
	var nextAllocationId = 1;
	var disposed = false;

	public function new(context:VkContext) {
		this.context = context;
		try {
			for (_ in 0...4) {
				var result = 0;
				final handle = Vma.create(context, result);
				if (handle == null)
					throw VulkanRuntime.error('VMA creation failed: $result');
				handles.push(handle);
			}
		} catch (error:Dynamic) {
			for (handle in handles)
				Vma.destroy(handle);
			throw error;
		}
	}

	public function allocate(memoryClass:VulkanMemoryClass, requiredProperties:Int, preferredProperties:Int,
		?dedicatedBuffer:VkBuffer, ?dedicatedImage:VkImage, ?debugName:String):VulkanAllocation {
		if (disposed)
			throw "Cannot allocate from a disposed Vulkan memory allocator";
		if ((dedicatedBuffer == null) == (dedicatedImage == null))
			throw "VMA requires exactly one buffer or image";
		var result = 0;
		final handle = handles[cast memoryClass];
		var native = dedicatedBuffer != null
			? Vma.allocate_buffer(handle, dedicatedBuffer, requiredProperties, preferredProperties, false, result)
			: Vma.allocate_image(handle, dedicatedImage, requiredProperties, preferredProperties, false, result);
		if (native == null && cleanupCallback != null && cleanupCallback())
			native = dedicatedBuffer != null
				? Vma.allocate_buffer(handle, dedicatedBuffer, requiredProperties, preferredProperties, false, result)
				: Vma.allocate_image(handle, dedicatedImage, requiredProperties, preferredProperties, false, result);
		if (native == null)
			throw VulkanRuntime.error('VMA allocation failed for $debugName: $result');
		final name = debugName == null ? 'allocation-$nextAllocationId' : debugName;
		var allocation:VulkanAllocation;
		try {
			allocation = new VulkanAllocation(this, native, context, nextAllocationId++, name);
		} catch (error:Dynamic) {
			Vma.release(native);
			throw error;
		}
		allocations.push(allocation);
		return allocation;
	}

	@:allow(h3d.impl.driver.vulkan.VulkanDriver)
	function allocateTransientImage(image:VkImage, properties:Int, name:String):VulkanAllocation {
		if (disposed) throw "Cannot allocate from a disposed Vulkan memory allocator";
		var result = 0;
		final native = Vma.allocate_transient_image(handles[cast DeviceImage], image, properties, properties, result);
		if (native == null) throw VulkanRuntime.error('Transient VMA allocation failed: $result');
		var allocation:VulkanAllocation;
		try {
			allocation = new VulkanAllocation(this, native, context, nextAllocationId++, name);
		} catch (error:Dynamic) {
			Vma.release(native);
			throw error;
		}
		allocations.push(allocation);
		return allocation;
	}

	public function free(allocation:VulkanAllocation) {
		if (allocation.released)
			return;
		allocation.markReleased();
		allocations.remove(allocation);
	}

	public function flush(allocation:VulkanAllocation, relativeOffset:Int64, size:Int64) {
		mappedOperation(allocation, relativeOffset, size, false);
	}

	public function invalidate(allocation:VulkanAllocation, relativeOffset:Int64, size:Int64) {
		mappedOperation(allocation, relativeOffset, size, true);
	}

	function mappedOperation(allocation:VulkanAllocation, offset:Int64, size:Int64, invalidate:Bool) {
		if (allocation.released || (allocation.memoryProperties & (1 << Type.enumIndex(VkMemoryPropertyFlag.HOST_VISIBLE))) == 0 || offset < 0 || size <= 0 || offset > allocation.size || size > allocation.size - offset)
			throw 'Invalid mapped range for Vulkan allocation ${allocation.debugName}';
		if ((allocation.memoryProperties & (1 << Type.enumIndex(VkMemoryPropertyFlag.HOST_COHERENT))) != 0)
			return;
		final result = invalidate ? Vma.invalidate(allocation.handle, offset, size) : Vma.flush(allocation.handle, offset, size);
		if (result != 0)
			throw VulkanRuntime.error('VMA cache operation failed for ${allocation.debugName}: $result');
	}

	function statistics(?memoryClass:VulkanMemoryClass, heap:Int = -1) {
		var blocks = 0, count = 0;
		var reserved:Int64 = 0, used:Int64 = 0;
		if (!disposed)
			for (index in 0...handles.length) {
				if (memoryClass != null && index != (cast memoryClass : Int))
					continue;
				var b = 0, c = 0;
				var r:Int64 = 0, u:Int64 = 0;
				if (heap < 0)
					Vma.statistics(handles[index], b, c, r, u);
				else
					Vma.heapStatistics(handles[index], heap, b, c, r, u);
				blocks += b;
				count += c;
				reserved += r;
				used += u;
			}
		return {blocks: blocks, count: count, reserved: reserved, used: used};
	}

	function get_reservedBytes():Int64 { return statistics().reserved; }
	function get_usedBytes():Int64 { return statistics().used; }
	function get_allocationCount():Int { return statistics().count; }
	public function getBlockCount(?memoryClass:VulkanMemoryClass):Int { return statistics(memoryClass).blocks; }
	public function getReservedBytesForHeap(heapIndex:Int):Int64 { return statistics(null, heapIndex).reserved; }
	public function getReservedBytesForClass(memoryClass:VulkanMemoryClass):Int64 { return statistics(memoryClass).reserved; }

	public function dispose() {
		if (disposed)
			return;
		if (allocations.length != 0)
			throw "Release Vulkan resources before disposing the VMA allocator";
		for (handle in handles)
			Vma.destroy(handle);
		disposed = true;
	}
}
#end
