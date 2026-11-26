package h3d.impl.driver.vulkan.descriptor;

#if (limen && gfx_vulkan)
import limen.vulkan.Vulkan as VulkanRuntime;
import limen.vulkan.descriptor.Descriptors.VkDescriptorPool;
import limen.vulkan.descriptor.Descriptors.VkDescriptorPoolCreateInfo;
import limen.vulkan.descriptor.Descriptors.VkDescriptorPoolSize;
import limen.vulkan.descriptor.Descriptors.VkDescriptorSet;
import limen.vulkan.descriptor.Descriptors.VkDescriptorSetAllocateInfo;
import limen.vulkan.descriptor.Descriptors.VkDescriptorSetLayout;
import limen.vulkan.descriptor.Descriptors.VkDescriptorType;
import limen.vulkan.internal.VulkanBindings;
import limen.vulkan.Context;

private class VulkanDescriptorPoolPage {
	public final pool:VkDescriptorPool;
	public final maxSets:Int;
	public final maxDescriptors:Int;
	public var usedSets = 0;
	public var idleResets = 0;
	public var usedDescriptors = 0;

	public function new(pool:VkDescriptorPool, maxSets:Int, maxDescriptors:Int) {
		this.pool = pool;
		this.maxSets = maxSets;
		this.maxDescriptors = maxDescriptors;
	}
}

class VulkanDescriptorArena {
	final context:Context;
	final pools:Array<VulkanDescriptorPoolPage> = [];
	final layouts = new hl.NativeArray<VkDescriptorSetLayout>(1);
	final sets = new hl.NativeArray<VkDescriptorSet>(1);
	final allocationInfo = new VkDescriptorSetAllocateInfo();
	final poolSizes = new hl.NativeArray<VkDescriptorPoolSize>(5);
	final poolInfo = new VkDescriptorPoolCreateInfo();
	var currentPool = 0;
	public var allocationCount(default, null) = 0;
	public var poolCreationCount(default, null) = 0;
	public var poolResetCount(default, null) = 0;
	public var pageCount(get, never):Int;

	function get_pageCount():Int return pools.length;

	public function new(context:Context) {
		this.context = context;
		allocationInfo.descriptorSetCount = 1;

		final types = [
			VkDescriptorType.UNIFORM_BUFFER_DYNAMIC,
			VkDescriptorType.UNIFORM_BUFFER,
			VkDescriptorType.STORAGE_BUFFER,
			VkDescriptorType.COMBINED_IMAGE_SAMPLER,
			VkDescriptorType.STORAGE_IMAGE,
		];
		for (index => type in types) {
			final size = new VkDescriptorPoolSize();
			size.type = type;
			poolSizes[index] = size;
		}
		poolInfo.poolSizeCount = poolSizes.length;

		pools.push(createPool(64, 256));
	}

	public function resetCacheAndPools(reuseOverflow = true) {
		if (!reuseOverflow)
			while (pools.length > 1)
				context.destroyDescriptorPool(pools.pop().pool);

		var retained = 1;
		for (index => page in pools) {
			if (page.usedSets != 0) {
				final result = context.resetDescriptorPool(page.pool);
				if (result != 0)
					throw VulkanRuntime.error('Failed to reset frame descriptor pool (VkResult $result)');
				page.usedSets = 0;
				page.usedDescriptors = 0;
				page.idleResets = 0;
			} else if (index != 0) {
				page.idleResets++;
			}

			if (page.idleResets < 2)
				retained = index + 1;
		}
		poolResetCount++;
		while (pools.length > retained)
			context.destroyDescriptorPool(pools.pop().pool);

		currentPool = 0;
	}

	public function preflight() {
		final page = pools[currentPool];
		if( page.usedSets == page.maxSets || page.usedDescriptors == page.maxDescriptors )
			nextPool(1);
	}

	public function allocate(layout:VkDescriptorSetLayout, descriptorCount:Int):VkDescriptorSet {
		var page = pools[currentPool];
		if (page.usedSets == page.maxSets || descriptorCount > page.maxDescriptors - page.usedDescriptors)
			page = nextPool(descriptorCount);

		var result = allocateFrom(page, layout);
		if (poolExhausted(result)) {
			page = nextPool(descriptorCount);
			result = allocateFrom(page, layout);
		}
		if (result == -1 || result == -2)
			result = allocateFrom(page, layout);
		if (result != 0)
			throw new h3d.impl.DescriptorAllocationError(
				VulkanRuntime.error('Failed to allocate frame descriptor set (VkResult $result)'),
				poolExhausted(result) || result == -1 || result == -2);

		page.usedSets++;
		page.usedDescriptors += descriptorCount;
		allocationCount++;
		return sets[0];
	}

	static inline function poolExhausted(result:Int) {
		return result == -1000069000 || result == -12;
	}

	function allocateFrom(page:VulkanDescriptorPoolPage, layout:VkDescriptorSetLayout):Int {
		if (layouts[0] != layout) {
			layouts[0] = layout;
			allocationInfo.pSetLayouts = VulkanBindings.makeArray(layouts);
		}
		allocationInfo.descriptorPool = page.pool;
		return context.allocateDescriptorSets(allocationInfo, sets);
	}

	function nextPool(requiredDescriptors:Int):VulkanDescriptorPoolPage {
		var index = currentPool + 1;
		while (index < pools.length) {
			final page = pools[index];
			if (page.usedSets < page.maxSets && requiredDescriptors <= page.maxDescriptors - page.usedDescriptors) {
				currentPool = index;
				return page;
			}
			index++;
		}

		final previous = pools[pools.length - 1];
		if (previous.maxSets > 0x3FFFFFFF || previous.maxDescriptors > 0x3FFFFFFF)
			throw new h3d.impl.DescriptorAllocationError("Vulkan frame descriptor arena exhausted", true);

		final page = try createPool(previous.maxSets * 2, hxd.Math.imax(previous.maxDescriptors * 2, requiredDescriptors))
		catch( error : h3d.impl.DescriptorAllocationError ) {
			if( !error.recoverable )
				throw error;
			createPool(64, hxd.Math.imax(256, requiredDescriptors));
		};
		currentPool = pools.length;
		pools.push(page);
		return page;
	}

	function createPool(maxSets:Int, maxDescriptors:Int):VulkanDescriptorPoolPage {
		for (size in poolSizes)
			size.descriptorCount = maxDescriptors;

		poolInfo.maxSets = maxSets;
		poolInfo.pPoolSizes = VulkanBindings.makeArray(poolSizes);
		final pool = context.createDescriptorPool(poolInfo);
		if (pool == null) {
			final message = VulkanRuntime.error('Failed to create frame descriptor pool ($maxSets sets, $maxDescriptors descriptors)');
			throw new h3d.impl.DescriptorAllocationError(message,
				StringTools.endsWith(message, 'VK_ERROR_OUT_OF_HOST_MEMORY (-1)') ||
				StringTools.endsWith(message, 'VK_ERROR_OUT_OF_DEVICE_MEMORY (-2)') ||
				StringTools.endsWith(message, 'VK_ERROR_FRAGMENTATION (-1000161000)'));
		}
		poolCreationCount++;
		return new VulkanDescriptorPoolPage(pool, maxSets, maxDescriptors);
	}

	public function dispose() {
		for (page in pools)
			context.destroyDescriptorPool(page.pool);
		pools.resize(0);
	}
}
#end
