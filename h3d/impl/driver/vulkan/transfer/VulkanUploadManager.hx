package h3d.impl.driver.vulkan.transfer;

#if (limen && gfx_vulkan)
import haxe.Int64;
import h3d.impl.driver.vulkan.memory.VulkanMemoryAllocator;
import h3d.impl.driver.vulkan.resource.VulkanAllocation.VulkanMemoryClass;
import h3d.impl.driver.vulkan.resource.VulkanBuffer;
import h3d.impl.driver.vulkan.resource.VulkanBuffer.VulkanBufferState;
import h3d.impl.driver.vulkan.resource.VulkanBuffer.VulkanUploadBuffer;
import h3d.impl.driver.vulkan.resource.VulkanImage;
import h3d.impl.driver.vulkan.resource.VulkanImage.VulkanImageState;
import h3d.impl.driver.vulkan.resource.VulkanResourceState;
import limen.graphics.renderer.vulkan.Vulkan as VulkanRuntime;
import limen.graphics.renderer.vulkan.command.Commands.VkCommandBuffer;
import limen.graphics.renderer.vulkan.command.Commands.VkPipelineStage2;
import limen.graphics.renderer.vulkan.internal.VulkanBindings;
import limen.graphics.renderer.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.renderer.vulkan.memory.Memory.VkAccess2;
import limen.graphics.renderer.vulkan.memory.Memory.VkBufferImageCopy;
import limen.graphics.renderer.vulkan.memory.Memory.VkBufferUsageFlag;
import limen.graphics.renderer.vulkan.memory.Memory.VkMemoryPropertyFlag;

private class VulkanUploadPage {
	public var buffer:VulkanUploadBuffer;
	public var capacity:Int;
	public var offset = 0;
	public var idleFrames = 0;
	public var underusedFrames = 0;

	public function new(buffer:VulkanUploadBuffer, capacity:Int) {
		this.buffer = buffer;
		this.capacity = capacity;
	}
}

class VulkanConstantUpload {
	public var buffer:VulkanUploadBuffer;
	public var offset:Int;
	public var size:Int;
	public var paramsCache = new h3d.impl.driver.ShaderParamCache();

	public function new() {
	}
}

class VulkanUploadManager {
	final context:VkContext;
	final allocator:VulkanMemoryAllocator;
	final pageSize:Int;
	final frames:Array<Array<VulkanUploadPage>>;
	final frameDemand:Array<Int>;
	var currentDemand = 0;
	var targetPageSize:Int;
	var currentFrame = -1;
	var nextPageId = 1;
	var allocatedPage:VulkanUploadPage;
	var allocatedOffset:Int;
	static inline final IDLE_FRAME_LIMIT = 8;
	static inline final LARGE_IDLE_FRAME_LIMIT = 2;
	public var retainedBytes(default, null):Int64 = 0;
	public var pageDestructionCount(default, null) = 0;
	public var pageCreationCount(default, null) = 0;
	public var uploadedBytes(default, null):Int64 = 0;

	static final HOST_VISIBLE = 1 << Type.enumIndex(VkMemoryPropertyFlag.HOST_VISIBLE);
	static final HOST_COHERENT = 1 << Type.enumIndex(VkMemoryPropertyFlag.HOST_COHERENT);

	public function new(context:VkContext, allocator:VulkanMemoryAllocator, frameCount:Int, pageSize = 8 << 20) {
		this.context = context;
		this.allocator = allocator;
		this.pageSize = pageSize;
		frames = [for (_ in 0...frameCount) []];
		frameDemand = [for (_ in 0...frameCount) 0];
	}

	public function beginFrame(frameIndex:Int) {
		currentFrame = frameIndex;
		allocatedPage = null;
		final pages = frames[frameIndex];
		var demand = 0;
		for (page in pages)
			demand += Std.int(Math.min(page.offset, pageSize - demand));
		final minimum = Std.int(Math.min(64 << 10, pageSize));
		final previous = frameDemand[frameIndex];
		final desired = Std.int(Math.max(demand, previous - (previous >> 2)));
		targetPageSize = minimum;
		while (targetPageSize < desired)
			targetPageSize = targetPageSize > (pageSize >> 1) ? pageSize : targetPageSize * 2;
		frameDemand[frameIndex] = desired;
		currentDemand = 0;

		var index = 0;
		while (index < pages.length) {
			final page = pages[index];
			page.idleFrames = page.offset == 0 ? page.idleFrames + 1 : 0;
			final oversized = page.capacity / 4 >= targetPageSize;
			page.underusedFrames = oversized && page.offset <= targetPageSize ? page.underusedFrames + 1 : 0;
			final idleLimit = oversized ? LARGE_IDLE_FRAME_LIMIT : IDLE_FRAME_LIMIT;
			if (page.idleFrames >= idleLimit || page.underusedFrames >= LARGE_IDLE_FRAME_LIMIT) {
				pages.splice(index, 1);
				destroyPage(page);
			} else {
				page.offset = 0;
				index++;
			}
		}
	}

	public function uploadBuffer(command:VkCommandBuffer, destination:VulkanBuffer, destinationOffset:Int, source:hl.Bytes, sourceOffset:Int, size:Int) {
		if (destinationOffset < 0 || size <= 0 || Int64.ofInt(destinationOffset) + size > destination.size)
			throw 'Upload range [$destinationOffset, ${destinationOffset + size}) exceeds ${destination.debugName} (${destination.size} bytes)';
		allocate(size, 16);
		final page = allocatedPage;
		final offset = allocatedOffset;
		page.buffer.allocation.writeMapped(offset, source, sourceOffset, size);
		page.buffer.allocation.flush(offset, size);
		uploadedBytes += size;
		VulkanResourceState.transitionBuffer(command, destination, TransferDestination, Int64.ofInt(destinationOffset), Int64.ofInt(size));
		command.copyBuffer2(page.buffer.buffer, destination.buffer, (Int64.ofInt(offset) : hl.I64), (Int64.ofInt(destinationOffset) : hl.I64), (Int64.ofInt(size) : hl.I64));
	}

	public function uploadConstants(command:VkCommandBuffer, source:hl.Bytes, sourceOffset:Int, size:Int, alignment:Int, upload:VulkanConstantUpload, recordBarrier = true) {
		if (size <= 0)
			throw "Vulkan constant upload size must be positive";
		allocate(size, alignment);
		final page = allocatedPage;
		final offset = allocatedOffset;
		page.buffer.allocation.writeMapped(offset, source, sourceOffset, size);
		page.buffer.allocation.flush(offset, size);
		uploadedBytes += size;
		if (recordBarrier) {
			VulkanResourceState.recordBarrier();
			final shaderStages:hl.I64 = cast ((VkPipelineStage2.VERTEX_SHADER : haxe.Int64)
				| (VkPipelineStage2.FRAGMENT_SHADER : haxe.Int64) | (VkPipelineStage2.COMPUTE_SHADER : haxe.Int64));
			command.bufferBarrier2(page.buffer.buffer, (Int64.ofInt(offset) : hl.I64), (Int64.ofInt(size) : hl.I64),
				VkPipelineStage2.HOST, VkAccess2.HOST_WRITE, shaderStages, VkAccess2.UNIFORM_READ);
		}
		upload.buffer = page.buffer;
		upload.offset = offset;
		upload.size = size;
	}

	public function uploadImage(command:VkCommandBuffer, destination:VulkanImage, mipLevel:Int, layer:Int, source:hl.Bytes, sourceOffset:Int, size:Int, width:Int, height:Int, depth:Int,
		x = 0, y = 0, z = 0) {
		allocate(size, 16);
		final page = allocatedPage;
		final offset = allocatedOffset;
		page.buffer.allocation.writeMapped(offset, source, sourceOffset, size);
		page.buffer.allocation.flush(offset, size);
		uploadedBytes += size;
		VulkanResourceState.transitionImage(command, destination, mipLevel, layer, TransferDestination);
		final region = new VkBufferImageCopy();
		region.bufferOffset = (Int64.ofInt(offset) : hl.I64);
		region.aspectMask = destination.aspect;
		region.mipLevel = mipLevel;
		region.baseArrayLayer = layer;
		region.layerCount = 1;
		region.imageOffsetX = x;
		region.imageOffsetY = y;
		region.imageOffsetZ = z;
		region.imageWidth = width;
		region.imageHeight = height;
		region.imageDepth = depth;
		command.copyBufferToImage2(page.buffer.buffer, destination.image, TRANSFER_DST_OPTIMAL, 1, VulkanBindings.makeRef(region));
		VulkanResourceState.transitionImage(command, destination, mipLevel, layer, ShaderRead);
	}

	function allocate(size:Int, alignment:Int) {
		if (currentFrame < 0)
			throw "Vulkan uploads require an active frame";
		if (allocatedPage != null) {
			final offset = alignUp(allocatedPage.offset, alignment);
			if (size <= allocatedPage.capacity - offset)
				return reserve(allocatedPage, offset, size);
		}
		var best:VulkanUploadPage = null;
		var bestOffset = 0;
		var bestRemaining = 0x7FFFFFFF;
		for (page in frames[currentFrame]) {
			final offset = alignUp(page.offset, alignment);
			final remaining = page.capacity - offset;
			if (size <= remaining && remaining < bestRemaining) {
				best = page;
				bestOffset = offset;
				bestRemaining = remaining;
			}
		}
		if (best != null)
			return reserve(best, bestOffset, size);

		var capacity = targetPageSize;
		final demand = Std.int(Math.max(size, currentDemand));
		while (capacity < demand && capacity < pageSize)
			capacity = capacity > (pageSize >> 1) ? pageSize : capacity * 2;
		if (size > capacity)
			capacity = alignUp(size, alignment);
		final page = createPage(capacity);
		frames[currentFrame].push(page);
		reserve(page, 0, size);
	}

	function reserve(page:VulkanUploadPage, offset:Int, size:Int) {
		if (currentDemand < pageSize) {
			final consumed = offset + size - page.offset;
			currentDemand = consumed >= pageSize - currentDemand ? pageSize : currentDemand + consumed;
		}
		page.offset = offset + size;
		allocatedPage = page;
		allocatedOffset = offset;
	}

	function createPage(capacity:Int):VulkanUploadPage {
		var usage = new haxe.EnumFlags<VkBufferUsageFlag>();
		usage.set(TRANSFER_SRC);
		usage.set(UNIFORM_BUFFER);
		final handle = context.createBuffer64((Int64.ofInt(capacity) : hl.I64), usage);
		if (handle == null)
			throw VulkanRuntime.error('Failed to create Vulkan upload page $nextPageId ($capacity bytes)');
		final name = 'frame-upload-page-${nextPageId++}';
		context.setBufferName(handle, @:privateAccess name.toUtf8());
		final allocation = try allocator.allocate(Upload, HOST_VISIBLE, HOST_COHERENT, handle, null, name) catch (error:Dynamic) {
			context.destroyBuffer(handle);
			throw error;
		};
		if (!context.bindBufferMemory64(handle, allocation.memory, (allocation.offset : hl.I64))) {
			allocation.dispose();
			context.destroyBuffer(handle);
			throw VulkanRuntime.error('Failed to bind Vulkan upload page $name');
		}
		final buffer = new VulkanUploadBuffer(handle, allocation, Int64.ofInt(capacity), usage, 1, HostWrite, -1, name);
		pageCreationCount++;
		retainedBytes += capacity;
		return new VulkanUploadPage(buffer, capacity);
	}

	function destroyPage(page:VulkanUploadPage) {
		context.destroyBuffer(page.buffer.buffer);
		page.buffer.allocation.dispose();
		retainedBytes -= page.capacity;
		pageDestructionCount++;
	}

	public function reclaimUnused(frameIndex:Int, completed:Bool) {
		final pages = frames[frameIndex];
		var index = 0;
		while (index < pages.length) {
			final page = pages[index];
			if (page.offset == 0 || completed) {
				if (allocatedPage == page)
					allocatedPage = null;
				pages.splice(index, 1);
				destroyPage(page);
			} else
				index++;
		}
	}

	public function dispose() {
		allocatedPage = null;
		for (frame in frames) {
			for (page in frame)
				destroyPage(page);
			frame.resize(0);
		}
	}

	static inline function alignUp(value:Int, alignment:Int):Int {
		return Std.int((value + alignment - 1) / alignment) * alignment;
	}
}
#end
