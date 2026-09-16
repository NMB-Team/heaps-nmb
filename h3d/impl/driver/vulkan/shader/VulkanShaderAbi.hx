package h3d.impl.driver.vulkan.shader;

#if (limen && gfx_vulkan)
import hxsl.Ast.BufferKind;
import hxsl.Ast.SizeDecl;
import hxsl.Ast.TVar;
import hxsl.Ast.Type;
import hxsl.Ast.VarKind;
import hxsl.RuntimeShader.AllocParam;
import hxsl.RuntimeShader.RuntimeShaderData;
import hxsl.VulkanGlslLayout;
import hxsl.VulkanGlslLayout.VulkanGlslBinding;
import hxsl.VulkanGlslLayout.VulkanGlslBindlessLayout;
import hxsl.VulkanGlslLayout.VulkanGlslConstantBlock;
import hxsl.VulkanGlslLayout.VulkanGlslConstantMember;
import limen.graphics.vulkan.device.DeviceLimits.VkPhysicalDeviceLimits;

enum abstract VulkanShaderStage(Int) from Int to Int {
	final Vertex = 0x00000001;
	final Fragment = 0x00000010;
	final Compute = 0x00000020;
}

enum abstract VulkanDescriptorType(Int) from Int to Int {
	final Sampler = 0;
	final CombinedImageSampler = 1;
	final SampledImage = 2;
	final StorageImage = 3;
	final UniformBuffer = 6;
	final StorageBuffer = 7;
}

enum abstract VulkanNumericType(Int) {
	final Float = 0;
	final SignedInteger = 1;
	final Boolean = 2;
}

enum abstract VulkanConstantFrequency(Int) {
	final Globals = 0;
	final Params = 1;
}

class VulkanShaderType {
	public final signature:String;
	public final numericType:VulkanNumericType;
	public final scalarWidth:Int;
	public final components:Int;
	public final columns:Int;

	public function new(signature:String, numericType:VulkanNumericType, scalarWidth:Int, components:Int, columns:Int) {
		this.signature = signature;
		this.numericType = numericType;
		this.scalarWidth = scalarWidth;
		this.components = components;
		this.columns = columns;
	}

	public static function fromHxsl(type:Type):VulkanShaderType {
		return switch (type) {
		case TInt, TBufferHandle: new VulkanShaderType(Std.string(type), SignedInteger, 32, 1, 1);
		case TTextureHandle: new VulkanShaderType("TextureHandle", SignedInteger, 32, 2, 1);
		case TBool: new VulkanShaderType("bool", Boolean, 32, 1, 1);
		case TFloat: new VulkanShaderType("float", Float, 32, 1, 1);
		case TVec(size, vectorType):
			final numericType = switch (vectorType) {
			case VFloat: Float;
			case VInt: SignedInteger;
			case VBool: Boolean;
			}
			new VulkanShaderType(Std.string(type), numericType, 32, size, 1);
		case TMat2: new VulkanShaderType("mat2", Float, 32, 2, 2);
		case TMat3: new VulkanShaderType("mat3", Float, 32, 3, 3);
		case TMat3x4: new VulkanShaderType("mat3x4", Float, 32, 4, 3);
		case TMat4: new VulkanShaderType("mat4", Float, 32, 4, 4);
		case TArray(element, _):
			final value = fromHxsl(element);
			new VulkanShaderType(Std.string(type), value.numericType, value.scalarWidth, value.components, value.columns);
		default: new VulkanShaderType(Std.string(type), Float, 0, 0, 0);
		}
	}
}

class VulkanShaderResource {
	public final logicalId:String;
	public final name:String;
	public final set:Int;
	public final binding:Int;
	public final stages:Int;
	public final descriptorType:VulkanDescriptorType;
	public final count:Int;
	public final allocationIds:Array<String>;

	public function new(logicalId:String, name:String, set:Int, binding:Int, stages:Int, descriptorType:VulkanDescriptorType, count:Int, allocationIds:Array<String>) {
		this.logicalId = logicalId;
		this.name = name;
		this.set = set;
		this.binding = binding;
		this.stages = stages;
		this.descriptorType = descriptorType;
		this.count = count;
		this.allocationIds = allocationIds.copy();
	}
}

class VulkanConstantMember {
	public final name:String;
	public final variableId:Int;
	public final type:VulkanShaderType;
	public final sourceOffset:Int;
	public final offset:Int;
	public final size:Int;
	public final arrayStride:Int;
	public final matrixStride:Int;
	public final arrayCount:Int;

	public function new(name:String, variableId:Int, type:VulkanShaderType, sourceOffset:Int, offset:Int, size:Int,
		arrayStride:Int, matrixStride:Int, arrayCount:Int)
	{
		this.name = name;
		this.variableId = variableId;
		this.type = type;
		this.sourceOffset = sourceOffset;
		this.offset = offset;
		this.size = size;
		this.arrayStride = arrayStride;
		this.matrixStride = matrixStride;
		this.arrayCount = arrayCount;
	}
}

class VulkanConstantBlock {
	public final name:String;
	public final set:Int;
	public final binding:Int;
	public final stage:VulkanShaderStage;
	public final frequency:VulkanConstantFrequency;
	public final sourceSize:Int;
	public final size:Int;
	public final members:Array<VulkanConstantMember>;

	public function new(name:String, set:Int, binding:Int, stage:VulkanShaderStage, frequency:VulkanConstantFrequency, sourceSize:Int, size:Int, members:Array<VulkanConstantMember>) {
		this.name = name;
		this.set = set;
		this.binding = binding;
		this.stage = stage;
		this.frequency = frequency;
		this.sourceSize = sourceSize;
		this.size = size;
		this.members = members.copy();
	}
}

class VulkanShaderInterfaceVariable {
	public final name:String;
	public final location:Int;
	public final type:VulkanShaderType;
	public final flat:Bool;

	public function new(name:String, location:Int, type:VulkanShaderType, flat:Bool = false) {
		this.name = name;
		this.location = location;
		this.type = type;
		this.flat = flat;
	}
}

class VulkanVertexShaderInterface {
	public final inputs:Array<VulkanShaderInterfaceVariable>;

	public function new(inputs:Array<VulkanShaderInterfaceVariable>) {
		this.inputs = inputs.copy();
	}
}

class VulkanFragmentOutputInterface {
	public final outputs:Array<VulkanShaderInterfaceVariable>;

	public function new(outputs:Array<VulkanShaderInterfaceVariable>) {
		this.outputs = outputs.copy();
	}
}

class VulkanProgramLayout {
	public final descriptors:Array<VulkanShaderResource>;
	public final constantBlocks:Array<VulkanConstantBlock>;
	public final pushConstantSize:Int;

	public function new(descriptors:Array<VulkanShaderResource>, constantBlocks:Array<VulkanConstantBlock>, pushConstantSize:Int) {
		this.descriptors = descriptors.copy();
		this.constantBlocks = constantBlocks.copy();
		this.pushConstantSize = pushConstantSize;
	}
}

private class Std140Layout {
	public final alignment:Int;
	public final size:Int;
	public final arrayStride:Int;
	public final matrixStride:Int;
	public final arrayCount:Int;

	public function new(alignment:Int, size:Int, arrayStride:Int = 0, matrixStride:Int = 0, arrayCount:Int = 0) {
		this.alignment = alignment;
		this.size = size;
		this.arrayStride = arrayStride;
		this.matrixStride = matrixStride;
		this.arrayCount = arrayCount;
	}
}

private class PendingResource {
	public final logicalId:String;
	public final name:String;
	public final set:Int;
	public final descriptorType:VulkanDescriptorType;
	public final count:Int;
	public final allocationIds:Array<String>;
	public var stages:Int;
	public final variables:Array<{stage:VulkanShaderStage, id:Int}> = [];

	public function new(logicalId:String, name:String, set:Int, descriptorType:VulkanDescriptorType, count:Int, allocationIds:Array<String>, stage:VulkanShaderStage, id:Int) {
		this.logicalId = logicalId;
		this.name = name;
		this.set = set;
		this.descriptorType = descriptorType;
		this.count = count;
		this.allocationIds = allocationIds.copy();
		this.stages = stage;
		variables.push({stage: stage, id: id});
	}
}

private typedef ResolvedResource = {
	var logicalId:String;
	var name:String;
	var allocationIds:Array<String>;
}

class VulkanShaderAbi {
	public static inline final VERSION = 1;
	public static inline final BINDLESS_VERSION = 2;
	public static inline final CAPABILITY_MODE = "vulkan13-descriptor-indexing-v1";
	public static inline final BINDLESS_SET = 3;
	public static inline final BINDLESS_IMAGE_BINDING = 0;
	public static inline final BINDLESS_SAMPLER_BINDING = 1;
	public static inline final BINDLESS_BUFFER_BINDING = 2;

	public final version:Int;
	public final resources:Array<VulkanShaderResource>;
	public final constantBlocks:Array<VulkanConstantBlock>;
	public final vertexInterface:VulkanVertexShaderInterface;
	public final fragmentOutputs:VulkanFragmentOutputInterface;
	public final vertexVaryings:Array<VulkanShaderInterfaceVariable>;
	public final fragmentVaryings:Array<VulkanShaderInterfaceVariable>;
	public final programLayout:VulkanProgramLayout;
	public final hasBindless:Bool;
	public final bindlessImageCapacity:Int;
	public final bindlessSamplerCapacity:Int;
	public final bindlessBufferCapacity:Int;
	final stageLayouts:Map<Int, VulkanGlslLayout> = new Map();

	public function new(shader:hxsl.RuntimeShader, bindlessImageCapacity = 0, bindlessSamplerCapacity = 0, bindlessBufferCapacity = 0) {
		hasBindless = shader.hasBindless();
		version = hasBindless ? BINDLESS_VERSION : VERSION;
		this.bindlessImageCapacity = bindlessImageCapacity;
		this.bindlessSamplerCapacity = bindlessSamplerCapacity;
		this.bindlessBufferCapacity = bindlessBufferCapacity;
		if (hasBindless && (bindlessImageCapacity <= 0 || bindlessSamplerCapacity <= 0 || bindlessBufferCapacity <= 0))
			throw "Vulkan bindless shader ABI requires positive image, sampler, and buffer capacities";
		final stages:Array<{stage:VulkanShaderStage, data:RuntimeShaderData}> = shader.mode == Compute
			? [{stage: Compute, data: shader.compute}]
			: [{stage: Vertex, data: shader.vertex}, {stage: Fragment, data: shader.fragment}];
		for (entry in stages) {
			final layout = new VulkanGlslLayout();
			if (entry.data.hasBindless)
				layout.bindless = new VulkanGlslBindlessLayout(BINDLESS_SET, BINDLESS_IMAGE_BINDING, BINDLESS_SAMPLER_BINDING,
					BINDLESS_BUFFER_BINDING, bindlessImageCapacity, bindlessSamplerCapacity, bindlessBufferCapacity);
			stageLayouts.set(entry.stage, layout);
		}

		if (shader.mode == Compute) {
			vertexInterface = new VulkanVertexShaderInterface([]);
			fragmentOutputs = new VulkanFragmentOutputInterface([]);
			vertexVaryings = [];
			fragmentVaryings = [];
		} else {
			vertexInterface = new VulkanVertexShaderInterface(assignInputs(shader.vertex));
			final varyingResult = assignVaryings(shader.vertex, shader.fragment);
			vertexVaryings = varyingResult.vertex;
			fragmentVaryings = varyingResult.fragment;
			fragmentOutputs = new VulkanFragmentOutputInterface(assignFragmentOutputs(shader.fragment));
		}

		constantBlocks = [];
		for (entry in stages) {
			addConstantBlock(entry.stage, entry.data, Global, constantBinding(entry.stage, true));
			addConstantBlock(entry.stage, entry.data, Param, constantBinding(entry.stage, false));
		}
		resources = assignResources(stages);
		programLayout = new VulkanProgramLayout(resources, constantBlocks, 0);
	}

	public function glslLayout(stage:VulkanShaderStage):VulkanGlslLayout {
		final layout = stageLayouts.get(stage);
		if (layout == null)
			throw 'Vulkan shader ABI has no layout for stage ${stageName(stage)}';
		return layout;
	}

	public function validateDeviceLimits(limits:VkPhysicalDeviceLimits) {
		var highestSet = -1;
		for (resource in resources)
			if (resource.set > highestSet)
				highestSet = resource.set;
		for (block in constantBlocks)
			if (block.set > highestSet)
				highestSet = block.set;
		if (hasBindless)
			highestSet = BINDLESS_SET;
		if (exceedsLimit(highestSet + 1, limits.maxBoundDescriptorSets))
			throw 'Shader ABI requires ${highestSet + 1} descriptor sets, device limit is ${limits.maxBoundDescriptorSets}';
		if (exceedsLimit(vertexInterface.inputs.length, limits.maxVertexInputAttributes))
			throw 'Vertex shader requires ${vertexInterface.inputs.length} inputs, device limit is ${limits.maxVertexInputAttributes}';
		if (exceedsLimit(fragmentOutputs.outputs.length, limits.maxFragmentOutputAttachments))
			throw 'Fragment shader requires ${fragmentOutputs.outputs.length} color outputs, device limit is ${limits.maxFragmentOutputAttachments}';
		final vertexOutputComponents = interfaceComponents(vertexVaryings);
		if (exceedsLimit(vertexOutputComponents, limits.maxVertexOutputComponents))
			throw 'Vertex shader requires $vertexOutputComponents varying components, device limit is ${limits.maxVertexOutputComponents}';
		final fragmentInputComponents = interfaceComponents(fragmentVaryings);
		if (exceedsLimit(fragmentInputComponents, limits.maxFragmentInputComponents))
			throw 'Fragment shader requires $fragmentInputComponents varying components, device limit is ${limits.maxFragmentInputComponents}';
		if (exceedsLimit(programLayout.pushConstantSize, limits.maxPushConstantsSize))
			throw 'Shader ABI requires ${programLayout.pushConstantSize} push-constant bytes, device limit is ${limits.maxPushConstantsSize}';
		var totalSampledImages = 0;
		var totalUniformBuffers = constantBlocks.length;
		var totalStorageBuffers = 0;
		var totalStorageImages = 0;
		for (resource in resources)
			switch (resource.descriptorType) {
			case CombinedImageSampler: totalSampledImages += resource.count;
			case UniformBuffer: totalUniformBuffers += resource.count;
			case StorageBuffer: totalStorageBuffers += resource.count;
			case StorageImage: totalStorageImages += resource.count;
			default:
			}
		checkProgramLimit("sampled images", totalSampledImages, limits.maxDescriptorSetSampledImages);
		checkProgramLimit("samplers", totalSampledImages, limits.maxDescriptorSetSamplers);
		checkProgramLimit("uniform buffers", totalUniformBuffers, limits.maxDescriptorSetUniformBuffers);
		checkProgramLimit("storage buffers", totalStorageBuffers, limits.maxDescriptorSetStorageBuffers);
		checkProgramLimit("storage images", totalStorageImages, limits.maxDescriptorSetStorageImages);

		for (stage in [Vertex, Fragment, Compute]) {
			var sampledImages = 0;
			var uniformBuffers = 0;
			var storageBuffers = 0;
			var storageImages = 0;
			for (resource in resources) {
				if ((resource.stages & stage) == 0)
					continue;
				switch (resource.descriptorType) {
				case CombinedImageSampler: sampledImages += resource.count;
				case UniformBuffer: uniformBuffers += resource.count;
				case StorageBuffer: storageBuffers += resource.count;
				case StorageImage: storageImages += resource.count;
				default:
				}
			}
			for (block in constantBlocks)
				if (block.stage == stage)
					uniformBuffers++;
			checkLimit(stage, "sampled images", sampledImages, limits.maxPerStageDescriptorSampledImages);
			checkLimit(stage, "samplers", sampledImages, limits.maxPerStageDescriptorSamplers);
			checkLimit(stage, "uniform buffers", uniformBuffers, limits.maxPerStageDescriptorUniformBuffers);
			checkLimit(stage, "storage buffers", storageBuffers, limits.maxPerStageDescriptorStorageBuffers);
			checkLimit(stage, "storage images", storageImages, limits.maxPerStageDescriptorStorageImages);
			checkLimit(stage, "total resources", sampledImages + uniformBuffers + storageBuffers + storageImages, limits.maxPerStageResources);
			if (stage == Fragment)
				checkLimit(stage, "combined output resources", fragmentOutputs.outputs.length + storageBuffers + storageImages,
					limits.maxFragmentCombinedOutputResources);
		}
	}

	function assignInputs(data:RuntimeShaderData):Array<VulkanShaderInterfaceVariable> {
		final result = [];
		final layout = stageLayouts.get(Vertex);
		for (variable in data.data.vars)
			if (variable.kind == Input) {
				final location = result.length;
				layout.locations.set(variable.id, location);
				result.push(new VulkanShaderInterfaceVariable(variable.name, location, VulkanShaderType.fromHxsl(variable.type)));
			}
		return result;
	}

	function assignVaryings(vertex:RuntimeShaderData, fragment:RuntimeShaderData):{vertex:Array<VulkanShaderInterfaceVariable>, fragment:Array<VulkanShaderInterfaceVariable>} {
		final vertexVariables:Map<String, TVar> = new Map();
		final fragmentVariables:Map<String, TVar> = new Map();
		for (variable in vertex.data.vars)
			if (variable.kind == Var)
				vertexVariables.set(variable.name, variable);
		for (variable in fragment.data.vars)
			if (variable.kind == Var)
				fragmentVariables.set(variable.name, variable);
		final names = [for (name in vertexVariables.keys()) name];
		names.sort(Reflect.compare);
		final vertexResult = [];
		final fragmentResult = [];
		for (name in names) {
			final producer = vertexVariables.get(name);
			final consumer = fragmentVariables.get(name);
			if (consumer == null)
				continue;
			if (Std.string(producer.type) != Std.string(consumer.type))
				throw 'HxSL varying "$name" type mismatch: vertex ${producer.type}, fragment ${consumer.type}';
			final producerFlat = hxsl.Ast.Tools.hasQualifier(producer, Flat);
			final consumerFlat = hxsl.Ast.Tools.hasQualifier(consumer, Flat);
			if (producerFlat != consumerFlat)
				throw 'HxSL varying "$name" interpolation mismatch between vertex and fragment stages';
			final location = vertexResult.length;
			stageLayouts.get(Vertex).locations.set(producer.id, location);
			stageLayouts.get(Fragment).locations.set(consumer.id, location);
			vertexResult.push(new VulkanShaderInterfaceVariable(name, location, VulkanShaderType.fromHxsl(producer.type), producerFlat));
			fragmentResult.push(new VulkanShaderInterfaceVariable(name, location, VulkanShaderType.fromHxsl(consumer.type), consumerFlat));
			fragmentVariables.remove(name);
		}
		for (name in fragmentVariables.keys())
			throw 'HxSL fragment varying "$name" has no vertex-stage producer';
		return {vertex: vertexResult, fragment: fragmentResult};
	}

	function assignFragmentOutputs(data:RuntimeShaderData):Array<VulkanShaderInterfaceVariable> {
		final result = [];
		final layout = stageLayouts.get(Fragment);
		for (variable in data.data.vars)
			if (variable.kind == Output) {
				final location = result.length;
				layout.locations.set(variable.id, location);
				result.push(new VulkanShaderInterfaceVariable(variable.name, location, VulkanShaderType.fromHxsl(variable.type)));
			}
		return result;
	}

	function addConstantBlock(stage:VulkanShaderStage, data:RuntimeShaderData, kind:VarKind, binding:Int) {
		final vectorCount = kind == Global ? data.globalsSize : data.paramsSize;
		final sourceSize = vectorCount * 16;
		if (sourceSize == 0)
			return;
		final storageVariable = findConstantStorage(data, kind, vectorCount);
		final members = [];
		if (kind == Global) {
			var allocation = data.globals;
			while (allocation != null) {
				addLogicalConstantMember(members, allocation.path, storageVariable.id, allocation.type, allocation.pos * 4, sourceSize);
				allocation = allocation.next;
			}
		} else {
			var allocation = data.params;
			while (allocation != null) {
				addLogicalConstantMember(members, allocation.name, storageVariable.id, allocation.type, allocation.pos * 4, sourceSize);
				allocation = allocation.next;
			}
		}
		final blockName = stageName(stage) + (kind == Global ? "Globals" : "Params");
		final frequency = kind == Global ? VulkanConstantFrequency.Globals : VulkanConstantFrequency.Params;
		final block = new VulkanConstantBlock(blockName, 0, binding, stage, frequency, sourceSize, sourceSize, members);
		constantBlocks.push(block);
		stageLayouts.get(stage).constantBlocks.push(new VulkanGlslConstantBlock(blockName, 0, binding,
			[new VulkanGlslConstantMember(storageVariable.id, 0)]));
	}

	static function findConstantStorage(data:RuntimeShaderData, kind:VarKind, vectorCount:Int):TVar {
		for (variable in data.data.vars)
			if (variable.kind == kind)
				switch (variable.type) {
				case TArray(TVec(4, VFloat), SConst(count)) if (count == vectorCount):
					return variable;
				default:
				}
		throw 'HxSL ${kind == Global ? "global" : "parameter"} constant storage is missing its packed vec4[$vectorCount] variable';
	}

	static function addLogicalConstantMember(members:Array<VulkanConstantMember>, name:String, variableId:Int, type:Type, offset:Int, blockSize:Int) {
		final layout = std140(type);
		if (offset + layout.size > blockSize)
			throw 'HxSL constant "$name" range [${offset}, ${offset + layout.size}) exceeds its $blockSize-byte block';
		members.push(new VulkanConstantMember(name, variableId, VulkanShaderType.fromHxsl(type), offset, offset,
			layout.size, layout.arrayStride, layout.matrixStride, layout.arrayCount));
	}

	function assignResources(stages:Array<{stage:VulkanShaderStage, data:RuntimeShaderData}>):Array<VulkanShaderResource> {
		final pending:Map<String, PendingResource> = new Map();
		for (entry in stages) {
			for (variable in entry.data.data.vars) {
				final descriptor = descriptor(variable.type);
				if (descriptor == null)
					continue;
				final resolved = resolveResource(entry.data, variable);
				final existing = pending.get(resolved.logicalId);
				if (existing == null) {
					pending.set(resolved.logicalId, new PendingResource(resolved.logicalId, resolved.name, descriptor.set, descriptor.type, descriptor.count, resolved.allocationIds, entry.stage, variable.id));
				} else {
					if (existing.set != descriptor.set || existing.descriptorType != descriptor.type || existing.count != descriptor.count)
						throw 'Vulkan shader ABI collision for "${resolved.logicalId}": incompatible descriptor declarations';
					existing.stages |= entry.stage;
					existing.variables.push({stage: entry.stage, id: variable.id});
				}
			}
		}
		final ordered = [for (resource in pending) resource];
		ordered.sort((left, right) -> left.set == right.set ? Reflect.compare(left.logicalId, right.logicalId) : left.set - right.set);
		final nextBinding:Map<Int, Int> = new Map();
		final result = [];
		for (resource in ordered) {
			final binding = nextBinding.exists(resource.set) ? nextBinding.get(resource.set) : 0;
			nextBinding.set(resource.set, binding + 1);
			result.push(new VulkanShaderResource(resource.logicalId, resource.name, resource.set, binding, resource.stages, resource.descriptorType, resource.count, resource.allocationIds));
			for (variable in resource.variables)
				stageLayouts.get(variable.stage).bindings.set(variable.id, new VulkanGlslBinding(resource.set, binding));
		}
		return result;
	}

	static function descriptor(type:Type):Null<{set:Int, type:VulkanDescriptorType, count:Int}> {
		return switch (type) {
		case TSampler(_, _): {set: 1, type: CombinedImageSampler, count: 1};
		case TArray(TSampler(_, _), SConst(count)): {set: 1, type: CombinedImageSampler, count: count};
		case TRWTexture(_, _, _): {set: 2, type: StorageImage, count: 1};
		case TArray(TRWTexture(_, _, _), SConst(count)): {set: 2, type: StorageImage, count: count};
		case TBuffer(_, _, Uniform | Partial): {set: 2, type: UniformBuffer, count: 1};
		case TBuffer(_, _, Storage | StoragePartial | RW | RWPartial): {set: 2, type: StorageBuffer, count: 1};
		case TTextureHandle, TBufferHandle: null;
		default: null;
		}
	}

	static function findResourceAllocation(data:RuntimeShaderData, name:String):AllocParam {
		var allocation = data.textures;
		while (allocation != null) {
			if (allocation.name == name)
				return allocation;
			allocation = allocation.next;
		}
		allocation = data.buffers;
		while (allocation != null) {
			if (allocation.name == name)
				return allocation;
			allocation = allocation.next;
		}
		return null;
	}

	static function resolveResource(data:RuntimeShaderData, variable:TVar):ResolvedResource {
		final textureElement = switch (variable.type) {
		case TArray(element = TSampler(_, _) | TRWTexture(_, _, _), SConst(_)): element;
		case element = TSampler(_, _) | TRWTexture(_, _, _): element;
		default: null;
		}
		if (textureElement != null) {
			final allocations = [];
			var allocation = data.textures;
			while (allocation != null) {
				if (Std.string(allocation.type) == Std.string(textureElement))
					allocations.push(allocation);
				allocation = allocation.next;
			}
			final count = switch (variable.type) {
			case TArray(_, SConst(value)): value;
			default: 1;
			}
			if (allocations.length != count)
				throw 'HxSL resource storage ${variable.name} contains $count entries, but ${allocations.length} logical resources were resolved';
			final allocationIds = [for (value in allocations) allocationId(value)];
			return {
				logicalId: allocationIds.join("+"),
				name: allocations.length == 1 ? allocations[0].name : variable.name,
				allocationIds: allocationIds,
			};
		}
		final allocation = findResourceAllocation(data, variable.name);
		return allocation == null
			? {logicalId: '${variable.kind}:${variable.name}', name: variable.name, allocationIds: []}
			: {logicalId: allocationId(allocation), name: allocation.name, allocationIds: [allocationId(allocation)]};
	}

	public static function allocationId(allocation:AllocParam):String {
		return allocation.perObjectGlobal == null
			? 'param:${allocation.instance}:${allocation.index}:${allocation.name}'
			: 'global:${allocation.perObjectGlobal.path}';
	}

	static function std140(type:Type):Std140Layout {
		return switch (type) {
		case TInt, TBool, TFloat, TBufferHandle: new Std140Layout(4, 4);
		case TTextureHandle: new Std140Layout(8, 8);
		case TVec(2, _): new Std140Layout(8, 8);
		case TVec(3, _): new Std140Layout(16, 12);
		case TVec(4, _): new Std140Layout(16, 16);
		case TMat2: new Std140Layout(16, 32, 0, 16);
		case TMat3: new Std140Layout(16, 48, 0, 16);
		case TMat3x4: new Std140Layout(16, 48, 0, 16);
		case TMat4: new Std140Layout(16, 64, 0, 16);
		case TArray(element, SConst(count)):
			final elementLayout = std140(element);
			final stride = align(elementLayout.size, 16);
			new Std140Layout(align(elementLayout.alignment, 16), stride * count, stride, elementLayout.matrixStride, count);
		case TStruct(fields):
			var size = 0;
			var maxAlignment = 16;
			for (field in fields) {
				final fieldLayout = std140(field.type);
				size = align(size, fieldLayout.alignment) + fieldLayout.size;
				if (fieldLayout.alignment > maxAlignment)
					maxAlignment = fieldLayout.alignment;
			}
			final alignment = align(maxAlignment, 16);
			new Std140Layout(alignment, align(size, alignment));
		default:
			throw 'HxSL constant type $type is not supported by Vulkan std140 ABI version $VERSION';
		}
	}

	static inline function align(value:Int, alignment:Int):Int {
		return Std.int((value + alignment - 1) / alignment) * alignment;
	}

	static function constantBinding(stage:VulkanShaderStage, globals:Bool):Int {
		final base = switch (stage) {
		case Vertex: 0;
		case Fragment: 2;
		case Compute: 4;
		default: throw 'Unsupported Vulkan shader stage $stage';
		}
		return base + (globals ? 0 : 1);
	}

	public static function stageName(stage:VulkanShaderStage):String {
		return switch (stage) {
		case Vertex: "Vertex";
		case Fragment: "Fragment";
		case Compute: "Compute";
		default: 'Unknown($stage)';
		}
	}

	static function checkLimit(stage:VulkanShaderStage, label:String, value:Int, limit:Int) {
		if (exceedsLimit(value, limit))
			throw '${stageName(stage)} shader requires $value $label, device limit is $limit';
	}

	static function checkProgramLimit(label:String, value:Int, limit:Int) {
		if (exceedsLimit(value, limit))
			throw 'Shader ABI requires $value total $label, device limit is $limit';
	}

	static inline function exceedsLimit(value:Int, limit:Int):Bool {
		return limit >= 0 && value > limit;
	}

	static function interfaceComponents(variables:Array<VulkanShaderInterfaceVariable>):Int {
		var count = 0;
		for (variable in variables)
			count += variable.type.components * variable.type.columns;
		return count;
	}
}
#end
