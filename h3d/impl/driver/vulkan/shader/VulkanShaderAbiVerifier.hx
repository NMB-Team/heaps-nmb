package h3d.impl.driver.vulkan.shader;

#if (limen && gfx_vulkan)
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanConstantBlock;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanShaderAbi;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanShaderInterfaceVariable;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanShaderResource;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanShaderStage;
import limen.graphics.vulkan.shader.SpirvReflection;
import limen.graphics.vulkan.shader.SpirvReflection.SpirvBlockVariable;
import limen.graphics.vulkan.shader.SpirvReflection.SpirvDescriptorBinding;
import limen.graphics.vulkan.shader.SpirvReflection.SpirvInterfaceVariable;

class VulkanShaderAbiVerifier {
	static inline final FLAT_DECORATION = 0x40;

	public static function verifyStage(abi:VulkanShaderAbi, stage:VulkanShaderStage, reflection:SpirvReflection) {
		if (reflection.shaderStage != stage)
			fail(stage, 'reflected stage mask ${reflection.shaderStage} does not match expected $stage');

		final reflectedBindings:Map<String, SpirvDescriptorBinding> = new Map();
		for (set in reflection.descriptorSets)
			for (binding in set.bindings) {
				final key = descriptorKey(set.set, binding.binding);
				final existing = reflectedBindings.get(key);
				if (existing != null) {
					if (!abi.hasBindless || set.set != VulkanShaderAbi.BINDLESS_SET
						|| existing.descriptorType != binding.descriptorType || existing.count != binding.count)
						fail(stage, 'duplicate reflected descriptor at $key');
					continue;
				}
				reflectedBindings.set(key, binding);
			}

		var expectedBindingCount = 0;
		for (block in abi.constantBlocks)
			if (block.stage == stage) {
				expectedBindingCount++;
				verifyConstantBlock(stage, block, requireBinding(stage, reflectedBindings, block.set, block.binding));
			}
		for (resource in abi.resources)
			if ((resource.stages & stage) != 0) {
				expectedBindingCount++;
				verifyResource(stage, resource, requireBinding(stage, reflectedBindings, resource.set, resource.binding));
			}
		if (abi.hasBindless)
			for (binding in reflectedBindings)
				if (binding.set == VulkanShaderAbi.BINDLESS_SET) {
					verifyBindlessResource(stage, abi, binding);
					expectedBindingCount++;
				}
		if (reflectedBindings.keys().hasNext() && countBindings(reflectedBindings) != expectedBindingCount)
			fail(stage, 'reflected ${countBindings(reflectedBindings)} descriptors but ABI expects $expectedBindingCount');
		if (reflection.pushConstantBlocks.length != 0)
			fail(stage, 'reflected ${reflection.pushConstantBlocks.length} unexpected push-constant blocks');

		switch (stage) {
		case Vertex:
			verifyInterface(stage, "vertex input", abi.vertexInterface.inputs, reflection.inputs);
			verifyInterface(stage, "vertex varying", abi.vertexVaryings, reflection.outputs);
		case Fragment:
			verifyInterface(stage, "fragment varying", abi.fragmentVaryings, reflection.inputs);
			verifyInterface(stage, "fragment output", abi.fragmentOutputs.outputs, reflection.outputs);
		case Compute:
			verifyInterface(stage, "compute input", [], reflection.inputs);
			verifyInterface(stage, "compute output", [], reflection.outputs);
		default:
			fail(stage, "unsupported stage");
		}
	}

	static function verifyBindlessResource(stage:VulkanShaderStage, abi:VulkanShaderAbi, binding:SpirvDescriptorBinding) {
		final expected = switch (binding.binding) {
		case VulkanShaderAbi.BINDLESS_IMAGE_BINDING: {type: 2, count: abi.bindlessImageCapacity, label: "sampled image"};
		case VulkanShaderAbi.BINDLESS_SAMPLER_BINDING: {type: 0, count: abi.bindlessSamplerCapacity, label: "sampler"};
		case VulkanShaderAbi.BINDLESS_BUFFER_BINDING: {type: 7, count: abi.bindlessBufferCapacity, label: "storage buffer"};
		default: fail(stage, 'unexpected bindless descriptor binding ${binding.binding}');
		}
		if (binding.descriptorType != expected.type)
			fail(stage, 'bindless ${expected.label} binding has type ${binding.descriptorType}, expected ${expected.type}');
		if (binding.count != expected.count)
			fail(stage, 'bindless ${expected.label} binding has count ${binding.count}, expected ${expected.count}');
	}

	public static function verifyGraphicsLink(vertex:SpirvReflection, fragment:SpirvReflection) {
		final producers = userVariables(vertex.outputs);
		final consumers = userVariables(fragment.inputs);
		for (location => consumer in consumers) {
			final producer = producers.get(location);
			if (producer == null)
				throw 'Vulkan shader ABI failure: fragment input location $location (${consumer.name}) has no vertex producer';
			if (!sameType(producer, consumer))
				throw 'Vulkan shader ABI failure: varying location $location type mismatch between vertex ${producer.name} and fragment ${consumer.name}';
			if (((producer.decorationFlags ^ consumer.decorationFlags) & FLAT_DECORATION) != 0)
				throw 'Vulkan shader ABI failure: varying location $location interpolation qualifier mismatch';
		}
	}

	static function verifyResource(stage:VulkanShaderStage, expected:VulkanShaderResource, actual:SpirvDescriptorBinding) {
		if (actual.descriptorType != expected.descriptorType)
			fail(stage, 'descriptor ${expected.logicalId} at (${expected.set}, ${expected.binding}) has type ${actual.descriptorType}, expected ${expected.descriptorType}');
		if (actual.count != expected.count)
			fail(stage, 'descriptor ${expected.logicalId} at (${expected.set}, ${expected.binding}) has count ${actual.count}, expected ${expected.count}');
	}

	static function verifyConstantBlock(stage:VulkanShaderStage, expected:VulkanConstantBlock, actual:SpirvDescriptorBinding) {
		if (actual.descriptorType != 6)
			fail(stage, 'constant block ${expected.name} is descriptor type ${actual.descriptorType}, expected uniform buffer');
		if (actual.count != 1)
			fail(stage, 'constant block ${expected.name} has descriptor count ${actual.count}, expected 1');
		if (actual.block.size != expected.size)
			fail(stage, 'constant block ${expected.name} size is ${actual.block.size}, CPU ABI expects ${expected.size}');
		if (actual.block.members.length != 1)
			fail(stage, 'constant block ${expected.name} must reflect exactly one canonical packed vec4 array');
		final storage:SpirvBlockVariable = actual.block.members[0];
		if (storage.offset != 0)
			fail(stage, 'constant block ${expected.name} packed storage starts at ${storage.offset}, expected 0');
		if (storage.numeric.arrayStride != 16)
			fail(stage, 'constant block ${expected.name} packed vec4 stride is ${storage.numeric.arrayStride}, expected 16');
		for (member in expected.members) {
			if (member.offset != member.sourceOffset)
				fail(stage, 'constant ${expected.name}.${member.name} CPU offset ${member.sourceOffset} does not match ABI offset ${member.offset}');
			if (member.offset < 0 || member.offset + member.size > expected.size)
				fail(stage, 'constant ${expected.name}.${member.name} exceeds its ${expected.size}-byte block');
		}
	}

	static function verifyInterface(stage:VulkanShaderStage, label:String, expected:Array<VulkanShaderInterfaceVariable>, reflected:Array<SpirvInterfaceVariable>) {
		final actual = userVariables(reflected);
		if (countInterface(actual) != expected.length)
			fail(stage, '$label count is ${countInterface(actual)}, ABI expects ${expected.length}');
		for (variable in expected) {
			final reflectedVariable = actual.get(variable.location);
			if (reflectedVariable == null)
				fail(stage, '$label ${variable.name} is missing at location ${variable.location}');
			final components = reflectedVariable.numeric.vectorComponents == 0 ? 1 : reflectedVariable.numeric.vectorComponents;
			if (reflectedVariable.numeric.scalarWidth != variable.type.scalarWidth || components != variable.type.components)
				fail(stage, '$label ${variable.name} type mismatch at location ${variable.location}');
			final flat = (reflectedVariable.decorationFlags & FLAT_DECORATION) != 0;
			if (flat != variable.flat)
				fail(stage, '$label ${variable.name} interpolation qualifier mismatch at location ${variable.location}');
		}
	}

	static function requireBinding(stage:VulkanShaderStage, bindings:Map<String, SpirvDescriptorBinding>, set:Int, binding:Int):SpirvDescriptorBinding {
		final result = bindings.get(descriptorKey(set, binding));
		if (result == null)
			fail(stage, 'missing reflected descriptor at set $set binding $binding');
		return result;
	}

	static function userVariables(values:Array<SpirvInterfaceVariable>):Map<Int, SpirvInterfaceVariable> {
		final result:Map<Int, SpirvInterfaceVariable> = new Map();
		for (value in values)
			if (value.builtIn < 0 && value.location >= 0) {
				if (result.exists(value.location))
					throw 'Vulkan shader ABI failure: interface location ${value.location} is declared more than once';
				result.set(value.location, value);
			}
		return result;
	}

	static function sameType(left:SpirvInterfaceVariable, right:SpirvInterfaceVariable):Bool {
		return left.numeric.scalarWidth == right.numeric.scalarWidth
			&& left.numeric.signedness == right.numeric.signedness
			&& left.numeric.vectorComponents == right.numeric.vectorComponents
			&& left.numeric.matrixColumns == right.numeric.matrixColumns
			&& left.numeric.matrixRows == right.numeric.matrixRows
			&& left.numeric.arrayDimensions.join(",") == right.numeric.arrayDimensions.join(",");
	}

	static inline function descriptorKey(set:Int, binding:Int):String {
		return '$set:$binding';
	}

	static function countBindings(values:Map<String, SpirvDescriptorBinding>):Int {
		var count = 0;
		for (_ in values)
			count++;
		return count;
	}

	static function countInterface(values:Map<Int, SpirvInterfaceVariable>):Int {
		var count = 0;
		for (_ in values)
			count++;
		return count;
	}

	static function fail(stage:VulkanShaderStage, message:String):Dynamic {
		throw 'Vulkan shader ABI failure in ${VulkanShaderAbi.stageName(stage)} stage: $message';
	}
}
#end
