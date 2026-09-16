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
import limen.graphics.vulkan.Runtime;
import limen.graphics.vulkan.command.Commands.VkCommandBuffer;
import limen.graphics.vulkan.command.Commands.VkPipelineStage2;
import limen.graphics.vulkan.internal.VulkanBindings;
import limen.graphics.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.vulkan.memory.Memory.VkAccess2;
import limen.graphics.vulkan.memory.Memory.VkBufferImageCopy;
import limen.graphics.vulkan.memory.Memory.VkBufferUsageFlag;
import limen.graphics.vulkan.memory.Memory.VkMemoryPropertyFlag;
import limen.graphics.vulkan.memory.Memory.VkMemoryRequirementsInfo;

private class VulkanUploadPage {
	public var buffer:VulkanUploadBuffer;
	public var capacity:Int;
	public var offset = 0;

	public function new(buffer:VulkanUploadBuffer, capacity:Int) {
		this.buffer = buffer;
		this.capacity = capacity;
	}
}

class VulkanConstantUpload {
	public var buffer:VulkanUploadBuffer;
	public var offset:Int;
	public var size:Int;

	public function new() {
	}
}

class VulkanUploadManager {
	final context:VkContext;
	final allocator:VulkanMemoryAllocator;
	final pageSize:Int;
	final frames:Array<Array<VulkanUploadPage>>;
	var currentFrame = -1;
	var nextPageId = 1;
	var allocatedPage:VulkanUploadPage;
	var allocatedOffset:Int;
	public var pageCreationCount(default, null) = 0;
	public var uploadedBytes(default, null):Int64 = 0;

	static final HOST_VISIBLE = 1 << Type.enumIndex(VkMemoryPropertyFlag.HOST_VISIBLE);
	static final HOST_COHERENT = 1 << Type.enumIndex(VkMemoryPropertyFlag.HOST_COHERENT);

	public function new(context:VkContext, allocator:VulkanMemoryAllocator, frameCount:Int, pageSize = 8 << 20) {
		this.context = context;
		this.allocator = allocator;
		this.pageSize = pageSize;
		frames = [for (_ in 0...frameCount) []];
	}

	public function beginFrame(frameIndex:Int) {
		currentFrame = frameIndex;
		for (page in frames[frameIndex])
			page.offset = 0;
	}

	public function uploadBuffer(command:VkCommandBuffer, destination:VulkanBuffer, destinationOffset:Int, source:hl.Bytes, sourceOffset:Int, size:Int) {
		if (destinationOffset < 0 || size <= 0 || Int64.ofInt(destinationOffset) + size > destination.size)
			throw 'Upload range [$destinationOffset, ${destinationOffset + size}) exceeds ${destination.debugName} (${destination.size} bytes)';
		allocate(size, 16);
		final page = allocatedPage;
		final offset = allocatedOffset;
		page.buffer.allocation.mappedBytes(offset, size).blit(0, source, sourceOffset, size);
		page.buffer.allocation.flush(offset, size);
		uploadedBytes += size;
		VulkanResourceState.recordBarrier();
		command.bufferBarrier2(page.buffer.buffer, (Int64.ofInt(offset) : hl.I64), (Int64.ofInt(size) : hl.I64), VkPipelineStage2.HOST, VkAccess2.HOST_WRITE, VkPipelineStage2.COPY, VkAccess2.TRANSFER_READ);
		VulkanResourceState.transitionBuffer(command, destination, TransferDestination, Int64.ofInt(destinationOffset), Int64.ofInt(size));
		command.copyBuffer2(page.buffer.buffer, destination.buffer, (Int64.ofInt(offset) : hl.I64), (Int64.ofInt(destinationOffset) : hl.I64), (Int64.ofInt(size) : hl.I64));
	}

	public function uploadConstants(command:VkCommandBuffer, source:hl.Bytes, sourceOffset:Int, size:Int, alignment:Int, upload:VulkanConstantUpload, recordBarrier = true) {
		if (size <= 0)
			throw "Vulkan constant upload size must be positive";
		allocate(size, alignment);
		final page = allocatedPage;
		final offset = allocatedOffset;
		page.buffer.allocation.mappedBytes(offset, size).blit(0, source, sourceOffset, size);
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
		page.buffer.allocation.mappedBytes(offset, size).blit(0, source, sourceOffset, size);
		page.buffer.allocation.flush(offset, size);
		uploadedBytes += size;
		VulkanResourceState.recordBarrier();
		command.bufferBarrier2(page.buffer.buffer, (Int64.ofInt(offset) : hl.I64), (Int64.ofInt(size) : hl.I64), VkPipelineStage2.HOST, VkAccess2.HOST_WRITE, VkPipelineStage2.COPY, VkAccess2.TRANSFER_READ);
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
		for (page in frames[currentFrame]) {
			final offset = alignUp(page.offset, alignment);
			if (offset + size <= page.capacity)
				return reserve(page, offset, size);
		}
		final capacity = size > pageSize ? alignUp(size, alignment) : pageSize;
		final page = createPage(capacity);
		frames[currentFrame].push(page);
		reserve(page, 0, size);
	}

	function reserve(page:VulkanUploadPage, offset:Int, size:Int) {
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
			throw Runtime.error('Failed to create Vulkan upload page $nextPageId ($capacity bytes)');
		final requirements = new VkMemoryRequirementsInfo();
		context.getBufferMemoryRequirements2(handle, requirements);
		final name = 'frame-upload-page-${nextPageId++}';
		context.setBufferName(handle, @:privateAccess name.toUtf8());
		final allocation = try allocator.allocate(requirements, Upload, HOST_VISIBLE, HOST_COHERENT, handle, null, name) catch (error:Dynamic) {
			context.destroyBuffer(handle);
			throw error;
		};
		if (!context.bindBufferMemory64(handle, allocation.memory, (allocation.offset : hl.I64))) {
			allocation.dispose();
			context.destroyBuffer(handle);
			throw Runtime.error('Failed to bind Vulkan upload page $name');
		}
		final buffer = new VulkanUploadBuffer(handle, allocation, Int64.ofInt(capacity), usage, 1, HostWrite, -1, name);
		pageCreationCount++;
		return new VulkanUploadPage(buffer, capacity);
	}

	public function dispose() {
		for (frame in frames)
			for (page in frame) {
				context.destroyBuffer(page.buffer.buffer);
				page.buffer.allocation.dispose();
			}
	}

	static inline function alignUp(value:Int, alignment:Int):Int {
		return Std.int((value + alignment - 1) / alignment) * alignment;
	}
}
#end
