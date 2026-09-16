package h3d.impl.driver.vulkan.frame;

#if (limen && gfx_vulkan)
import h3d.impl.driver.vulkan.transfer.VulkanUploadManager.VulkanConstantUpload;
import h3d.impl.driver.vulkan.descriptor.VulkanDescriptorArena;
import h3d.impl.driver.vulkan.descriptor.VulkanBindlessDescriptors.VulkanBindlessGeneration;
import h3d.impl.driver.vulkan.resource.VulkanBuffer;
import h3d.impl.driver.vulkan.resource.VulkanImage.VulkanTexture;
import h3d.impl.driver.vulkan.shader.VulkanCompiledShader.VulkanDescriptorSetMetadata;
import limen.graphics.vulkan.command.Commands.VkCommandBuffer;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSet;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSetLayout;
import limen.graphics.vulkan.memory.Memory.VkBuffer;
import limen.graphics.vulkan.memory.Memory.VkImageView;
import limen.graphics.vulkan.sampler.Samplers.VkSampler;
import limen.graphics.vulkan.command.Commands.VkFence;
import limen.graphics.vulkan.command.Commands.VkSemaphore;

class VulkanDescriptorCacheEntry {
	public final metadata:VulkanDescriptorSetMetadata;
	public final layout:VkDescriptorSetLayout;
	public final set:VkDescriptorSet;
	public final buffers:Array<VulkanBuffer>;
	public final bufferHandles:Array<VkBuffer>;
	public final bufferRanges:Array<haxe.Int64>;
	public final images:Array<VulkanTexture>;
	public final views:Array<VkImageView>;
	public final samplers:Array<VkSampler>;

	public function new(metadata:VulkanDescriptorSetMetadata, layout:VkDescriptorSetLayout, set:VkDescriptorSet, buffers:Array<VulkanBuffer>,
		bufferHandles:Array<VkBuffer>, bufferRanges:Array<haxe.Int64>, images:Array<VulkanTexture>, views:Array<VkImageView>, samplers:Array<VkSampler>) {
		this.metadata = metadata;
		this.layout = layout;
		this.set = set;
		this.buffers = buffers;
		this.bufferHandles = bufferHandles;
		this.bufferRanges = bufferRanges;
		this.images = images;
		this.views = views;
		this.samplers = samplers;
	}

	public inline function matchesMetadata(candidate:VulkanDescriptorSetMetadata, candidateLayout:VkDescriptorSetLayout):Bool {
		return metadata == candidate && layout == candidateLayout;
	}

	public inline function matchesBuffer(index:Int, buffer:VulkanBuffer, range:haxe.Int64):Bool {
		return buffers[index] == buffer && bufferHandles[index] == buffer.buffer && bufferRanges[index] == range && !buffer.disposed;
	}

	public inline function matchesImage(index:Int, image:VulkanTexture, view:VkImageView, sampler:VkSampler):Bool {
		return images[index] == image && views[index] == view && samplers[index] == sampler && !image.disposed;
	}
}

class VulkanFrame {
	public static inline final MAX_DESCRIPTOR_CACHE_ENTRIES = 8192;
	public var command : VkCommandBuffer;
	public var fence : VkFence;
	public var imageAvailable : VkSemaphore;
	public var imageAvailableConsumed = false;
	public var submissionSerial = 0;
	public var descriptorArena : VulkanDescriptorArena;
	public var bindlessGeneration : VulkanBindlessGeneration;
	public final shaderConstants:Map<Int, VulkanConstantUpload> = new Map();
	public final descriptorSets:Map<Int, Array<VulkanDescriptorCacheEntry>> = new Map();
	public final resolvedDescriptorSets:Map<Int, {revision:Int, entry:VulkanDescriptorCacheEntry}> = new Map();
	public var descriptorCacheEntries = 0;
	public var descriptorCachePeakEntries = 0;
	public var descriptorCacheResetCount = 0;
	public var descriptorCacheHitCount = 0;
	public var descriptorCacheMissCount = 0;
	public var descriptorUpdateCount = 0;

	public function reclaimDescriptors() {
		if (!shouldReclaimDescriptors()) return;
		descriptorSets.clear();
		resolvedDescriptorSets.clear();
		descriptorCacheEntries = 0;
		descriptorArena.resetCacheAndPools();
		descriptorCacheResetCount++;
	}

	public inline function shouldReclaimDescriptors():Bool return descriptorCacheEntries >= MAX_DESCRIPTOR_CACHE_ENTRIES;

	public function recordDescriptorEntry() {
		descriptorCacheEntries++;
		if (descriptorCacheEntries > descriptorCachePeakEntries) descriptorCachePeakEntries = descriptorCacheEntries;
	}

	public function new() {
	}
}
#end
