package h3d.impl.driver.vulkan.pipeline;

#if (limen && gfx_vulkan)
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanShaderStage;
import limen.graphics.vulkan.Runtime;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSetLayout;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSetLayoutBinding;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSetLayoutCreateInfo;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorType;
import limen.graphics.vulkan.internal.VulkanBindings;
import limen.graphics.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineLayout;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineLayoutCreateInfo;
import limen.graphics.vulkan.shader.ShaderModule.VkShaderStageFlag;

class VulkanPipelineLayoutResource {
	public final signature:String;
	public final descriptorSetLayouts:Array<VkDescriptorSetLayout>;
	public final ownedDescriptorSetLayouts:Array<Bool>;
	public final layout:VkPipelineLayout;
	public var references = 1;

	public function new(signature:String, descriptorSetLayouts:Array<VkDescriptorSetLayout>, ownedDescriptorSetLayouts:Array<Bool>, layout:VkPipelineLayout) {
		this.signature = signature;
		this.descriptorSetLayouts = descriptorSetLayouts;
		this.ownedDescriptorSetLayouts = ownedDescriptorSetLayouts;
		this.layout = layout;
	}
}

class VulkanPipelineLayoutCache {
	final context:VkContext;
	final layouts:Map<String, VulkanPipelineLayoutResource> = new Map();
	final bindlessLayout:VkDescriptorSetLayout;
	public var createdCount(default, null) = 0;
	public var hitCount(default, null) = 0;

	public function new(context:VkContext, bindlessLayout:VkDescriptorSetLayout = null) {
		this.context = context;
		this.bindlessLayout = bindlessLayout;
	}

	public function acquire(abi:VulkanShaderAbi):VulkanPipelineLayoutResource {
		final signature = signature(abi);
		final existing = layouts.get(signature);
		if (existing != null) {
			existing.references++;
			hitCount++;
			return existing;
		}
		final resource = create(signature, abi);
		layouts.set(signature, resource);
		createdCount++;
		return resource;
	}

	function create(signature:String, abi:VulkanShaderAbi):VulkanPipelineLayoutResource {
		var highestSet = -1;
		for (resource in abi.resources)
			if (resource.set > highestSet) highestSet = resource.set;
		for (block in abi.constantBlocks)
			if (block.set > highestSet) highestSet = block.set;
		if (abi.hasBindless)
			highestSet = VulkanShaderAbi.BINDLESS_SET;
		final setLayouts:Array<VkDescriptorSetLayout> = [];
		final ownedSetLayouts:Array<Bool> = [];
		var pipelineLayout:VkPipelineLayout = null;
		try {
			for (setIndex in 0...highestSet + 1) {
				if (abi.hasBindless && setIndex == VulkanShaderAbi.BINDLESS_SET) {
					if (bindlessLayout == null)
						throw "Vulkan bindless shader requires a shared bindless descriptor-set layout";
					setLayouts.push(bindlessLayout);
					ownedSetLayouts.push(false);
					continue;
				}
				final bindings = [];
				for (block in abi.constantBlocks)
					if (block.set == setIndex)
						bindings.push(makeBinding(block.binding, VkDescriptorType.UNIFORM_BUFFER_DYNAMIC, 1, block.stage));
				for (resource in abi.resources)
					if (resource.set == setIndex)
						bindings.push(makeBinding(resource.binding, cast resource.descriptorType, resource.count, resource.stages));
				bindings.sort((left, right) -> left.binding - right.binding);
				final nativeBindings = new hl.NativeArray<VkDescriptorSetLayoutBinding>(bindings.length);
				for (index => binding in bindings) nativeBindings[index] = binding;
				final info = new VkDescriptorSetLayoutCreateInfo();
				info.bindingCount = bindings.length;
				info.bindings = bindings.length == 0 ? null : VulkanBindings.makeArray(nativeBindings);
				final setLayout = context.createDescriptorSetLayout(info);
				if (setLayout == null)
					throw Runtime.error('Failed to create Vulkan descriptor-set layout $setIndex');
				setLayouts.push(setLayout);
				ownedSetLayouts.push(true);
			}
			final nativeSetLayouts = new hl.NativeArray<VkDescriptorSetLayout>(setLayouts.length);
			for (index => setLayout in setLayouts) nativeSetLayouts[index] = setLayout;
			final info = new VkPipelineLayoutCreateInfo();
			info.setLayoutCount = setLayouts.length;
			info.setLayouts = setLayouts.length == 0 ? null : VulkanBindings.makeArray(nativeSetLayouts);
			pipelineLayout = context.createPipelineLayout(info);
			if (pipelineLayout == null)
				throw Runtime.error("Failed to create Vulkan pipeline layout");
			return new VulkanPipelineLayoutResource(signature, setLayouts, ownedSetLayouts, pipelineLayout);
		} catch (error:Dynamic) {
			if (pipelineLayout != null) context.destroyPipelineLayout(pipelineLayout);
			for (index => setLayout in setLayouts)
				if (ownedSetLayouts[index]) context.destroyDescriptorSetLayout(setLayout);
			throw error;
		}
	}

	function makeBinding(binding:Int, descriptorType:VkDescriptorType, count:Int, stages:Int):VkDescriptorSetLayoutBinding {
		final result = new VkDescriptorSetLayoutBinding();
		result.binding = binding;
		result.descriptorType = descriptorType;
		result.descriptorCount = count;
		if ((stages & VulkanShaderStage.Vertex) != 0) result.stageFlags.set(VkShaderStageFlag.VERTEX);
		if ((stages & VulkanShaderStage.Fragment) != 0) result.stageFlags.set(VkShaderStageFlag.FRAGMENT);
		if ((stages & VulkanShaderStage.Compute) != 0) result.stageFlags.set(VkShaderStageFlag.COMPUTE);
		return result;
	}

	static function signature(abi:VulkanShaderAbi):String {
		final entries = [];
		for (block in abi.constantBlocks)
			entries.push('${block.set}:${block.binding}:${cast(VkDescriptorType.UNIFORM_BUFFER_DYNAMIC, Int)}:1:${block.stage}');
		for (resource in abi.resources)
			entries.push('${resource.set}:${resource.binding}:${cast(resource.descriptorType, Int)}:${resource.count}:${resource.stages}');
		entries.sort(Reflect.compare);
		return 'abi=${abi.version}|bindless=${abi.hasBindless ? 1 : 0}:${abi.bindlessImageCapacity}:${abi.bindlessSamplerCapacity}:${abi.bindlessBufferCapacity}|'
			+ '${abi.programLayout.pushConstantSize}|${entries.join(",")}';
	}

	public function dispose() {
		for (resource in layouts) {
			context.destroyPipelineLayout(resource.layout);
			for (index => setLayout in resource.descriptorSetLayouts)
				if (resource.ownedDescriptorSetLayouts[index]) context.destroyDescriptorSetLayout(setLayout);
		}
		layouts.clear();
	}
}
#end
