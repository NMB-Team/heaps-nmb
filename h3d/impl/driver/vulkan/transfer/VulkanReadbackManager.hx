package h3d.impl.driver.vulkan.transfer;

#if (limen && gfx_vulkan)
import haxe.Int64;
import h3d.impl.driver.vulkan.memory.VulkanMemoryAllocator;
import h3d.impl.driver.vulkan.resource.VulkanAllocation.VulkanMemoryClass;
import h3d.impl.driver.vulkan.resource.VulkanBuffer;
import h3d.impl.driver.vulkan.resource.VulkanBuffer.VulkanReadbackBuffer;
import h3d.impl.driver.vulkan.resource.VulkanImage.VulkanImage;
import h3d.impl.driver.vulkan.resource.VulkanResourceState;
import hxd.PixelFormat;
import limen.graphics.vulkan.Runtime;
import limen.graphics.vulkan.command.Commands.VkCommandBuffer;
import limen.graphics.vulkan.format.Formats.VkFormat;
import limen.graphics.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.vulkan.memory.Memory.VkBufferImageCopy;
import limen.graphics.vulkan.memory.Memory.VkImage;
import limen.graphics.vulkan.memory.Memory.VkImageAspectFlag;
import limen.graphics.vulkan.memory.Memory.VkMemoryPropertyFlag;
import limen.graphics.vulkan.memory.Memory.VkMemoryRequirementsInfo;

class VulkanImageReadbackRequest {
	public final source:VkImage;
	public final resource:VulkanImage;
	public final aspect:haxe.EnumFlags<VkImageAspectFlag>;
	public final mipLevel:Int;
	public final layer:Int;
	public final sourceX:Int;
	public final sourceY:Int;
	public final width:Int;
	public final height:Int;
	public final vulkanFormat:VkFormat;
	public final heapsFormat:PixelFormat;
	public final blockWidth:Int;
	public final blockHeight:Int;
	public final bytesPerBlock:Int;
	public final sourceRowStride:Int;
	public final destinationRowStride:Int;
	public final destination:hl.Bytes;
	public final destinationOffset:Int;
	public final completionSerial:Int;
	public final callback:Void->Void;
	public var readback(default, null):VulkanReadbackBuffer;

	public function new(source:VkImage, resource:VulkanImage, aspect:haxe.EnumFlags<VkImageAspectFlag>, mipLevel:Int, layer:Int,
		sourceX:Int, sourceY:Int, width:Int, height:Int, vulkanFormat:VkFormat, heapsFormat:PixelFormat,
		blockWidth:Int, blockHeight:Int, bytesPerBlock:Int, destination:hl.Bytes, destinationOffset:Int,
		destinationRowStride:Int, completionSerial:Int, callback:Void->Void) {
		this.source = source;
		this.resource = resource;
		this.aspect = aspect;
		this.mipLevel = mipLevel;
		this.layer = layer;
		this.sourceX = sourceX;
		this.sourceY = sourceY;
		this.width = width;
		this.height = height;
		this.vulkanFormat = vulkanFormat;
		this.heapsFormat = heapsFormat;
		this.blockWidth = blockWidth;
		this.blockHeight = blockHeight;
		this.bytesPerBlock = bytesPerBlock;
		sourceRowStride = Std.int((width + blockWidth - 1) / blockWidth) * bytesPerBlock;
		this.destinationRowStride = destinationRowStride;
		this.destination = destination;
		this.destinationOffset = destinationOffset;
		this.completionSerial = completionSerial;
		this.callback = callback;
	}

	public inline function rowCount():Int {
		return Std.int((height + blockHeight - 1) / blockHeight);
	}

	public inline function byteSize():Int {
		return sourceRowStride * rowCount();
	}

	@:allow(h3d.impl.driver.vulkan.transfer.VulkanReadbackManager)
	function setReadback(readback:VulkanReadbackBuffer) {
		this.readback = readback;
	}
}

private class VulkanPendingReadback {
	public final buffer:VulkanReadbackBuffer;
	public final target:hl.Bytes;
	public final targetOffset:Int;
	public final size:Int;
	public final sourceRowStride:Int;
	public final destinationRowStride:Int;
	public final rowCount:Int;
	public final callback:Void->Void;

	public function new(buffer:VulkanReadbackBuffer, target:hl.Bytes, targetOffset:Int, size:Int,
		sourceRowStride:Int, destinationRowStride:Int, rowCount:Int, callback:Void->Void) {
		this.buffer = buffer;
		this.target = target;
		this.targetOffset = targetOffset;
		this.size = size;
		this.sourceRowStride = sourceRowStride;
		this.destinationRowStride = destinationRowStride;
		this.rowCount = rowCount;
		this.callback = callback;
	}
}

class VulkanReadbackManager {
	final context:VkContext;
	final allocator:VulkanMemoryAllocator;
	final pending:Array<Array<VulkanPendingReadback>>;
	final available:Array<VulkanReadbackBuffer> = [];
	var nextId = 1;
	public var bufferCreationCount(default, null) = 0;
	public var readbackBytes(default, null):Int64 = 0;

	static final HOST_VISIBLE = 1 << Type.enumIndex(VkMemoryPropertyFlag.HOST_VISIBLE);
	static final HOST_CACHED = 1 << Type.enumIndex(VkMemoryPropertyFlag.HOST_CACHED);

	public function new(context:VkContext, allocator:VulkanMemoryAllocator, frameCount:Int) {
		this.context = context;
		this.allocator = allocator;
		pending = [for (_ in 0...frameCount) []];
	}

	public function requestBuffer(command:VkCommandBuffer, frameIndex:Int, source:VulkanBuffer, sourceOffset:Int, size:Int, target:hl.Bytes, targetOffset:Int, callback:Void->Void) {
		if (sourceOffset < 0 || size <= 0 || Int64.ofInt(sourceOffset) + size > source.size)
			throw 'Readback range [$sourceOffset, ${sourceOffset + size}) exceeds ${source.debugName} (${source.size} bytes)';
		readbackBytes += size;
		final readback = acquireBuffer(size);
		VulkanResourceState.transitionBuffer(command, source, TransferSource, Int64.ofInt(sourceOffset), Int64.ofInt(size));
		VulkanResourceState.transitionBuffer(command, readback, TransferDestination, Int64.ofInt(0), Int64.ofInt(size));
		command.copyBuffer2(source.buffer, readback.buffer, (Int64.ofInt(sourceOffset) : hl.I64), (Int64.ofInt(0) : hl.I64), (Int64.ofInt(size) : hl.I64));
		VulkanResourceState.transitionBuffer(command, readback, HostRead, Int64.ofInt(0), Int64.ofInt(size));
		pending[frameIndex].push(new VulkanPendingReadback(readback, target, targetOffset, size, size, size, 1, callback));
	}

	public function requestImage(command:VkCommandBuffer, frameIndex:Int, request:VulkanImageReadbackRequest) {
		final size = request.byteSize();
		if (size <= 0 || request.destinationOffset < 0)
			throw "Vulkan image readback destination range is invalid";
		readbackBytes += size;
		final readback = acquireBuffer(size);
		request.setReadback(readback);
		VulkanResourceState.transitionBuffer(command, readback, TransferDestination, Int64.ofInt(0), Int64.ofInt(size));
		final region = new VkBufferImageCopy();
		region.bufferOffset = (Int64.ofInt(0) : hl.I64);
		region.aspectMask = request.aspect;
		region.mipLevel = request.mipLevel;
		region.baseArrayLayer = request.layer;
		region.layerCount = 1;
		region.imageOffsetX = request.sourceX;
		region.imageOffsetY = request.sourceY;
		region.imageWidth = request.width;
		region.imageHeight = request.height;
		region.imageDepth = 1;
		command.copyImageToBuffer2(request.source, TRANSFER_SRC_OPTIMAL, readback.buffer, 1,
			limen.graphics.vulkan.internal.VulkanBindings.makeRef(region));
		VulkanResourceState.transitionBuffer(command, readback, HostRead, Int64.ofInt(0), Int64.ofInt(size));
		pending[frameIndex].push(new VulkanPendingReadback(readback, request.destination, request.destinationOffset, size,
			request.sourceRowStride, request.destinationRowStride, request.rowCount(), request.callback));
	}

	public function completeFrame(frameIndex:Int) {
		final requests = pending[frameIndex];
		pending[frameIndex] = [];
		for (request in requests) {
			request.buffer.allocation.invalidate(0, request.size);
			final mapped = request.buffer.allocation.mappedBytes(0, request.size);
			if (request.sourceRowStride == request.destinationRowStride)
				request.target.blit(request.targetOffset, mapped, 0, request.size);
			else
				for (row in 0...request.rowCount)
					request.target.blit(request.targetOffset + row * request.destinationRowStride, mapped, row * request.sourceRowStride, request.sourceRowStride);
			available.push(request.buffer);
			if (request.callback != null)
				request.callback();
		}
	}

	function acquireBuffer(size:Int):VulkanReadbackBuffer {
		var bestIndex = -1;
		for (index => buffer in available)
			if (buffer.size >= Int64.ofInt(size) && (bestIndex < 0 || buffer.size < available[bestIndex].size))
				bestIndex = index;
		if (bestIndex >= 0)
			return available.splice(bestIndex, 1)[0];
		return createBuffer(size);
	}

	function createBuffer(size:Int):VulkanReadbackBuffer {
		var usage = new haxe.EnumFlags<limen.graphics.vulkan.memory.Memory.VkBufferUsageFlag>();
		usage.set(TRANSFER_DST);
		final handle = context.createBuffer64((Int64.ofInt(size) : hl.I64), usage);
		if (handle == null)
			throw Runtime.error('Failed to create Vulkan readback buffer ($size bytes)');
		final requirements = new VkMemoryRequirementsInfo();
		context.getBufferMemoryRequirements2(handle, requirements);
		final name = 'readback-${nextId++}';
		context.setBufferName(handle, @:privateAccess name.toUtf8());
		final allocation = try allocator.allocate(requirements, Readback, HOST_VISIBLE, HOST_CACHED, handle, null, name) catch (error:Dynamic) {
			context.destroyBuffer(handle);
			throw error;
		};
		if (!context.bindBufferMemory64(handle, allocation.memory, (allocation.offset : hl.I64))) {
			allocation.dispose();
			context.destroyBuffer(handle);
			throw Runtime.error('Failed to bind Vulkan readback buffer $name');
		}
		bufferCreationCount++;
		return new VulkanReadbackBuffer(handle, allocation, Int64.ofInt(size), usage, 1, Undefined, -1, name);
	}

	function destroyBuffer(buffer:VulkanReadbackBuffer) {
		context.destroyBuffer(buffer.buffer);
		buffer.allocation.dispose();
	}

	public function dispose() {
		for (frameIndex in 0...pending.length)
			completeFrame(frameIndex);
		for (buffer in available)
			destroyBuffer(buffer);
		available.resize(0);
	}
}
#end
