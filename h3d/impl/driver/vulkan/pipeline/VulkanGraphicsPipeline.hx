package h3d.impl.driver.vulkan.pipeline;

#if (limen && gfx_vulkan)
import h3d.impl.driver.vulkan.shader.VulkanCompiledShader;
import limen.graphics.vulkan.Runtime;
import limen.graphics.vulkan.VulkanCore.IntArray;
import limen.graphics.vulkan.format.Formats.VkFormat;
import limen.graphics.vulkan.internal.VulkanBindings;
import limen.graphics.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.vulkan.pipeline.Pipeline.VkBlendFactor;
import limen.graphics.vulkan.pipeline.Pipeline.VkBlendOp;
import limen.graphics.vulkan.pipeline.Pipeline.VkDynamicState;
import limen.graphics.vulkan.pipeline.Pipeline.VkGraphicsPipeline;
import limen.graphics.vulkan.pipeline.Pipeline.VkGraphicsPipelineCreateInfo;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineColorBlend;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineColorBlendAttachmentState;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineDepthStencil;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineDynamic;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineInputAssembly;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineMultisample;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineRasterization;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineRenderingCreateInfo;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineVertexInput;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineViewport;
import limen.graphics.vulkan.pipeline.Pipeline.VkPolygonMode;
import limen.graphics.vulkan.pipeline.Pipeline.VkCompareOp;
import limen.graphics.vulkan.pipeline.Pipeline.VkStencilOp;
import limen.graphics.vulkan.pipeline.Pipeline.VkVertexInputAttributeDescription;
import limen.graphics.vulkan.pipeline.Pipeline.VkVertexInputBindingDescription;

class VulkanVertexBinding {
	public final binding:Int;
	public final stride:Int;

	public function new(binding:Int, stride:Int) {
		this.binding = binding;
		this.stride = stride;
	}
}

class VulkanVertexAttribute {
	public final location:Int;
	public final binding:Int;
	public final format:VkFormat;
	public final offset:Int;

	public function new(location:Int, binding:Int, format:VkFormat, offset:Int) {
		this.location = location;
		this.binding = binding;
		this.format = format;
		this.offset = offset;
	}
}

class VulkanVertexLayout {
	public final bindings:Array<VulkanVertexBinding>;
	public final attributes:Array<VulkanVertexAttribute>;
	public final hash:Int;

	public function new(bindings:Array<VulkanVertexBinding>, attributes:Array<VulkanVertexAttribute>) {
		this.bindings = bindings.copy();
		this.attributes = attributes.copy();
		var value = 0x811C9DC5;
		value = (value ^ bindings.length) * 0x01000193;
		for (binding in bindings) {
			value = (value ^ binding.binding) * 0x01000193;
			value = (value ^ binding.stride) * 0x01000193;
		}
		value = (value ^ attributes.length) * 0x01000193;
		for (attribute in attributes) {
			value = (value ^ attribute.location) * 0x01000193;
			value = (value ^ attribute.binding) * 0x01000193;
			value = (value ^ (cast attribute.format : Int)) * 0x01000193;
			value = (value ^ attribute.offset) * 0x01000193;
		}
		hash = value;
	}

	public function equals(other:VulkanVertexLayout):Bool {
		if (hash != other.hash || bindings.length != other.bindings.length || attributes.length != other.attributes.length)
			return false;
		for (index in 0...bindings.length)
			if (bindings[index].binding != other.bindings[index].binding || bindings[index].stride != other.bindings[index].stride)
				return false;
		for (index in 0...attributes.length) {
			final left = attributes[index];
			final right = other.attributes[index];
			if (left.location != right.location || left.binding != right.binding || left.format != right.format || left.offset != right.offset)
				return false;
		}
		return true;
	}
}

class VulkanBlendState {
	public var enabled:Bool;
	public var srcColor:VkBlendFactor;
	public var dstColor:VkBlendFactor;
	public var colorOp:VkBlendOp;
	public var srcAlpha:VkBlendFactor;
	public var dstAlpha:VkBlendFactor;
	public var alphaOp:VkBlendOp;
	public var colorWriteMask:Int;

	public function new(enabled:Bool, srcColor:VkBlendFactor, dstColor:VkBlendFactor, colorOp:VkBlendOp,
		srcAlpha:VkBlendFactor, dstAlpha:VkBlendFactor, alphaOp:VkBlendOp, colorWriteMask:Int)
	{
		update(enabled, srcColor, dstColor, colorOp, srcAlpha, dstAlpha, alphaOp, colorWriteMask);
	}

	public function update(enabled:Bool, srcColor:VkBlendFactor, dstColor:VkBlendFactor, colorOp:VkBlendOp,
		srcAlpha:VkBlendFactor, dstAlpha:VkBlendFactor, alphaOp:VkBlendOp, colorWriteMask:Int) {
		this.enabled = enabled;
		this.srcColor = srcColor;
		this.dstColor = dstColor;
		this.colorOp = colorOp;
		this.srcAlpha = srcAlpha;
		this.dstAlpha = dstAlpha;
		this.alphaOp = alphaOp;
		this.colorWriteMask = colorWriteMask;
	}
}

class VulkanStencilFaceState {
	public var fail:VkStencilOp;
	public var pass:VkStencilOp;
	public var depthFail:VkStencilOp;
	public var compare:VkCompareOp;

	public function new(fail:VkStencilOp, pass:VkStencilOp, depthFail:VkStencilOp, compare:VkCompareOp) {
		update(fail, pass, depthFail, compare);
	}

	public function update(fail:VkStencilOp, pass:VkStencilOp, depthFail:VkStencilOp, compare:VkCompareOp) {
		this.fail = fail;
		this.pass = pass;
		this.depthFail = depthFail;
		this.compare = compare;
	}
}

class VulkanStencilState {
	public var enabled:Bool;
	public var front:VulkanStencilFaceState;
	public var back:VulkanStencilFaceState;
	public var readMask:Int;
	public var writeMask:Int;
	public var reference:Int;

	public function new(enabled:Bool, front:VulkanStencilFaceState, back:VulkanStencilFaceState, readMask:Int, writeMask:Int, reference:Int) {
		update(enabled, front, back, readMask, writeMask, reference);
	}

	public function update(enabled:Bool, front:VulkanStencilFaceState, back:VulkanStencilFaceState, readMask:Int, writeMask:Int, reference:Int) {
		this.enabled = enabled;
		this.front = front;
		this.back = back;
		this.readMask = readMask;
		this.writeMask = writeMask;
		this.reference = reference;
	}
}

class VulkanGraphicsPipelineDesc {
	public var program(default, null):VulkanCompiledShader;
	public var vertexLayout(default, null):VulkanVertexLayout;
	public var colorFormats(default, null):Array<VkFormat>;
	public var depthFormat(default, null):VkFormat;
	public var stencilFormat(default, null):VkFormat;
	public var samples(default, null):Int;
	public var blend(default, null):VulkanBlendState;
	public var colorMasks(default, null):Array<Int>;
	public var stencil(default, null):VulkanStencilState;
	public var depthClamp(default, null):Bool;
	public var wireframe(default, null):Bool;
	var cachedHash:Int;

	public function new() {
	}

	static inline function mix(hash:Int, value:Int):Int {
		return (hash ^ value) * 0x01000193;
	}

	public function update(program:VulkanCompiledShader, vertexLayout:VulkanVertexLayout, colorFormats:Array<VkFormat>,
		depthFormat:VkFormat, stencilFormat:VkFormat, samples:Int, blend:VulkanBlendState, colorMasks:Array<Int>, stencil:VulkanStencilState,
		depthClamp:Bool, wireframe:Bool) {
		this.program = program;
		this.vertexLayout = vertexLayout;
		this.colorFormats = colorFormats;
		this.depthFormat = depthFormat;
		this.stencilFormat = stencilFormat;
		this.samples = samples;
		this.blend = blend;
		this.colorMasks = colorMasks;
		this.stencil = stencil;
		this.depthClamp = depthClamp;
		this.wireframe = wireframe;
		var value = mix(0x811C9DC5, program.pipelineId);
		value = mix(value, vertexLayout.hash);
		value = mix(value, colorFormats.length);
		for (index in 0...colorFormats.length)
			value = mix(value, cast colorFormats[index]);
		value = mix(value, cast depthFormat);
		value = mix(value, cast stencilFormat);
		value = mix(value, samples);
		value = mix(value, blend.enabled ? 1 : 0);
		value = mix(value, cast blend.srcColor);
		value = mix(value, cast blend.dstColor);
		value = mix(value, cast blend.colorOp);
		value = mix(value, cast blend.srcAlpha);
		value = mix(value, cast blend.dstAlpha);
		value = mix(value, cast blend.alphaOp);
		value = mix(value, blend.colorWriteMask);
		value = mix(value, colorMasks.length);
		for (index in 0...colorMasks.length)
			value = mix(value, colorMasks[index]);
		value = mix(value, stencil.enabled ? 1 : 0);
		if (stencil.enabled) {
			value = mix(value, cast stencil.front.fail);
			value = mix(value, cast stencil.front.pass);
			value = mix(value, cast stencil.front.depthFail);
			value = mix(value, cast stencil.front.compare);
			value = mix(value, cast stencil.back.fail);
			value = mix(value, cast stencil.back.pass);
			value = mix(value, cast stencil.back.depthFail);
			value = mix(value, cast stencil.back.compare);
			value = mix(value, stencil.readMask);
			value = mix(value, stencil.writeMask);
			value = mix(value, stencil.reference);
		}
		value = mix(value, depthClamp ? 1 : 0);
		cachedHash = mix(value, wireframe ? 1 : 0);
	}

	public inline function hash():Int {
		return cachedHash;
	}

	public function equals(other:VulkanGraphicsPipelineDesc):Bool {
		if (cachedHash != other.cachedHash || program.pipelineId != other.program.pipelineId || !vertexLayout.equals(other.vertexLayout)
			|| colorFormats.length != other.colorFormats.length || depthFormat != other.depthFormat || stencilFormat != other.stencilFormat
			|| samples != other.samples || colorMasks.length != other.colorMasks.length || depthClamp != other.depthClamp || wireframe != other.wireframe)
			return false;
		for (index in 0...colorFormats.length)
			if (colorFormats[index] != other.colorFormats[index])
				return false;
		for (index in 0...colorMasks.length)
			if (colorMasks[index] != other.colorMasks[index])
				return false;
		final leftBlend = blend;
		final rightBlend = other.blend;
		if (leftBlend.enabled != rightBlend.enabled || leftBlend.srcColor != rightBlend.srcColor || leftBlend.dstColor != rightBlend.dstColor
			|| leftBlend.colorOp != rightBlend.colorOp || leftBlend.srcAlpha != rightBlend.srcAlpha || leftBlend.dstAlpha != rightBlend.dstAlpha
			|| leftBlend.alphaOp != rightBlend.alphaOp || leftBlend.colorWriteMask != rightBlend.colorWriteMask)
			return false;
		if (stencil.enabled != other.stencil.enabled)
			return false;
		if (!stencil.enabled)
			return true;
		final leftFront = stencil.front;
		final rightFront = other.stencil.front;
		final leftBack = stencil.back;
		final rightBack = other.stencil.back;
		return leftFront.fail == rightFront.fail && leftFront.pass == rightFront.pass && leftFront.depthFail == rightFront.depthFail
			&& leftFront.compare == rightFront.compare && leftBack.fail == rightBack.fail && leftBack.pass == rightBack.pass
			&& leftBack.depthFail == rightBack.depthFail && leftBack.compare == rightBack.compare && stencil.readMask == other.stencil.readMask
			&& stencil.writeMask == other.stencil.writeMask && stencil.reference == other.stencil.reference;
	}

	public function snapshot():VulkanGraphicsPipelineDesc {
		final result = new VulkanGraphicsPipelineDesc();
		final savedBlend = new VulkanBlendState(blend.enabled, blend.srcColor, blend.dstColor, blend.colorOp,
			blend.srcAlpha, blend.dstAlpha, blend.alphaOp, blend.colorWriteMask);
		final front = new VulkanStencilFaceState(stencil.front.fail, stencil.front.pass, stencil.front.depthFail, stencil.front.compare);
		final back = new VulkanStencilFaceState(stencil.back.fail, stencil.back.pass, stencil.back.depthFail, stencil.back.compare);
		final savedStencil = new VulkanStencilState(stencil.enabled, front, back, stencil.readMask, stencil.writeMask, stencil.reference);
		result.update(program, vertexLayout, colorFormats.copy(), depthFormat, stencilFormat, samples, savedBlend, colorMasks.copy(), savedStencil,
			depthClamp, wireframe);
		return result;
	}
}

private class VulkanGraphicsPipelineEntry {
	public final description:VulkanGraphicsPipelineDesc;
	public final pipeline:VkGraphicsPipeline;

	public function new(description:VulkanGraphicsPipelineDesc, pipeline:VkGraphicsPipeline) {
		this.description = description;
		this.pipeline = pipeline;
	}
}

class VulkanGraphicsPipelineManager {
	final context:VkContext;
	final buckets:Map<Int, Array<VulkanGraphicsPipelineEntry>> = new Map();
	public var createdCount(default, null) = 0;
	public var hitCount(default, null) = 0;

	public function new(context:VkContext) {
		this.context = context;
	}

	public function get(description:VulkanGraphicsPipelineDesc):VkGraphicsPipeline {
		final hash = description.hash();
		var bucket = buckets.get(hash);
		if (bucket != null)
			for (entry in bucket)
				if (entry.description.equals(description)) {
					hitCount++;
					return entry.pipeline;
				}
		if (bucket == null) {
			bucket = [];
			buckets.set(hash, bucket);
		}
		final saved = description.snapshot();
		final pipeline = create(saved);
		bucket.push(new VulkanGraphicsPipelineEntry(saved, pipeline));
		createdCount++;
		return pipeline;
	}

	function create(description:VulkanGraphicsPipelineDesc):VkGraphicsPipeline {
		final bindingDescriptions = new hl.NativeArray<VkVertexInputBindingDescription>(description.vertexLayout.bindings.length);
		for (index => source in description.vertexLayout.bindings) {
			final binding = new VkVertexInputBindingDescription();
			binding.binding = source.binding;
			binding.stride = source.stride;
			binding.inputRate = VERTEX;
			bindingDescriptions[index] = binding;
		}
		final attributeDescriptions = new hl.NativeArray<VkVertexInputAttributeDescription>(description.vertexLayout.attributes.length);
		for (index => source in description.vertexLayout.attributes) {
			final attribute = new VkVertexInputAttributeDescription();
			attribute.location = source.location;
			attribute.binding = source.binding;
			attribute.format = source.format;
			attribute.offset = source.offset;
			attributeDescriptions[index] = attribute;
		}
		final vertexInput = new VkPipelineVertexInput();
		vertexInput.vertexBindingDescriptionCount = bindingDescriptions.length;
		vertexInput.vertexBindingDescriptions = bindingDescriptions.length == 0 ? null : VulkanBindings.makeArray(bindingDescriptions);
		vertexInput.vertexAttributeDescriptionCount = attributeDescriptions.length;
		vertexInput.vertexAttributeDescriptions = attributeDescriptions.length == 0 ? null : VulkanBindings.makeArray(attributeDescriptions);
		final inputAssembly = new VkPipelineInputAssembly();
		inputAssembly.topology = TRIANGLE_LIST;
		final viewport = new VkPipelineViewport();
		viewport.viewportCount = 1;
		viewport.scissorCount = 1;
		final rasterization = new VkPipelineRasterization();
		rasterization.depthClampEnable = description.depthClamp;
		rasterization.polygonMode = description.wireframe ? VkPolygonMode.LINE : VkPolygonMode.FILL;
		rasterization.cullMode = NONE;
		rasterization.frontFace = CLOCKWISE;
		rasterization.lineWidth = 1;
		final multisample = new VkPipelineMultisample();
		multisample.rasterizationSamples = description.samples;
		final depthStencil = new VkPipelineDepthStencil();
		depthStencil.depthCompareOp = ALWAYS;
		depthStencil.stencilTestEnable = description.stencil.enabled;
		if (description.stencil.enabled) {
			final stencil = description.stencil;
			depthStencil.frontFail = stencil.front.fail;
			depthStencil.frontPass = stencil.front.pass;
			depthStencil.frontDepthFail = stencil.front.depthFail;
			depthStencil.frontCompare = stencil.front.compare;
			depthStencil.frontMask = stencil.readMask;
			depthStencil.frontWrite = stencil.writeMask;
			depthStencil.frontReference = stencil.reference;
			depthStencil.backFail = stencil.back.fail;
			depthStencil.backPass = stencil.back.pass;
			depthStencil.backDepthFail = stencil.back.depthFail;
			depthStencil.backCompare = stencil.back.compare;
			depthStencil.backMask = stencil.readMask;
			depthStencil.backWrite = stencil.writeMask;
			depthStencil.backReference = stencil.reference;
		}
		final sourceBlend = description.blend;
		final blendAttachments = new hl.NativeArray<VkPipelineColorBlendAttachmentState>(description.colorFormats.length);
		for (index in 0...description.colorFormats.length) {
			final blendAttachment = new VkPipelineColorBlendAttachmentState();
			blendAttachment.blendEnable = sourceBlend.enabled;
			blendAttachment.srcColorBlendFactor = sourceBlend.srcColor;
			blendAttachment.dstColorBlendFactor = sourceBlend.dstColor;
			blendAttachment.colorBlendOp = sourceBlend.colorOp;
			blendAttachment.srcAlphaBlendFactor = sourceBlend.srcAlpha;
			blendAttachment.dstAlphaBlendFactor = sourceBlend.dstAlpha;
			blendAttachment.alphaBlendOp = sourceBlend.alphaOp;
			blendAttachment.colorWriteMask = description.colorMasks[index];
			blendAttachments[index] = blendAttachment;
		}
		final colorBlend = new VkPipelineColorBlend();
		colorBlend.attachmentCount = blendAttachments.length;
		colorBlend.attachments = blendAttachments.length == 0 ? null : VulkanBindings.makeArray(blendAttachments);
		final dynamicState = new VkPipelineDynamic();
		dynamicState.dynamicStates = new IntArray([
			VkDynamicState.VIEWPORT,
			VkDynamicState.SCISSOR,
			VkDynamicState.CULL_MODE_EXT,
			VkDynamicState.FRONT_FACE_EXT,
			VkDynamicState.PRIMITIVE_TOPOLOGY_EXT,
			VkDynamicState.DEPTH_TEST_ENABLE_EXT,
			VkDynamicState.DEPTH_WRITE_ENABLE_EXT,
			VkDynamicState.DEPTH_COMPARE_OP_EXT,
			VkDynamicState.DEPTH_BIAS_ENABLE_EXT,
			VkDynamicState.DEPTH_BIAS,
		]);
		dynamicState.dynamicStateCount = 10;
		final rendering = new VkPipelineRenderingCreateInfo();
		rendering.colorAttachmentCount = description.colorFormats.length;
		rendering.colorAttachmentFormats = new IntArray(description.colorFormats);
		rendering.depthAttachmentFormat = description.depthFormat;
		rendering.stencilAttachmentFormat = description.stencilFormat;
		final pipelineInfo = new VkGraphicsPipelineCreateInfo();
		@:privateAccess pipelineInfo.next = cast VulkanBindings.makeRef(rendering);
		pipelineInfo.stageCount = 2;
		pipelineInfo.stages = description.program.stages;
		pipelineInfo.vertexInput = vertexInput;
		pipelineInfo.inputAssembly = inputAssembly;
		pipelineInfo.viewport = viewport;
		pipelineInfo.rasterization = rasterization;
		pipelineInfo.multisample = multisample;
		pipelineInfo.depthStencil = depthStencil;
		pipelineInfo.colorBlend = colorBlend;
		pipelineInfo.dynamicDef = dynamicState;
		pipelineInfo.layout = description.program.layout;
		final pipeline = context.createGraphicsPipeline(pipelineInfo);
		if (pipeline == null)
			throw Runtime.error('Failed to create Vulkan graphics pipeline for ${description.program.cacheKey}');
		return pipeline;
	}

	public function dispose() {
		for (bucket in buckets)
			for (entry in bucket)
				context.destroyGraphicsPipeline(entry.pipeline);
		buckets.clear();
	}
}
#end
