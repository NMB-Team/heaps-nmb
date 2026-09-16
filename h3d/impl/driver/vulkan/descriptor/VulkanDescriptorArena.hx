package h3d.impl.driver.vulkan.descriptor;

#if (limen && gfx_vulkan)
import limen.graphics.vulkan.Runtime;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorPool;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorPoolCreateInfo;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorPoolSize;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSet;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSetAllocateInfo;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSetLayout;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorType;
import limen.graphics.vulkan.internal.VulkanBindings;
import limen.graphics.vulkan.internal.VulkanBindings.VkContext;

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
	var currentPool = 0;
	public var allocationCount(default, null) = 0;
	public var poolCreationCount(default, null) = 0;
	public var poolResetCount(default, null) = 0;
	public var pageCount(get, never):Int;

	function get_pageCount():Int return pools.length;

	public function new(context:VkContext) {
		this.context = context;
		pools.push(createPool(64, 256));
	}

	public function resetCacheAndPools() {
		for (page in pools) {
			final result = context.resetDescriptorPool(page.pool);
			if (result != 0)
				throw Runtime.error('Failed to reset frame descriptor pool (VkResult $result)');
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
		if (result.set == null) {
			page = growPool(descriptorCount);
			result = allocateFrom(page, layout);
		}
		if (result.set == null)
			throw Runtime.error('Failed to allocate frame descriptor set after pool growth (VkResult ${result.code})');
		page.usedSets++;
		page.usedDescriptors += descriptorCount;
		allocationCount++;
		return result.set;
	}

	function allocateFrom(page:VulkanDescriptorPoolPage, layout:VkDescriptorSetLayout):{set:VkDescriptorSet, code:Int} {
		final layouts = new hl.NativeArray<VkDescriptorSetLayout>(1);
		layouts[0] = layout;
		final sets = new hl.NativeArray<VkDescriptorSet>(1);
		final info = new VkDescriptorSetAllocateInfo();
		info.descriptorPool = page.pool;
		info.descriptorSetCount = 1;
		info.pSetLayouts = VulkanBindings.makeArray(layouts);
		final code = context.allocateDescriptorSets(info, sets);
		return {set: code == 0 ? sets[0] : null, code: code};
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
		final types = [
			VkDescriptorType.UNIFORM_BUFFER_DYNAMIC,
			VkDescriptorType.UNIFORM_BUFFER,
			VkDescriptorType.STORAGE_BUFFER,
			VkDescriptorType.COMBINED_IMAGE_SAMPLER,
			VkDescriptorType.STORAGE_IMAGE,
		];
		final sizes = new hl.NativeArray<VkDescriptorPoolSize>(types.length);
		for (index => type in types) {
			final size = new VkDescriptorPoolSize();
			size.type = type;
			size.descriptorCount = maxDescriptors;
			sizes[index] = size;
		}
		final info = new VkDescriptorPoolCreateInfo();
		info.maxSets = maxSets;
		info.poolSizeCount = sizes.length;
		info.pPoolSizes = VulkanBindings.makeArray(sizes);
		final pool = context.createDescriptorPool(info);
		if (pool == null)
			throw Runtime.error('Failed to create frame descriptor pool ($maxSets sets, $maxDescriptors descriptors)');
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
