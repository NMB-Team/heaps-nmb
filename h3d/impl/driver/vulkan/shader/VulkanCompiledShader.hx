package h3d.impl.driver.vulkan.shader;

#if (limen && gfx_vulkan)
import limen.graphics.vulkan.VulkanCore.ArrayStruct;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanFragmentOutputInterface;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanProgramLayout;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanConstantBlock;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanShaderResource;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanDescriptorType;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanShaderAbi;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanVertexShaderInterface;
import h3d.impl.driver.vulkan.resource.VulkanBuffer;
import h3d.impl.driver.vulkan.resource.VulkanImage.VulkanTexture;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSetLayout;
import limen.graphics.vulkan.memory.Memory.VkBuffer;
import limen.graphics.vulkan.memory.Memory.VkImageView;
import limen.graphics.vulkan.sampler.Samplers.VkSampler;
import limen.graphics.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineLayout;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineShaderStage;

class VulkanComputeMetadata {
	public final localSizeX:Int;
	public final localSizeY:Int;
	public final localSizeZ:Int;
	public final sharedMemoryBytes:Int;

	public function new(localSizeX:Int, localSizeY:Int, localSizeZ:Int, sharedMemoryBytes:Int) {
		this.localSizeX = localSizeX;
		this.localSizeY = localSizeY;
		this.localSizeZ = localSizeZ;
		this.sharedMemoryBytes = sharedMemoryBytes;
	}
}

class VulkanDescriptorSetMetadata {
	public final id:Int;
	public final blocks:Array<VulkanConstantBlock> = [];
	public final blockIds:Array<Int> = [];
	public final resources:Array<VulkanShaderResource> = [];
	public final bindless:Bool;
	public var descriptorCount = 0;
	public var revision = 0;
	public final textureStates:Map<String, Array<{image:VulkanTexture, view:VkImageView, sampler:VkSampler}>> = new Map();

	public function new(id:Int, bindless:Bool) {
		this.id = id;
		this.bindless = bindless;
	}
}

class VulkanCompiledShader {
	static var nextDescriptorId = 1;
	static var nextPipelineId = 1;
	public final shader:hxsl.RuntimeShader;
	public final cacheKey:String;
	public final pipelineId:Int;
	public final abiVersion:Int;
	public final abi:VulkanShaderAbi;
	public final programLayout:VulkanProgramLayout;
	public final vertexInterface:VulkanVertexShaderInterface;
	public final fragmentOutputs:VulkanFragmentOutputInterface;
	public final vertex:Null<VulkanShaderStageData>;
	public final fragment:Null<VulkanShaderStageData>;
	public final compute:Null<VulkanShaderStageData>;
	public final computeMetadata:Null<VulkanComputeMetadata>;
	public final stages:ArrayStruct<VkPipelineShaderStage>;
	public final descriptorSetLayouts:Array<VkDescriptorSetLayout>;
	public final descriptorSets:Array<VulkanDescriptorSetMetadata>;
	public final constantBlockIds:Map<VulkanConstantBlock, Int>;
	public final bufferDescriptorSets:Map<String, Array<VulkanDescriptorSetMetadata>> = new Map();
	public final descriptorBuffers:Map<String, {buffer:VulkanBuffer, handle:VkBuffer, range:haxe.Int64}> = new Map();
	public final layout:VkPipelineLayout;
	public final pipelineLayoutIdentity:String;
	var disposed = false;

	public function new(shader:hxsl.RuntimeShader, cacheKey:String, abi:VulkanShaderAbi, vertex:Null<VulkanShaderStageData>,
		fragment:Null<VulkanShaderStageData>, compute:Null<VulkanShaderStageData>, stages:ArrayStruct<VkPipelineShaderStage>,
		descriptorSetLayouts:Array<VkDescriptorSetLayout>, layout:VkPipelineLayout, pipelineLayoutIdentity:String)
	{
		this.shader = shader;
		this.cacheKey = cacheKey;
		this.pipelineId = nextPipelineId++;
		this.abiVersion = abi.version;
		this.abi = abi;
		this.programLayout = abi.programLayout;
		this.vertexInterface = abi.vertexInterface;
		this.fragmentOutputs = abi.fragmentOutputs;
		this.vertex = vertex;
		this.fragment = fragment;
		this.compute = compute;
		if (compute == null)
			computeMetadata = null;
		else {
			final localSize = compute.source.reflection.localSize;
			var sharedMemoryBytes = 0;
			for (variable in shader.compute.data.vars)
				if (variable.kind == hxsl.Ast.VarKind.Local && hxsl.Ast.Tools.hasQualifier(variable, hxsl.Ast.VarQualifier.Shared))
					sharedMemoryBytes += hxsl.Ast.Tools.size(variable.type) * 4;
			computeMetadata = new VulkanComputeMetadata(localSize.x, localSize.y, localSize.z, sharedMemoryBytes);
		}
		this.stages = stages;
		this.descriptorSetLayouts = descriptorSetLayouts.copy();
		constantBlockIds = new Map();
		descriptorSets = [for (index in 0...descriptorSetLayouts.length)
			new VulkanDescriptorSetMetadata(nextDescriptorId++, abi.hasBindless && index == VulkanShaderAbi.BINDLESS_SET)];
		for (block in programLayout.constantBlocks) {
			constantBlockIds.set(block, nextDescriptorId++);
			descriptorSets[block.set].blocks.push(block);
		}
		for (resource in programLayout.descriptors) {
			final set = descriptorSets[resource.set];
			set.resources.push(resource);
			set.descriptorCount += resource.count;
			if (resource.descriptorType == VulkanDescriptorType.UniformBuffer || resource.descriptorType == VulkanDescriptorType.StorageBuffer)
				for (allocationId in resource.allocationIds) {
					var sets = bufferDescriptorSets.get(allocationId);
					if (sets == null) {
						sets = [];
						bufferDescriptorSets.set(allocationId, sets);
					}
					if (!sets.contains(set)) sets.push(set);
				}
		}
		for (set in descriptorSets) {
			set.blocks.sort((left, right) -> left.binding - right.binding);
			for (block in set.blocks) set.blockIds.push(constantBlockIds.get(block));
			set.resources.sort((left, right) -> left.binding - right.binding);
			set.descriptorCount += set.blocks.length;
		}
		this.layout = layout;
		this.pipelineLayoutIdentity = pipelineLayoutIdentity;
	}

	public function dispose(_context:VkContext) {
		if (disposed)
			return;
		disposed = true;
		if (vertex != null)
			vertex.dispose();
		if (fragment != null)
			fragment.dispose();
		if (compute != null)
			compute.dispose();
	}
}
#end
