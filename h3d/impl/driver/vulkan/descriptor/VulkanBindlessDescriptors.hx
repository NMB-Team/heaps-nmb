package h3d.impl.driver.vulkan.descriptor;

#if (limen && gfx_vulkan)
import haxe.Int64;
import limen.graphics.renderer.vulkan.Vulkan as VulkanRuntime;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorBindingFlag;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorPool;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorPoolCreateInfo;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorPoolSize;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorSet;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorSetAllocateInfo;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorSetLayout;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorSetLayoutBinding;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorSetLayoutBindingFlagsCreateInfo;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorSetLayoutCreateInfo;
import limen.graphics.renderer.vulkan.descriptor.Descriptors.VkDescriptorType;
import limen.graphics.renderer.vulkan.device.Capabilities;
import limen.graphics.renderer.vulkan.internal.VulkanBindings;
import limen.graphics.renderer.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.renderer.vulkan.memory.Memory.VkBuffer;
import limen.graphics.renderer.vulkan.memory.Memory.VkImageLayout;
import limen.graphics.renderer.vulkan.memory.Memory.VkImageView;
import limen.graphics.renderer.vulkan.sampler.Samplers.VkSampler;
import limen.graphics.renderer.vulkan.shader.ShaderModule.VkShaderStageFlag;

private class VulkanBindlessImageSlot {
	public var view:VkImageView;
	public var layout:VkImageLayout;
	public var version = 0;
	public var allocated = false;
	public function new() {}
}

private class VulkanBindlessSamplerSlot {
	public var sampler:VkSampler;
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
	final imageDirty:Array<Bool>;
	final imagePending:Array<Int> = [];
	final samplerDirty:Array<Bool>;
	final samplerPending:Array<Int> = [];
	final bufferDirty:Array<Bool>;
	final bufferPending:Array<Int> = [];
	public var descriptorWrites(default, null) = 0;
	public var descriptorUpdateCalls(default, null) = 0;

	public function new(set:VkDescriptorSet, imageCapacity:Int, samplerCapacity:Int, bufferCapacity:Int) {
		this.set = set;
		imageDirty = [for (_ in 0...imageCapacity) false];
		samplerDirty = [for (_ in 0...samplerCapacity) false];
		bufferDirty = [for (_ in 0...bufferCapacity) false];
	}
}

class VulkanBindlessDescriptors {
	public static inline final IMAGE_BINDING = 0;
	public static inline final SAMPLER_BINDING = 1;
	public static inline final BUFFER_BINDING = 2;

	final context:VkContext;
	final generations:Array<VulkanBindlessGeneration> = [];
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
		pool = try createPool(generationCount) catch (error:Dynamic) {
			context.destroyDescriptorSetLayout(layout);
			throw error;
		};
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
			throw VulkanRuntime.error("Failed to create Vulkan bindless descriptor-set layout");
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
			throw VulkanRuntime.error("Failed to create Vulkan bindless descriptor pool");
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
			throw VulkanRuntime.error('Failed to allocate Vulkan bindless descriptor generation (VkResult $result)');
		final generation = new VulkanBindlessGeneration(sets[0], imageCapacity, samplerCapacity, bufferCapacity);
		generations.push(generation);
		for (index in 0...imageAllocator.highWater)
			if (imageSlots[index].allocated) {
				@:privateAccess generation.imageDirty[index] = true;
				@:privateAccess generation.imagePending.push(index);
			}
		for (index in 0...samplerAllocator.highWater)
			if (samplerSlots[index].allocated) {
				@:privateAccess generation.samplerDirty[index] = true;
				@:privateAccess generation.samplerPending.push(index);
			}
		for (index in 0...bufferAllocator.highWater)
			if (bufferSlots[index].allocated) {
				@:privateAccess generation.bufferDirty[index] = true;
				@:privateAccess generation.bufferPending.push(index);
			}
		return generation;
	}

	public function allocateImage(view:VkImageView, layout:VkImageLayout):Int {
		final index = imageAllocator.allocate();
		final slot = imageSlots[index];
		if (slot.version != 0) slotReuses++;
		slot.view = view;
		slot.layout = layout;
		slot.allocated = true;
		slot.version++;
		markImage(index);
		return index;
	}

	public function updateImage(index:Int, view:VkImageView, layout:VkImageLayout) {
		final slot = imageSlots[index];
		if (slot.allocated && slot.view == view && slot.layout == layout)
			return;
		slot.view = view;
		slot.layout = layout;
		slot.allocated = true;
		slot.version++;
		markImage(index);
	}

	public function suspendImage(index:Int) {
		imageSlots[index].allocated = false;
		markImage(index);
	}

	public function allocateSampler(sampler:VkSampler):Int {
		final index = samplerAllocator.allocate();
		final slot = samplerSlots[index];
		slot.sampler = sampler;
		slot.allocated = true;
		markSampler(index);
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
		markBuffer(index);
		return index;
	}

	static function compareSlots(a:Int, b:Int):Int {
		return a - b;
	}

	function markImage(index:Int) {
		for (generation in generations) {
			if (!@:privateAccess generation.imageDirty[index]) {
				@:privateAccess generation.imageDirty[index] = true;
				@:privateAccess generation.imagePending.push(index);
			}
		}
	}

	function markSampler(index:Int) {
		for (generation in generations) {
			if (!@:privateAccess generation.samplerDirty[index]) {
				@:privateAccess generation.samplerDirty[index] = true;
				@:privateAccess generation.samplerPending.push(index);
			}
		}
	}

	function markBuffer(index:Int) {
		for (generation in generations) {
			if (!@:privateAccess generation.bufferDirty[index]) {
				@:privateAccess generation.bufferDirty[index] = true;
				@:privateAccess generation.bufferPending.push(index);
			}
		}
	}

	public function sync(generation:VulkanBindlessGeneration) {
		if (@:privateAccess generation.imagePending.length == 0
			&& @:privateAccess generation.samplerPending.length == 0
			&& @:privateAccess generation.bufferPending.length == 0)
			return;

		var writes = 0;
		var updateCalls = 0;

		final imagePending = @:privateAccess generation.imagePending;
		haxe.ds.ArraySort.sort(imagePending, compareSlots);
		var imageCursor = 0;
		while (imageCursor < imagePending.length) {
			final first = imagePending[imageCursor++];
			@:privateAccess generation.imageDirty[first] = false;
			if (!imageSlots[first].allocated)
				continue;

			var end = first + 1;
			while (imageCursor < imagePending.length && imagePending[imageCursor] == end && imageSlots[end].allocated) {
				@:privateAccess generation.imageDirty[end] = false;
				imageCursor++;
				end++;
			}
			final views = new hl.NativeArray<VkImageView>(end - first);
			for (slotIndex in first...end) {
				views[slotIndex - first] = imageSlots[slotIndex].view;
			}
			context.updateDescriptorSampledImageRange(generation.set, IMAGE_BINDING, first, views, VkImageLayout.SHADER_READ_ONLY_OPTIMAL);
			writes += end - first;
			updateCalls++;
		}
		imagePending.resize(0);

		final samplerPending = @:privateAccess generation.samplerPending;
		haxe.ds.ArraySort.sort(samplerPending, compareSlots);
		var samplerCursor = 0;
		while (samplerCursor < samplerPending.length) {
			final first = samplerPending[samplerCursor++];
			@:privateAccess generation.samplerDirty[first] = false;
			if (!samplerSlots[first].allocated)
				continue;

			var end = first + 1;
			while (samplerCursor < samplerPending.length && samplerPending[samplerCursor] == end && samplerSlots[end].allocated) {
				@:privateAccess generation.samplerDirty[end] = false;
				samplerCursor++;
				end++;
			}
			final samplers = new hl.NativeArray<VkSampler>(end - first);
			for (slotIndex in first...end) {
				samplers[slotIndex - first] = samplerSlots[slotIndex].sampler;
			}
			context.updateDescriptorSamplerRange(generation.set, SAMPLER_BINDING, first, samplers);
			writes += end - first;
			updateCalls++;
		}
		samplerPending.resize(0);

		final bufferPending = @:privateAccess generation.bufferPending;
		haxe.ds.ArraySort.sort(bufferPending, compareSlots);
		var bufferCursor = 0;
		while (bufferCursor < bufferPending.length) {
			final first = bufferPending[bufferCursor++];
			@:privateAccess generation.bufferDirty[first] = false;
			if (!bufferSlots[first].allocated)
				continue;

			var end = first + 1;
			while (bufferCursor < bufferPending.length && bufferPending[bufferCursor] == end && bufferSlots[end].allocated) {
				@:privateAccess generation.bufferDirty[end] = false;
				bufferCursor++;
				end++;
			}
			final buffers = new hl.NativeArray<VkBuffer>(end - first);
			final ranges = new hl.NativeArray<hl.I64>(end - first);
			for (slotIndex in first...end) {
				buffers[slotIndex - first] = bufferSlots[slotIndex].buffer;
				ranges[slotIndex - first] = (bufferSlots[slotIndex].range : hl.I64);
			}
			context.updateDescriptorBufferRange(generation.set, BUFFER_BINDING, first, VkDescriptorType.STORAGE_BUFFER, buffers, ranges);
			writes += end - first;
			updateCalls++;
		}
		bufferPending.resize(0);
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
