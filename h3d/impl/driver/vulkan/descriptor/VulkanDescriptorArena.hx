package h3d.impl.driver.vulkan.descriptor;

#if (limen && gfx_vulkan)
import limen.graphics.renderer.vulkan.Vulkan as VulkanRuntime;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorPool;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorPoolCreateInfo;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorPoolSize;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorSet;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorSetAllocateInfo;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorSetLayout;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorType;
import limen.graphics.renderer.vulkan.internal.VulkanBindings;
import limen.graphics.renderer.vulkan.internal.VulkanBindings.VkContext;

private class VulkanDescriptorPoolPage {
	public final pool:VkDescriptorPool;
	public final maxSets:Int;
	public final maxDescriptors:Int;
	public var usedSets = 0;
	public var usedDescriptors = 0;

	public function new(pool:VkDescriptorPool, maxSets:Int, maxDescriptors:Int) {
		this.pool = pool;
		this.maxSets = maxSets;
		this.maxDescriptors = maxDescriptors;
	}
}

class VulkanDescriptorArena {
	final context:VkContext;
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

	public function new(context:VkContext) {
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

	public function resetCacheAndPools() {
		for (page in pools) {
			final result = context.resetDescriptorPool(page.pool);
			if (result != 0)
				throw VulkanRuntime.error('Failed to reset frame descriptor pool (VkResult $result)');
			page.usedSets = 0;
			page.usedDescriptors = 0;
		}
		poolResetCount++;
		while (pools.length > 1)
			context.destroyDescriptorPool(pools.pop().pool);
		currentPool = 0;
	}

	public function allocate(layout:VkDescriptorSetLayout, descriptorCount:Int):VkDescriptorSet {
		var page = pools[currentPool];
		if (page.usedSets == page.maxSets || page.usedDescriptors + descriptorCount > page.maxDescriptors)
			page = nextPool(descriptorCount);
		var result = allocateFrom(page, layout);
		if (result != 0) {
			page = growPool(descriptorCount);
			result = allocateFrom(page, layout);
		}
		if (result != 0)
			throw VulkanRuntime.error('Failed to allocate frame descriptor set after pool growth (VkResult $result)');
		page.usedSets++;
		page.usedDescriptors += descriptorCount;
		allocationCount++;
		return sets[0];
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
		currentPool++;
		if (currentPool == pools.length) {
			final previous = pools[currentPool - 1];
			pools.push(createPool(previous.maxSets << 1, hxd.Math.imax(previous.maxDescriptors << 1, requiredDescriptors)));
		}
		return pools[currentPool];
	}

	function growPool(requiredDescriptors:Int):VulkanDescriptorPoolPage {
		currentPool = pools.length;
		final previous = pools[pools.length - 1];
		final page = createPool(previous.maxSets << 1, hxd.Math.imax(previous.maxDescriptors << 1, requiredDescriptors));
		pools.push(page);
		return page;
	}

	function createPool(maxSets:Int, maxDescriptors:Int):VulkanDescriptorPoolPage {
		for (size in poolSizes)
			size.descriptorCount = maxDescriptors;

		poolInfo.maxSets = maxSets;
		poolInfo.pPoolSizes = VulkanBindings.makeArray(poolSizes);
		final pool = context.createDescriptorPool(poolInfo);
		if (pool == null)
			throw VulkanRuntime.error('Failed to create frame descriptor pool ($maxSets sets, $maxDescriptors descriptors)');
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
