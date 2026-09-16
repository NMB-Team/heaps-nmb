package h3d.impl.driver.vulkan.descriptor;

#if (limen && gfx_vulkan)
import haxe.Int64;
import limen.graphics.vulkan.Runtime;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorBindingFlag;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorPool;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorPoolCreateInfo;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorPoolSize;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSet;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSetAllocateInfo;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSetLayout;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSetLayoutBinding;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSetLayoutBindingFlagsCreateInfo;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSetLayoutCreateInfo;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorType;
import limen.graphics.vulkan.device.Capabilities;
import limen.graphics.vulkan.internal.VulkanBindings;
import limen.graphics.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.vulkan.memory.Memory.VkBuffer;
import limen.graphics.vulkan.memory.Memory.VkImageLayout;
import limen.graphics.vulkan.memory.Memory.VkImageView;
import limen.graphics.vulkan.sampler.Samplers.VkSampler;
import limen.graphics.vulkan.shader.ShaderModule.VkShaderStageFlag;

private class VulkanBindlessImageSlot {
	public var view:VkImageView;
	public var layout:VkImageLayout;
	public var version = 0;
	public var allocated = false;
	public function new() {}
}

private class VulkanBindlessSamplerSlot {
	public var sampler:VkSampler;
	public var version = 0;
	public var allocated = false;
	public function new() {}
}

private class VulkanBindlessBufferSlot {
	public var buffer:VkBuffer;
	public var range:Int64;
	public var version = 0;
	public var allocated = false;
	public function new() {}
}

private class VulkanBindlessSlotAllocator {
	final label:String;
	final capacity:Int;
	final deviceLimit:Int;
	final free:Array<Int> = [];
	var next = 0;
	var activeCapacity:Int;
	public var highWater(default, null) = 0;

	public function new(label:String, capacity:Int, deviceLimit:Int) {
		this.label = label;
		this.capacity = capacity;
		this.deviceLimit = deviceLimit;
		activeCapacity = hxd.Math.imin(1024, capacity);
	}

	public function allocate():Int {
		if (free.length != 0)
			return free.pop();
		if (next == activeCapacity && activeCapacity < capacity)
			activeCapacity = hxd.Math.imin(capacity, activeCapacity << 1);
		if (next >= capacity)
			throw 'Vulkan bindless $label capacity exhausted: usage=$next, configuredCapacity=$capacity, deviceLimit=$deviceLimit';
		final index = next++;
		if (next > highWater) highWater = next;
		return index;
	}

	public function release(index:Int) {
		free.push(index);
	}

	public inline function allocatedCount():Int {
		return next - free.length;
	}
}

class VulkanBindlessGeneration {
	public final set:VkDescriptorSet;
	final imageVersions:Array<Int>;
	final samplerVersions:Array<Int>;
	final bufferVersions:Array<Int>;
	public var descriptorWrites(default, null) = 0;
	public var descriptorUpdateCalls(default, null) = 0;

	public function new(set:VkDescriptorSet, imageCapacity:Int, samplerCapacity:Int, bufferCapacity:Int) {
		this.set = set;
		imageVersions = [for (_ in 0...imageCapacity) -1];
		samplerVersions = [for (_ in 0...samplerCapacity) -1];
		bufferVersions = [for (_ in 0...bufferCapacity) -1];
	}
}

class VulkanBindlessDescriptors {
	public static inline final IMAGE_BINDING = 0;
	public static inline final SAMPLER_BINDING = 1;
	public static inline final BUFFER_BINDING = 2;

	final context:VkContext;
	final imageSlots:Array<VulkanBindlessImageSlot>;
	final samplerSlots:Array<VulkanBindlessSamplerSlot>;
	final bufferSlots:Array<VulkanBindlessBufferSlot>;
	final imageAllocator:VulkanBindlessSlotAllocator;
	final samplerAllocator:VulkanBindlessSlotAllocator;
	final bufferAllocator:VulkanBindlessSlotAllocator;
	final pool:VkDescriptorPool;
	public final layout:VkDescriptorSetLayout;
	public final imageCapacity:Int;
	public final samplerCapacity:Int;
	public final bufferCapacity:Int;
	public var slotRetirements(default, null) = 0;
	public var slotReuses(default, null) = 0;

	public static function supported(capabilities:Capabilities, generationCount:Int):Bool {
		return capabilities.bindless && capabilities.maxUpdateAfterBindDescriptorsInAllPools >= generationCount * 3
			&& capabilities.maxPerStageDescriptorUpdateAfterBindResources >= 3
			&& capabilities.maxPerStageDescriptorUpdateAfterBindSampledImages > 0
			&& capabilities.maxPerStageDescriptorUpdateAfterBindSamplers > 0
			&& capabilities.maxPerStageDescriptorUpdateAfterBindStorageBuffers > 0
			&& capabilities.maxDescriptorSetUpdateAfterBindSampledImages > 0
			&& capabilities.maxDescriptorSetUpdateAfterBindSamplers > 0
			&& capabilities.maxDescriptorSetUpdateAfterBindStorageBuffers > 0;
	}

	public function new(context:VkContext, capabilities:Capabilities, generationCount:Int) {
		if (!supported(capabilities, generationCount))
			throw "Vulkan bindless descriptors require the descriptor-indexing capability set";
		this.context = context;
		final totalLimit = capabilities.maxUpdateAfterBindDescriptorsInAllPools;
		final perClassBudget = hxd.Math.imin(Std.int(totalLimit / generationCount / 3),
			Std.int(capabilities.maxPerStageDescriptorUpdateAfterBindResources / 3));
		final imageLimit = hxd.Math.imin(perClassBudget, hxd.Math.imin(capabilities.maxPerStageDescriptorUpdateAfterBindSampledImages,
			capabilities.maxDescriptorSetUpdateAfterBindSampledImages));
		final samplerLimit = hxd.Math.imin(perClassBudget, hxd.Math.imin(capabilities.maxPerStageDescriptorUpdateAfterBindSamplers,
			capabilities.maxDescriptorSetUpdateAfterBindSamplers));
		final bufferLimit = hxd.Math.imin(perClassBudget, hxd.Math.imin(capabilities.maxPerStageDescriptorUpdateAfterBindStorageBuffers,
			capabilities.maxDescriptorSetUpdateAfterBindStorageBuffers));
		imageCapacity = configuredCapacity("VULKAN_BINDLESS_IMAGE_CAPACITY", 4096, imageLimit);
		samplerCapacity = configuredCapacity("VULKAN_BINDLESS_SAMPLER_CAPACITY", 2048, samplerLimit);
		bufferCapacity = configuredCapacity("VULKAN_BINDLESS_BUFFER_CAPACITY", 4096, bufferLimit);
		if (imageCapacity <= 0 || samplerCapacity <= 0 || bufferCapacity <= 0)
			throw 'Vulkan descriptor-indexing limits cannot provide positive bindless capacities: images=$imageCapacity, samplers=$samplerCapacity, buffers=$bufferCapacity';
		imageSlots = [for (_ in 0...imageCapacity) new VulkanBindlessImageSlot()];
		samplerSlots = [for (_ in 0...samplerCapacity) new VulkanBindlessSamplerSlot()];
		bufferSlots = [for (_ in 0...bufferCapacity) new VulkanBindlessBufferSlot()];
		imageAllocator = new VulkanBindlessSlotAllocator("sampled-image", imageCapacity, imageLimit);
		samplerAllocator = new VulkanBindlessSlotAllocator("sampler", samplerCapacity, samplerLimit);
		bufferAllocator = new VulkanBindlessSlotAllocator("storage-buffer", bufferCapacity, bufferLimit);
		layout = createLayout();
		pool = createPool(generationCount);
	}

	static function configuredCapacity(name:String, preferred:Int, limit:Int):Int {
		final configured = Sys.getEnv(name);
		final requested = configured == null ? preferred : Std.parseInt(configured);
		if (requested == null || requested <= 0)
			throw '$name must be a positive integer';
		return hxd.Math.imin(requested, limit);
	}

	function createLayout():VkDescriptorSetLayout {
		final bindings = new hl.NativeArray<VkDescriptorSetLayoutBinding>(3);
		for (index => descriptorType in [VkDescriptorType.SAMPLED_IMAGE, VkDescriptorType.SAMPLER, VkDescriptorType.STORAGE_BUFFER]) {
			final binding = new VkDescriptorSetLayoutBinding();
			binding.binding = index;
			binding.descriptorType = descriptorType;
			binding.descriptorCount = index == IMAGE_BINDING ? imageCapacity : index == SAMPLER_BINDING ? samplerCapacity : bufferCapacity;
			binding.stageFlags.set(VkShaderStageFlag.VERTEX);
			binding.stageFlags.set(VkShaderStageFlag.FRAGMENT);
			binding.stageFlags.set(VkShaderStageFlag.COMPUTE);
			bindings[index] = binding;
		}
		final flags = new hl.NativeArray<VkDescriptorBindingFlag>(3);
		for (index in 0...3)
			flags[index] = cast((cast VkDescriptorBindingFlag.UPDATE_AFTER_BIND : Int) | (cast VkDescriptorBindingFlag.PARTIALLY_BOUND : Int));
		final bindingFlags = new VkDescriptorSetLayoutBindingFlagsCreateInfo();
		bindingFlags.bindingCount = flags.length;
		bindingFlags.bindingFlags = VulkanBindings.makeArray(flags);
		final info = new VkDescriptorSetLayoutCreateInfo();
		info.flags.set(UPDATE_AFTER_BIND_POOL);
		info.bindingCount = bindings.length;
		info.bindings = VulkanBindings.makeArray(bindings);
		@:privateAccess info.next = cast VulkanBindings.makeRef(bindingFlags);
		final result = context.createDescriptorSetLayout(info);
		if (result == null)
			throw Runtime.error("Failed to create Vulkan bindless descriptor-set layout");
		return result;
	}

	function createPool(generationCount:Int):VkDescriptorPool {
		final sizes = new hl.NativeArray<VkDescriptorPoolSize>(3);
		for (index => entry in [
			{type: VkDescriptorType.SAMPLED_IMAGE, count: imageCapacity},
			{type: VkDescriptorType.SAMPLER, count: samplerCapacity},
			{type: VkDescriptorType.STORAGE_BUFFER, count: bufferCapacity},
		]) {
			final size = new VkDescriptorPoolSize();
			size.type = entry.type;
			size.descriptorCount = entry.count * generationCount;
			sizes[index] = size;
		}
		final info = new VkDescriptorPoolCreateInfo();
		info.flags.set(UPDATE_AFTER_BIND);
		info.maxSets = generationCount;
		info.poolSizeCount = sizes.length;
		info.pPoolSizes = VulkanBindings.makeArray(sizes);
		final result = context.createDescriptorPool(info);
		if (result == null)
			throw Runtime.error("Failed to create Vulkan bindless descriptor pool");
		return result;
	}

	public function createGeneration():VulkanBindlessGeneration {
		final layouts = new hl.NativeArray<VkDescriptorSetLayout>(1);
		layouts[0] = layout;
		final sets = new hl.NativeArray<VkDescriptorSet>(1);
		final info = new VkDescriptorSetAllocateInfo();
		info.descriptorPool = pool;
		info.descriptorSetCount = 1;
		info.pSetLayouts = VulkanBindings.makeArray(layouts);
		final result = context.allocateDescriptorSets(info, sets);
		if (result != 0)
			throw Runtime.error('Failed to allocate Vulkan bindless descriptor generation (VkResult $result)');
		return new VulkanBindlessGeneration(sets[0], imageCapacity, samplerCapacity, bufferCapacity);
	}

	public function allocateImage(view:VkImageView, layout:VkImageLayout):Int {
		final index = imageAllocator.allocate();
		final slot = imageSlots[index];
		if (slot.version != 0) slotReuses++;
		slot.view = view;
		slot.layout = layout;
		slot.allocated = true;
		slot.version++;
		return index;
	}

	public function updateImage(index:Int, view:VkImageView, layout:VkImageLayout) {
		final slot = imageSlots[index];
		slot.view = view;
		slot.layout = layout;
		slot.version++;
	}

	public function allocateSampler(sampler:VkSampler):Int {
		final index = samplerAllocator.allocate();
		final slot = samplerSlots[index];
		slot.sampler = sampler;
		slot.allocated = true;
		slot.version++;
		return index;
	}

	public function allocateBuffer(buffer:VkBuffer, range:Int64):Int {
		final index = bufferAllocator.allocate();
		final slot = bufferSlots[index];
		if (slot.version != 0) slotReuses++;
		slot.buffer = buffer;
		slot.range = range;
		slot.allocated = true;
		slot.version++;
		return index;
	}

	public function sync(generation:VulkanBindlessGeneration) {
		var writes = 0;
		var updateCalls = 0;
		var index = 0;
		while (index < imageSlots.length) {
			final slot = imageSlots[index];
			if (!slot.allocated || @:privateAccess generation.imageVersions[index] == slot.version) {
				index++;
				continue;
			}
			final first = index;
			while (index < imageSlots.length && imageSlots[index].allocated
				&& @:privateAccess generation.imageVersions[index] != imageSlots[index].version)
				index++;
			final views = new hl.NativeArray<VkImageView>(index - first);
			for (slotIndex in first...index) {
				views[slotIndex - first] = imageSlots[slotIndex].view;
				@:privateAccess generation.imageVersions[slotIndex] = imageSlots[slotIndex].version;
			}
			context.updateDescriptorSampledImageRange(generation.set, IMAGE_BINDING, first, views, VkImageLayout.SHADER_READ_ONLY_OPTIMAL);
			writes += index - first;
			updateCalls++;
		}
		index = 0;
		while (index < samplerSlots.length) {
			final slot = samplerSlots[index];
			if (!slot.allocated || @:privateAccess generation.samplerVersions[index] == slot.version) {
				index++;
				continue;
			}
			final first = index;
			while (index < samplerSlots.length && samplerSlots[index].allocated
				&& @:privateAccess generation.samplerVersions[index] != samplerSlots[index].version)
				index++;
			final samplers = new hl.NativeArray<VkSampler>(index - first);
			for (slotIndex in first...index) {
				samplers[slotIndex - first] = samplerSlots[slotIndex].sampler;
				@:privateAccess generation.samplerVersions[slotIndex] = samplerSlots[slotIndex].version;
			}
			context.updateDescriptorSamplerRange(generation.set, SAMPLER_BINDING, first, samplers);
			writes += index - first;
			updateCalls++;
		}
		index = 0;
		while (index < bufferSlots.length) {
			final slot = bufferSlots[index];
			if (!slot.allocated || @:privateAccess generation.bufferVersions[index] == slot.version) {
				index++;
				continue;
			}
			final first = index;
			while (index < bufferSlots.length && bufferSlots[index].allocated
				&& @:privateAccess generation.bufferVersions[index] != bufferSlots[index].version)
				index++;
			final buffers = new hl.NativeArray<VkBuffer>(index - first);
			final ranges = new hl.NativeArray<hl.I64>(index - first);
			for (slotIndex in first...index) {
				buffers[slotIndex - first] = bufferSlots[slotIndex].buffer;
				ranges[slotIndex - first] = (bufferSlots[slotIndex].range : hl.I64);
				@:privateAccess generation.bufferVersions[slotIndex] = bufferSlots[slotIndex].version;
			}
			context.updateDescriptorBufferRange(generation.set, BUFFER_BINDING, first, VkDescriptorType.STORAGE_BUFFER, buffers, ranges);
			writes += index - first;
			updateCalls++;
		}
		@:privateAccess generation.descriptorWrites += writes;
		@:privateAccess generation.descriptorUpdateCalls += updateCalls;
	}

	public function releaseImage(index:Int) {
		imageSlots[index].allocated = false;
		imageAllocator.release(index);
		slotRetirements++;
	}

	public function releaseBuffer(index:Int) {
		bufferSlots[index].allocated = false;
		bufferAllocator.release(index);
		slotRetirements++;
	}

	public inline function imageCount():Int return imageAllocator.allocatedCount();
	public inline function samplerCount():Int return samplerAllocator.allocatedCount();
	public inline function bufferCount():Int return bufferAllocator.allocatedCount();
	public inline function imageHighWater():Int return imageAllocator.highWater;
	public inline function samplerHighWater():Int return samplerAllocator.highWater;
	public inline function bufferHighWater():Int return bufferAllocator.highWater;

	public function dispose() {
		context.destroyDescriptorPool(pool);
		context.destroyDescriptorSetLayout(layout);
	}
}
#end
