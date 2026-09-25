package h3d.impl.driver.vulkan;

#if (limen && gfx_vulkan)
import h3d.impl.driver.Driver;
import h3d.impl.driver.Feature;
import h3d.impl.driver.GPUBuffer;
import h3d.impl.driver.Query;
import h3d.impl.driver.QueryKind;
import h3d.impl.driver.RenderFlag;
import h3d.impl.driver.Texture;
import h3d.impl.driver.vulkan.frame.VulkanFrame;
import h3d.impl.driver.vulkan.frame.VulkanFrame.VulkanDescriptorCacheEntry;
import h3d.impl.driver.vulkan.attachment.VulkanRenderingTargetSet.VulkanRenderingAttachment;
import h3d.impl.driver.vulkan.attachment.VulkanRenderingTargetSet;
import h3d.impl.driver.vulkan.descriptor.VulkanDescriptorArena;
import h3d.impl.driver.vulkan.descriptor.VulkanBindlessDescriptors;
import h3d.impl.driver.vulkan.descriptor.VulkanBindlessDescriptors.VulkanBindlessGeneration;
import h3d.impl.driver.vulkan.memory.VulkanMemoryAllocator;
import h3d.impl.driver.vulkan.resource.VulkanAllocation.VulkanMemoryClass;
import h3d.impl.driver.vulkan.resource.VulkanBuffer;
import h3d.impl.driver.vulkan.resource.VulkanBuffer.VulkanBufferState;
import h3d.impl.driver.vulkan.resource.VulkanInstanceBuffer;
import h3d.impl.driver.vulkan.resource.VulkanDeferredDestroyQueue;
import h3d.impl.driver.vulkan.resource.VulkanImage.VulkanTexture;
import h3d.impl.driver.vulkan.resource.VulkanImage.VulkanImageViewEntry;
import h3d.impl.driver.vulkan.resource.VulkanImage.VulkanImageState;
import h3d.impl.driver.vulkan.resource.VulkanImage.VulkanMipmapMode;
import h3d.impl.driver.vulkan.resource.VulkanResourceState;
import h3d.impl.driver.vulkan.sampler.VulkanSamplerCache;
import h3d.impl.driver.vulkan.texture.VulkanTextureFormat;
import h3d.impl.driver.vulkan.texture.VulkanTextureFormat.VulkanTextureFormatInfo;
import h3d.impl.driver.vulkan.transfer.VulkanUploadManager;
import h3d.impl.driver.vulkan.transfer.VulkanUploadManager.VulkanConstantUpload;
import h3d.impl.driver.vulkan.transfer.VulkanReadbackManager;
import h3d.impl.driver.vulkan.transfer.VulkanReadbackManager.VulkanImageReadbackRequest;
import h3d.impl.driver.vulkan.shader.VulkanCompiledShader;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanConstantBlock;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanConstantFrequency;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanShaderStage;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanNumericType;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanShaderType;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanDescriptorType;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanShaderResource;
import h3d.impl.driver.vulkan.pipeline.VulkanGraphicsPipeline.VulkanBlendState;
import h3d.impl.driver.vulkan.pipeline.VulkanGraphicsPipeline.VulkanGraphicsPipelineDesc;
import h3d.impl.driver.vulkan.pipeline.VulkanGraphicsPipeline.VulkanGraphicsPipelineManager;
import h3d.impl.driver.vulkan.pipeline.VulkanGraphicsPipeline.VulkanStencilFaceState;
import h3d.impl.driver.vulkan.pipeline.VulkanGraphicsPipeline.VulkanStencilState;
import h3d.impl.driver.vulkan.pipeline.VulkanGraphicsPipeline.VulkanVertexAttribute;
import h3d.impl.driver.vulkan.pipeline.VulkanGraphicsPipeline.VulkanVertexBinding;
import h3d.impl.driver.vulkan.pipeline.VulkanGraphicsPipeline.VulkanVertexLayout;
import h3d.impl.driver.vulkan.pipeline.VulkanComputePipeline;
import h3d.impl.driver.vulkan.pipeline.VulkanComputePipeline.VulkanComputePipelineManager;
import h3d.impl.driver.vulkan.pipeline.VulkanPipelineLayoutCache;
import h3d.impl.driver.vulkan.query.VulkanQuery;
import h3d.impl.driver.vulkan.query.VulkanQuery.VulkanQueryGeneration;
import h3d.impl.driver.vulkan.query.VulkanQuery.VulkanQueryManager;
import h3d.impl.driver.vulkan.query.VulkanQuery.VulkanQueryState;
import h3d.impl.driver.vulkan.shader.VulkanShaderCompilerService;
import h3d.impl.driver.vulkan.shader.VulkanShaderCompilerService.VulkanCompiledProgramData;
import h3d.impl.driver.vulkan.shader.VulkanShaderStageData;
import h3d.impl.driver.vulkan.swapchain.VulkanSwapchainImage;
import limen.graphics.vulkan.VulkanCore.ArrayStruct;
import limen.graphics.vulkan.command.Commands.VkCommandBuffer;
import limen.graphics.vulkan.command.Commands.VkCommandBufferAllocateInfo;
import limen.graphics.vulkan.command.Commands.VkCommandBufferBeginInfo;
import limen.graphics.vulkan.command.Commands.VkCommandPool;
import limen.graphics.vulkan.command.Commands.VkCommandPoolCreateInfo;
import limen.graphics.vulkan.command.Commands.VkDynamicRenderingClearInfo;
import limen.graphics.vulkan.command.Commands.VkIndexType;
import limen.graphics.vulkan.command.Commands.VkFilter;
import limen.graphics.vulkan.command.Commands.VkImageBlitRegion;
import limen.graphics.vulkan.command.Commands.VkPipelineStage2;
import limen.graphics.vulkan.command.Commands.VkFenceCreateInfo;
import limen.graphics.vulkan.command.Commands.VkSemaphore;
import limen.graphics.vulkan.command.Commands.VkSemaphoreCreateInfo;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorSet;
import limen.graphics.vulkan.descriptor.Descriptors.VkDescriptorType;
import limen.graphics.vulkan.device.DeviceLimits.VkPhysicalDeviceLimits;
import limen.graphics.vulkan.device.Capabilities;
import limen.graphics.vulkan.format.Formats.VkFormat;
import limen.graphics.vulkan.format.Formats.VkFormatFeature;
import limen.graphics.vulkan.format.Formats.VkFormatProperties;
import limen.graphics.vulkan.internal.VulkanBindings as Vulkan;
import limen.graphics.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.vulkan.internal.VulkanBindings.VkSwapchainInfo;
import limen.graphics.vulkan.memory.Memory.VkBufferUsageFlag;
import limen.graphics.vulkan.memory.Memory.VkAccess2;
import limen.graphics.vulkan.memory.Memory.VkImageAspectFlag;
import limen.graphics.vulkan.memory.Memory.VkImageCreateInfo;
import limen.graphics.vulkan.memory.Memory.VkImageLayout;
import limen.graphics.vulkan.memory.Memory.VkImageView;
import limen.graphics.vulkan.memory.Memory.VkImageViewCreateInfo;
import limen.graphics.vulkan.memory.Memory.VkImageViewType;
import limen.graphics.vulkan.memory.Memory.VkMemoryHeapBudgetInfo;
import limen.graphics.vulkan.memory.Memory.VkMemoryPropertyFlag;
import limen.graphics.vulkan.memory.Memory.VkMemoryRequirementsInfo;
import limen.graphics.vulkan.pipeline.Pipeline.VkBlendFactor;
import limen.graphics.vulkan.pipeline.Pipeline.VkBlendOp;
import limen.graphics.vulkan.pipeline.Pipeline.VkCompareOp;
import limen.graphics.vulkan.pipeline.Pipeline.VkCullModeFlags;
import limen.graphics.vulkan.pipeline.Pipeline.VkFrontFace;
import limen.graphics.vulkan.pipeline.Pipeline.VkGraphicsPipeline;
import limen.graphics.vulkan.pipeline.Pipeline.VkPrimitiveTopology;
import limen.graphics.vulkan.pipeline.Pipeline.VkStencilOp;
import limen.graphics.vulkan.pipeline.Pipeline.VkPipelineShaderStage;
import limen.graphics.vulkan.render.RenderPass.VkClearAttachment;
import limen.graphics.vulkan.render.RenderPass.VkClearRect;
import limen.graphics.vulkan.query.Queries.VkQueryControlFlag;
import limen.graphics.vulkan.Runtime;
import limen.graphics.vulkan.shader.ShaderModule;
import limen.graphics.vulkan.shader.ShaderModule.VkShaderStageFlag;
import limen.graphics.vulkan.sampler.Samplers.VkSampler;
import limen.graphics.vulkan.Surface;

import hxd.Math;

private class VulkanResolvedTexture {
	public var texture:h3d.mat.Texture;
	public var image:VulkanTexture;
	public var bits:Int;
	public var flags:Int;
	public var filterable:Bool;
	public var storage:Bool;
	public var view:VkImageView;
	public var viewKey:String;
	public var sampler:VkSampler;
	public var samplerKey:String;
	public var baseMip:Int;
	public var levelCount:Int;
	public var baseLayer:Int;
	public var layerCount:Int;

	public function new() {
	}

	public function update(texture:h3d.mat.Texture, image:VulkanTexture, bits:Int, flags:Int, storage:Bool, view:VkImageView, viewKey:String, sampler:VkSampler, samplerKey:String,
		baseMip:Int, levelCount:Int, baseLayer:Int, layerCount:Int) {
		this.texture = texture;
		this.image = image;
		this.bits = bits;
		this.flags = flags;
		this.filterable = image.filterable;
		this.storage = storage;
		this.view = view;
		this.viewKey = viewKey;
		this.sampler = sampler;
		this.samplerKey = samplerKey;
		this.baseMip = baseMip;
		this.levelCount = levelCount;
		this.baseLayer = baseLayer;
		this.layerCount = layerCount;
	}
}

private class VulkanBindlessTextureSlot {
	public final texture:h3d.mat.Texture;
	public final bits:Int;
	public final index:Int;
	public var image:VulkanTexture;
	public var viewKey:String;

	public function new(texture:h3d.mat.Texture, bits:Int, index:Int, image:VulkanTexture, viewKey:String) {
		this.texture = texture;
		this.bits = bits;
		this.index = index;
		this.image = image;
		this.viewKey = viewKey;
	}
}

private class VulkanBindlessResolvedView {
	public var image:VulkanTexture;
	public var view:VkImageView;
	public var key:String;
	public var baseMip:Int;
	public var levelCount:Int;
	public var baseLayer:Int;
	public var layerCount:Int;

	public function new() {
	}
}

private class VulkanMipmapShader extends hxsl.Shader {
	static var SRC = {
		@input var input:{var position:Vec2; var uv:Vec2;};
		@param var source:Sampler2D;
		var output:{var position:Vec4; var color:Vec4;};
		var textureUv:Vec2;

		function vertex() {
			output.position = vec4(input.position, 0.0, 1.0);
			textureUv = input.uv;
		}

		function fragment() {
			output.color = source.get(textureUv);
		}
	};
}

class VulkanDriver extends Driver {

	var ctx : VkContext;
	var surface : Surface;
	var capabilities : Capabilities;
	var disposed = false;
	var swapchainReady = false;
	var recreatePending = false;
	var retiredPresentSemaphores : Array<VkSemaphore> = [];
	var currentShader : VulkanCompiledShader;
	var programs : Map<String,VulkanCompiledShader> = new Map();
	var shaderKeys : Map<Int,String> = new Map();
	var shaderCompiler : VulkanShaderCompilerService;
	var pipelineManager : VulkanGraphicsPipelineManager;
	var computePipelineManager : VulkanComputePipelineManager;
	var pipelineLayoutCache : VulkanPipelineLayoutCache;
	var command : VkCommandBuffer;
	var commandPool : VkCommandPool;
	var savedPointers : Array<Dynamic> = [];
	var colorViewScratch = new hl.NativeArray<VkImageView>(0);
	var vertexBufferScratch = new hl.NativeArray<limen.graphics.vulkan.memory.Memory.VkBuffer>(0);
	var vertexOffsetScratch = new hl.NativeArray<hl.I64>(0);
	var descriptorSetScratch = new hl.NativeArray<VkDescriptorSet>(0);
	var dynamicOffsetScratch = new hl.NativeArray<Int>(0);
	var boundGraphicsSets = new hl.NativeArray<VkDescriptorSet>(0);
	var boundComputeSets = new hl.NativeArray<VkDescriptorSet>(0);
	var boundGraphicsOffsets = new hl.NativeArray<Int>(0);
	var boundComputeOffsets = new hl.NativeArray<Int>(0);
	var boundGraphicsSetCount = 0;
	var boundComputeSetCount = 0;
	var boundGraphicsOffsetCount = 0;
	var boundComputeOffsetCount = 0;
	var clearAttachmentScratch = new hl.NativeArray<Int>(0);
	var clearRectScratch = new hl.NativeArray<Int>(6);


	var queueFamily : Int;
	var depthFormat : VkFormat;
	var outImageFormat : VkFormat;
	var outImages : Array<VulkanSwapchainImage>;
	var viewportWidth : Int;
	var viewportHeight : Int;
	var swapchainVsync : Bool;
	var swapchainTransferSource = false;
	var renderZoneX : Int;
	var renderZoneY : Int;
	var renderZoneWidth : Int;
	var renderZoneHeight : Int;

	var frames : Array<VulkanFrame>;
	var currentImageIndex : Int;
	var currentFrameIndex : Int;
	var frameStarted = false;
	var renderingStarted = false;
	var pendingClearColor : Vector4;
	var pendingClearDepth : Null<Float>;
	var pendingClearStencil : Null<Int>;
	var limits : VkPhysicalDeviceLimits;
	var allocator : VulkanMemoryAllocator;
	var uploadManager : VulkanUploadManager;
	var readbackManager : VulkanReadbackManager;
	var queryManager : VulkanQueryManager;
	var activeSampleQuery : VulkanQuery;
	var activeSampleGeneration : VulkanQueryGeneration;
	var activeSampleNativeStarted = false;
	var activeQueryIntervals = 0;
	var samplerCache : VulkanSamplerCache;
	var bindlessDescriptors : VulkanBindlessDescriptors;
	var textureHandles:Map<h3d.mat.Texture, Map<Int, h3d.mat.TextureHandle>> = new Map();
	var textureImageSlots:Map<h3d.mat.Texture, Map<Int, VulkanBindlessTextureSlot>> = new Map();
	var bindlessTextureSlots:Array<VulkanBindlessTextureSlot> = [];
	final bindlessResolvedView = new VulkanBindlessResolvedView();
	var samplerHandles:Map<String, Int> = new Map();
	var bufferHandles:Map<h3d.Buffer, h3d.BufferHandle> = new Map();
	var liveBuffers : Array<VulkanBuffer> = [];
	var liveTextures : Array<VulkanTexture> = [];
	var deferredDestroy = new VulkanDeferredDestroyQueue();
	var currentSubmissionSerial = 1;
	var completedSubmissionSerial = 0;
	var currentVertexLayout : VulkanVertexLayout;
	final vertexLayouts:Map<VulkanCompiledShader, Map<hxd.BufferFormat, VulkanVertexLayout>> = new Map();
	final multiVertexLayouts:Map<VulkanCompiledShader, Map<hxd.BufferFormat.MultiFormat, VulkanVertexLayout>> = new Map();
	var pipelineDescription = new VulkanGraphicsPipelineDesc();
	var pipelineColorFormats:Array<VkFormat> = [];
	var pipelineColorMasks:Array<Int> = [];
	final blendFormatSupport:Map<Int, Bool> = new Map();
	var currentVertexBuffers : Array<VulkanBuffer> = [];
	var currentBlendState : VulkanBlendState;
	var currentCullMode : VkCullModeFlags;
	var currentDepthTest = true;
	var currentDepthWrite = true;
	var currentDepthCompare : VkCompareOp;
	var currentDepthClamp = false;
	var currentWireframe = false;
	var driverDepthClamp = false;
	var depthBias = 0.;
	var slopeScaledDepthBias = 0.;
	var rightHanded = false;
	var currentColorMasks = 15;
	var currentStencilState : VulkanStencilState;
	var disabledStencilState:VulkanStencilState;
	var readOnlyStencilState:VulkanStencilState;
	var materialSelected = false;
	var boundPipeline : VkGraphicsPipeline;
	var boundDescriptorState : VulkanCompiledShader;
	var boundComputePipeline : VulkanComputePipeline;
	var boundComputeDescriptorState : VulkanCompiledShader;
	var boundDynamicState = false;
	var boundCullMode:VkCullModeFlags;
	var boundFrontFace:VkFrontFace;
	var boundDepthTest:Bool;
	var boundDepthWrite:Bool;
	var boundDepthCompare:VkCompareOp;
	var boundBiasEnabled:Bool;
	var boundDepthBias:Float;
	var boundSlopeScaledDepthBias:Float;
	var renderingResume = false;
	var textureBindings:Map<String, h3d.mat.Texture> = new Map();
	var resolvedTextureScratch:Map<String, Array<VulkanResolvedTexture>> = new Map();
	var textureBindingsShaderKey:String;
	var bufferBindings:Map<String, h3d.Buffer> = new Map();
	var bufferBindingKinds:Map<String, hxsl.Ast.BufferKind> = new Map();
	var bufferBindingsShaderKey:String;
	var fallbackTextures:Map<String, h3d.mat.Texture> = new Map();
	var nextFallbackTextureId = -1;
	var currentTargetSet:VulkanRenderingTargetSet;
	var pendingInitialColorClears:Array<Int> = [];
	final noInitialColorClears:Array<Int> = [];
	final firstColorClear:Array<Int> = [0];
	final targetColorClears:Array<Int> = [];
	var pendingInitialDepthClear = false;
	var defaultDepthBuffer:h3d.mat.Texture;
	var nextInstanceBufferId = 1;
	var mipmapShader:hxsl.RuntimeShader;
	var mipmapPass:h3d.mat.Pass;
	var mipmapVertex:h3d.Buffer;
	var mipmapIndex:h3d.Buffer;

	var frameCount = 2;

	public function new() {
		var win = hxd.Window.getInstance();
		surface = Surface.create(@:privateAccess win.window, Vulkan.ENABLE_VALIDATION);
		try {
			initContext(surface);
			if( initSwapchain(win.width, win.height) )
				beginFrame();
		} catch( error : Dynamic ) {
			dispose();
			throw error;
		}
	}

	function initContext(surface) {
		var queueFamily = 0;

		ctx = Runtime.createContext(surface, queueFamily);
		capabilities = Runtime.getCapabilities(ctx);
		shaderCompiler = new VulkanShaderCompilerService();
		this.queueFamily = queueFamily;
		this.depthFormat = selectDepthFormat();

		var poolInf = new VkCommandPoolCreateInfo();
		poolInf.flags.set(RESET_COMMAND_BUFFER);
		poolInf.queueFamilyIndex = queueFamily;
		commandPool = ctx.createCommandPool(poolInf);
		if( commandPool == null )
			throw Runtime.error("Failed to create Vulkan command pool");


		frames = [];
		for( i in 0...frameCount ) {
			var frame = new VulkanFrame();
			var inf = new VkCommandBufferAllocateInfo();
			inf.commandPool = commandPool;
			inf.commandBufferCount = 1;

			var arr = new hl.NativeArray(1);
			if( ctx.allocateCommandBuffers(inf,arr) != 0 )
				throw Runtime.error("Failed to allocate Vulkan frame command buffer");
			frame.command = arr[0];

			var inf = new VkFenceCreateInfo();
			inf.flags.set(SIGNALED);
			frame.fence = ctx.createFence(inf);

			var inf = new VkSemaphoreCreateInfo();
			frame.imageAvailable = ctx.createSemaphore(inf);
			if( frame.fence == null || frame.imageAvailable == null )
				throw Runtime.error("Failed to create Vulkan frame synchronization objects");

			frame.descriptorArena = new VulkanDescriptorArena(ctx);
			frames.push(frame);
		}

		limits = ctx.getLimits();
		allocator = new VulkanMemoryAllocator(ctx, limits);
		uploadManager = new VulkanUploadManager(ctx, allocator, frameCount);
		readbackManager = new VulkanReadbackManager(ctx, allocator, frameCount);
		queryManager = new VulkanQueryManager(ctx, frameCount, capabilities.timestampValidBits, capabilities.timestampPeriod,
			capabilities.occlusionQueryPrecise);
		samplerCache = new VulkanSamplerCache(ctx, limits, capabilities.samplerAnisotropy);
		if( VulkanBindlessDescriptors.supported(capabilities, frameCount) ) {
			bindlessDescriptors = new VulkanBindlessDescriptors(ctx, capabilities, frameCount);
			for( frame in frames )
				frame.bindlessGeneration = bindlessDescriptors.createGeneration();
		}
		pipelineManager = new VulkanGraphicsPipelineManager(ctx);
		computePipelineManager = new VulkanComputePipelineManager(ctx);
		pipelineLayoutCache = new VulkanPipelineLayoutCache(ctx, bindlessDescriptors == null ? null : bindlessDescriptors.layout);
	}

	function initSwapchain( width : Int, height : Int ) : Bool {
		var images = new hl.NativeArray(8);
		swapchainVsync = hxd.Window.getInstance().vsync;
		var info = new VkSwapchainInfo(width, height, swapchainVsync);
		var status = ctx.initSwapchain(info, images);
		if( status == Deferred ) {
			swapchainReady = false;
			return false;
		}
		if( status != Success )
			throw Runtime.error('Failed to initialize Vulkan swapchain (status $status)');
		width = info.actualWidth;
		height = info.actualHeight;
		var format = info.format;

		outImageFormat = format;
		swapchainTransferSource = info.transferSource != 0;

		var newImages = [];
		var swapchainImageIndex = 0;
		for( img in images ) {

			var inf = new VkImageCreateInfo();
			inf.imageType = TYPE_2D;
			inf.width = width;
			inf.height = height;
			inf.depth = 1;
			inf.arrayLayers = 1;
			inf.mipLevels = 1;
			inf.tiling = OPTIMAL;
			inf.samples = 1;
			inf.format = depthFormat;
			inf.usage.set(DEPTH_STENCIL_ATTACHMENT);
			inf.usage.set(TRANSFER_SRC);

			var depth = ctx.createImage(inf);
			if( depth == null )
				throw Runtime.error("Failed to create Vulkan depth image");
			final depthName = 'swapchain-depth-$swapchainImageIndex';
			ctx.setImageName(depth, @:privateAccess depthName.toUtf8());
			var depthRequirements = new VkMemoryRequirementsInfo();
			ctx.getImageMemoryRequirements2(depth, depthRequirements);
			final deviceLocal = 1 << Type.enumIndex(VkMemoryPropertyFlag.DEVICE_LOCAL);
			var depthAllocation = try allocator.allocate(depthRequirements, DeviceImage, deviceLocal, deviceLocal, null, depth, depthName) catch( error : Dynamic ) {
				ctx.destroyImage(depth);
				throw error;
			};
			if( !ctx.bindImageMemory64(depth, depthAllocation.memory, (depthAllocation.offset : hl.I64)) ) {
				depthAllocation.dispose();
				ctx.destroyImage(depth);
				throw Runtime.error("Failed to bind Vulkan depth memory");
			}

			var viewInfo = new VkImageViewCreateInfo();
			viewInfo.image = img;
			viewInfo.viewType = TYPE_2D;
			viewInfo.format = format;
			viewInfo.layerCount = 1;
			viewInfo.levelCount = 1;
			viewInfo.aspectMask.set(COLOR);

			var view = ctx.createImageView(viewInfo);
			if( view == null )
				throw Runtime.error("Failed to create Vulkan swapchain image view");
			final swapchainName = 'swapchain-image-$swapchainImageIndex';
			final swapchainViewName = '$swapchainName-view';
			ctx.setImageName(img, @:privateAccess swapchainName.toUtf8());
			ctx.setImageViewName(view, @:privateAccess swapchainViewName.toUtf8());

			var viewInfo = new VkImageViewCreateInfo();
			viewInfo.image = depth;
			viewInfo.viewType = TYPE_2D;
			viewInfo.format = depthFormat;
			viewInfo.layerCount = 1;
			viewInfo.levelCount = 1;
			viewInfo.aspectMask.set(DEPTH);
			var depthView = ctx.createImageView(viewInfo);
			if( depthView == null )
				throw Runtime.error("Failed to create Vulkan depth image view");
			final depthViewName = '$depthName-view';
			ctx.setImageViewName(depthView, @:privateAccess depthViewName.toUtf8());
			var out = new VulkanSwapchainImage();
			out.img = img;
			out.view = view;
			out.depth = depth;
			out.depthView = depthView;
			out.depthAllocation = depthAllocation;
			var depthAspect = new haxe.EnumFlags<VkImageAspectFlag>();
			depthAspect.set(DEPTH);
			if( formatHasStencil(depthFormat) )
				depthAspect.set(STENCIL);
			out.depthResource = new VulkanTexture(depth, depthView, depthAllocation, depthRequirements.size, depthFormat, width, height, 1, 1, 1,
				depthAspect, inf.usage, false, VulkanMipmapMode.None, -1000 - swapchainImageIndex, depthName);
			out.renderFinished = ctx.createSemaphore(new VkSemaphoreCreateInfo());
			if( out.renderFinished == null )
				throw Runtime.error("Failed to create Vulkan presentation semaphore");
			newImages.push(out);
			swapchainImageIndex++;
		}
		outImages = newImages;

		viewportWidth = width;
		viewportHeight = height;
		if( defaultDepthBuffer != null )
			@:privateAccess {
				defaultDepthBuffer.width = width;
				defaultDepthBuffer.height = height;
			}
		setRenderZone(0, 0, -1, -1);
		swapchainReady = true;
		recreatePending = status == Suboptimal;
		return true;
	}

	function waitForFrames() {
		if( frames == null )
			return;
		for( index => frame in frames ) {
			if( ctx.waitForFence(frame.fence, -1) != 0 )
				throw Runtime.error("Failed to wait for Vulkan frame completion");
			if( frame.submissionSerial > completedSubmissionSerial )
				completedSubmissionSerial = frame.submissionSerial;
			if( queryManager != null )
				queryManager.completeFrame(index);
		}
	}

	function releaseSwapchainResources( images : Array<VulkanSwapchainImage> ) {
		if( images == null )
			return;
		for( img in images ) {
			retiredPresentSemaphores.push(img.renderFinished);
			@:privateAccess img.depthResource.markDisposed();
			ctx.destroyImageView(img.view);
			@:privateAccess img.depthResource.destroyViews(ctx.destroyImageView);
			ctx.destroyImage(img.depthResource.image);
			img.depthResource.allocation.dispose();
		}
	}

	function recreateSwapchain( width : Int, height : Int ) : Bool {
		if( width <= 0 || height <= 0 ) {
			swapchainReady = false;
			return false;
		}
		waitForFrames();
		var previousImages = outImages;
		if( !initSwapchain(width, height) )
			return false;
		releaseSwapchainResources(previousImages);
		currentImageIndex = -1;
		return true;
	}

	function selectDepthFormat() {
		for( format in [D24_UNORM_S8_UINT, D32_SFLOAT_S8_UINT, D32_SFLOAT] ) {
			var props = new VkFormatProperties();
			ctx.getPdeviceFormatProps(format, props);
			final required = (cast VkFormatFeature.DEPTH_STENCIL_ATTACHMENT : Int) | (cast VkFormatFeature.TRANSFER_SRC : Int);
			if( (props.optimalTilingFeatures & required) == required )
				return format;
		}
		throw "Could not find supported depth format";
	}

	function depthTextureFormat(format:VkFormat):hxd.PixelFormat {
		return switch (format) {
		case D16_UNORM: Depth16;
		case X8_D24_UNORM_PACK32: Depth24;
		case D24_UNORM_S8_UINT: Depth24Stencil8;
		case D32_SFLOAT: Depth32;
		case D32_SFLOAT_S8_UINT: Depth32Stencil8;
		default: throw 'Unsupported Vulkan depth format $format';
		}
	}

	inline function formatHasStencil(format:VkFormat):Bool {
		return format == D24_UNORM_S8_UINT || format == D32_SFLOAT_S8_UINT;
	}

	inline function stencilAttachmentFormat():VkFormat {
		return depthFormat == D24_UNORM_S8_UINT || depthFormat == D32_SFLOAT_S8_UINT ? depthFormat : UNDEFINED;
	}

	function beginFrame() : Bool {
		if( !swapchainReady || disposed )
			return false;
		var frame = frames[currentFrameIndex];
		if( ctx.waitForFence(frame.fence, -1) != 0 )
			throw Runtime.error("Failed to wait for Vulkan frame fence");
		if( frame.submissionSerial > completedSubmissionSerial )
			completedSubmissionSerial = frame.submissionSerial;
		queryManager.completeFrame(currentFrameIndex);
		deferredDestroy.collect(completedSubmissionSerial);
		readbackManager.completeFrame(currentFrameIndex);
		uploadManager.beginFrame(currentFrameIndex);
		frame.reclaimDescriptors();
		if( bindlessDescriptors != null )
			bindlessDescriptors.sync(frame.bindlessGeneration);
		frame.shaderConstants.clear();
		var acquiredImage = 0;
		var acquireStatus = ctx.acquireNextImage(frame.imageAvailable, acquiredImage);
		if( acquireStatus == OutOfDate ) {
			var win = hxd.Window.getInstance();
			if( !recreateSwapchain(win.width, win.height) )
				return false;
			acquireStatus = ctx.acquireNextImage(frame.imageAvailable, acquiredImage);
		}
		if( acquireStatus != Success && acquireStatus != Suboptimal )
			throw Runtime.error('Failed to acquire Vulkan swapchain image (status $acquireStatus)');
		currentImageIndex = acquiredImage;
		frame.imageAvailableConsumed = false;
		recreatePending = acquireStatus == Suboptimal;
		var img = outImages[currentImageIndex];
		if( img.fence != null && img.fence != frame.fence && ctx.waitForFence(img.fence, -1) != 0 )
			throw Runtime.error("Failed to wait for Vulkan swapchain image fence");
		img.fence = frame.fence;
		if( ctx.resetFence(frame.fence) != 0 )
			throw Runtime.error("Failed to reset Vulkan frame fence");
		if( frame.command.reset() != 0 )
			throw Runtime.error("Failed to reset Vulkan frame command buffer");

		var inf = new VkCommandBufferBeginInfo();
		inf.flags.set(ONE_TIME_SUBMIT);
		command = frame.command;
		if( command.begin(inf) != 0 )
			throw Runtime.error("Failed to begin Vulkan frame command buffer");
		queryManager.beginFrame(currentFrameIndex, command);
		frameStarted = true;
		renderingStarted = false;
		renderingResume = false;
		boundPipeline = null;
		boundDescriptorState = null;
		boundComputePipeline = null;
		boundComputeDescriptorState = null;
		boundDynamicState = false;
		currentVertexLayout = null;
		currentVertexBuffers.resize(0);
		currentTargetSet = resolveDefaultTarget(ReadWrite);
		if( defaultDepthBuffer != null )
			@:privateAccess defaultDepthBuffer.t = outImages[currentImageIndex].depthResource;
		viewportWidth = currentTargetSet.width;
		viewportHeight = currentTargetSet.height;
		setRenderZone(0, 0, -1, -1);
		pendingInitialColorClears = outImages[currentImageIndex].initialized ? noInitialColorClears : firstColorClear;
		pendingInitialDepthClear = !outImages[currentImageIndex].initialized;
		return true;
	}

	function beginRendering() {
		if( renderingStarted )
			return;
		if( currentTargetSet == null )
			throw "Vulkan rendering requires an active attachment set";
		for( color in currentTargetSet.colors ) {
			if( color.resource != null )
				VulkanResourceState.transitionImage(command, color.resource, color.mipLevel, color.layer, ColorAttachment, color.aspect);
			else {
				final swapchain = outImages[currentImageIndex];
				final sourceStage = VkPipelineStage2.COLOR_ATTACHMENT_OUTPUT;
				final sourceAccess = swapchain.colorLayout == ATTACHMENT_OPTIMAL_KHR ? VkAccess2.COLOR_ATTACHMENT_WRITE : VkAccess2.NONE;
				final destinationAccess = (cast ((VkAccess2.COLOR_ATTACHMENT_READ : haxe.Int64) | (VkAccess2.COLOR_ATTACHMENT_WRITE : haxe.Int64)) : hl.I64);
				if( swapchain.colorLayout != ATTACHMENT_OPTIMAL_KHR || renderingResume ) {
					VulkanResourceState.recordBarrier();
					command.imageBarrier2(color.image, color.aspect, 0, 1, 0, 1, swapchain.colorLayout, ATTACHMENT_OPTIMAL_KHR,
						sourceStage, sourceAccess, VkPipelineStage2.COLOR_ATTACHMENT_OUTPUT, destinationAccess);
				}
				swapchain.colorLayout = ATTACHMENT_OPTIMAL_KHR;
			}
		}
		final depthState = currentTargetSet.depthBinding == ReadOnly ? DepthStencilReadOnly : DepthStencilAttachment;
		if( currentTargetSet.depth != null )
			VulkanResourceState.transitionImage(command, currentTargetSet.depth.resource, currentTargetSet.depth.mipLevel,
				currentTargetSet.depth.layer, depthState, currentTargetSet.depth.aspect);
		final colorCount = currentTargetSet.colors.length;
		if( colorViewScratch.length < colorCount ) colorViewScratch = new hl.NativeArray<VkImageView>(colorCount);
		for( index in 0...colorCount ) colorViewScratch[index] = currentTargetSet.colors[index].view;
		final depthLayout = currentTargetSet.depthBinding == ReadOnly ? DEPTH_STENCIL_READ_ONLY_OPTIMAL : DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
		command.beginDynamicRenderingNative(currentTargetSet.width, currentTargetSet.height, colorCount, colorViewScratch,
			COLOR_ATTACHMENT_OPTIMAL, currentTargetSet.depth == null ? null : currentTargetSet.depth.view, depthLayout,
			currentTargetSet.stencil == null ? null : currentTargetSet.stencil.view, depthLayout);
		renderingStarted = true;
		renderingResume = false;
		applyViewport();
		applyScissor();
		if( pendingInitialColorClears.length > 0 ) {
			clearColorAttachments(pendingInitialColorClears, new Vector4(0, 0, 0, 0));
			pendingInitialColorClears = noInitialColorClears;
		}
		if( pendingInitialDepthClear ) {
			clearNow(null, 1, currentTargetSet.hasStencil() ? 0 : null);
			pendingInitialDepthClear = false;
		}
		if( pendingClearColor != null || pendingClearDepth != null || pendingClearStencil != null ) {
			clearNow(pendingClearColor, pendingClearDepth, pendingClearStencil);
			pendingClearColor = null;
			pendingClearDepth = null;
			pendingClearStencil = null;
		}
	}

	function suspendRendering() {
		if( !renderingStarted )
			return;
		if( activeSampleNativeStarted )
			throw "Cannot suspend Vulkan rendering while a Samples query is active";
		command.endDynamicRendering();
		renderingStarted = false;
		renderingResume = true;
		boundPipeline = null;
		boundDescriptorState = null;
		boundDynamicState = false;
	}

	function endFrame() {
		if( !frameStarted )
			return;
		if( activeQueryIntervals != 0 )
			throw "Cannot submit a Vulkan command stream while a query interval is active";
		if( currentTargetSet == null || !currentTargetSet.isDefault )
			changeTarget(resolveDefaultTarget(ReadWrite));
		beginRendering();
		final swapchain = outImages[currentImageIndex];
		final image = swapchain.img;
		command.endDynamicRenderingPresent(image);
		swapchain.colorLayout = PRESENT_SRC_KHR;
		if( command.end() != 0 )
			throw Runtime.error("Failed to end Vulkan frame command buffer");
		frameStarted = false;
		renderingStarted = false;
	}

	override function hasFeature( f : Feature ) {
		return switch( f ) {
		case HardwareAccelerated, StandardDerivatives, ShaderModel3, InstancedRendering: true;
		case AllocDepthBuffer: depthFormat != UNDEFINED;
		case DepthTextureArray: true;
		case ComputeShaders: capabilities != null && capabilities.graphicsQueueCompute;
		case MultipleRenderTargets: limits != null && limits.maxColorAttachments > 1;
		case FloatTextures: isSupportedFormat(RGBA16F);
		case SRGBTextures: isSupportedFormat(SRGB_ALPHA);
		case Bindless: bindlessDescriptors != null;
		case Queries: capabilities != null && capabilities.timestampValidBits > 0 && capabilities.occlusionQueryPrecise;
		case Wireframe: capabilities != null && capabilities.fillModeNonSolid;
		default: false;
		}
	}

	override function isSupportedFormat( fmt : h3d.mat.Data.TextureFormat ) {
		final mapping = try VulkanTextureFormat.resolve(fmt) catch( _ : Dynamic ) return false;
		var required:Int = cast VkFormatFeature.SAMPLED_IMAGE;
		required |= cast VkFormatFeature.TRANSFER_DST;
		if( mapping.depth )
			required |= cast VkFormatFeature.DEPTH_STENCIL_ATTACHMENT;
		final properties = new VkFormatProperties();
		ctx.getPdeviceFormatProps(mapping.format, properties);
		return mapping.uploadCompatible && mapping.sampledCompatible && (properties.optimalTilingFeatures & required) == required;
	}

	override function logImpl(str:String) {
		#if sys
		Sys.println(str);
		#else
		trace(str);
		#end
	}

	override function isDisposed() {
		return disposed;
	}

	override function isFrameReady() {
		return frameStarted;
	}

	override function dispose() {
		if( disposed )
			return;
		disposed = true;
		frameStarted = false;
		renderingStarted = false;
		if( ctx != null ) {
			if( ctx.waitIdle() != 0 )
				throw Runtime.error("Failed to wait for Vulkan shutdown");
			if( queryManager != null ) {
				queryManager.dispose();
				queryManager = null;
			}
			if( uploadManager != null ) {
				uploadManager.dispose();
				uploadManager = null;
			}
			if( readbackManager != null ) {
				readbackManager.dispose();
				readbackManager = null;
			}
			deferredDestroy.drain();
			if( pipelineManager != null ) {
				pipelineManager.dispose();
				pipelineManager = null;
			}
			if( computePipelineManager != null ) {
				computePipelineManager.dispose();
				computePipelineManager = null;
			}
			for( program in programs )
				program.dispose(ctx);
			programs.clear();
			vertexLayouts.clear();
			multiVertexLayouts.clear();
			shaderKeys.clear();
			if( frames != null )
				for( frame in frames ) if( frame.descriptorArena != null ) frame.descriptorArena.dispose();
			if( pipelineLayoutCache != null ) {
				pipelineLayoutCache.dispose();
				pipelineLayoutCache = null;
			}
			if( bindlessDescriptors != null ) {
				bindlessDescriptors.dispose();
				bindlessDescriptors = null;
			}
			if( samplerCache != null ) {
				samplerCache.dispose();
				samplerCache = null;
			}
			if( shaderCompiler != null ) {
				shaderCompiler.dispose();
				shaderCompiler = null;
			}
			for( texture in liveTextures.copy() )
				destroyTextureResource(texture, true);
			fallbackTextures.clear();
			for( buffer in liveBuffers.copy() )
				destroyBufferResource(buffer, true);
			if( outImages != null ) {
				for( image in outImages ) {
					ctx.destroySemaphore(image.renderFinished);
					@:privateAccess image.depthResource.markDisposed();
					ctx.destroyImageView(image.view);
					@:privateAccess image.depthResource.destroyViews(ctx.destroyImageView);
					ctx.destroyImage(image.depthResource.image);
					image.depthResource.allocation.dispose();
				}
				outImages = null;
			}
			for( semaphore in retiredPresentSemaphores )
				ctx.destroySemaphore(semaphore);
			retiredPresentSemaphores = [];
			if( frames != null ) {
				for( frame in frames ) {
					ctx.destroySemaphore(frame.imageAvailable);
					ctx.destroyFence(frame.fence);
				}
				frames = null;
			}
			if( commandPool != null )
				ctx.destroyCommandPool(commandPool);
			if( allocator != null ) {
				allocator.dispose();
				allocator = null;
			}
			Runtime.destroyContext(ctx);
			ctx = null;
		}
		if( surface != null ) {
			surface.destroy();
			surface = null;
		}
	}

	override function getDriverName( details : Bool ) {
		if( !details || capabilities == null )
			return "Vulkan";
		var version = capabilities.apiVersion;
		final memoryReporting = ctx != null && ctx.hasMemoryBudget() ? "VK_EXT_memory_budget" : "allocator estimate";
		return 'Vulkan ${version >>> 22}.${(version >>> 12) & 0x3FF}.${version & 0xFFF} (vendor 0x${StringTools.hex(capabilities.vendorId, 4)}, device 0x${StringTools.hex(capabilities.deviceId, 4)}, driver ${capabilities.driverVersion}, memory $memoryReporting)';
	}

	override function getRendererName() {
		if( capabilities == null )
			return "Vulkan";

		final version = capabilities.apiVersion;
		return 'Vulkan ${version >>> 22}.${(version >>> 12) & 0x3FF}.${version & 0xFFF}';
	}

	override function getMemoryUsage() {
		if( ctx == null || allocator == null )
			return null;
		var total = 0.;
		var allocated = 0.;
		final hasBudget = ctx.hasMemoryBudget();
		for( index in 0...ctx.getMemoryHeapCount() ) {
			if( (ctx.getMemoryHeapFlags(index) & 1) == 0 )
				continue;
			if( hasBudget ) {
				final info = new VkMemoryHeapBudgetInfo();
				ctx.getMemoryHeapBudget(index, info);
				total += Math.int64ToFloat((info.budget : haxe.Int64));
				allocated += Math.int64ToFloat((info.usage : haxe.Int64));
			} else {
				total += Math.int64ToFloat((ctx.getMemoryHeapSize(index) : haxe.Int64));
				allocated += Math.int64ToFloat(allocator.getReservedBytesForHeap(index));
			}
		}
		return { total : total, allocated : allocated, free : total > allocated ? total - allocated : 0. };
	}

	override function capturePixels(tex:h3d.mat.Texture, layer:Int, mipLevel:Int, ?region:h2d.col.IBounds):hxd.Pixels {
		if (!frameStarted)
			throw "Vulkan texture capture requires an active frame";
		final image:VulkanTexture = tex.t;
		if (image == null || image.disposed)
			throw 'Texture ${tex.id} is not allocated';
		if (mipLevel < 0 || mipLevel >= image.mipCount)
			throw 'Texture ${tex.id} capture mip $mipLevel is outside 0...${image.mipCount - 1}';
		if (layer < 0 || layer >= image.layerCount)
			throw 'Texture ${tex.id} capture layer $layer is outside 0...${image.layerCount - 1}';
		if (!image.usage.has(TRANSFER_SRC))
			throw 'Texture ${tex.id} was not created with Vulkan transfer-source usage required for capture';
		final mapping = VulkanTextureFormat.resolve(tex.format);
		final properties = new VkFormatProperties();
		ctx.getPdeviceFormatProps(image.format, properties);
		if (!mapping.capabilities(properties).transferSource)
			throw 'Texture ${tex.id} format ${tex.format} does not support Vulkan transfer-source capture';
		if (tex.format.match(Depth24 | Depth24Stencil8 | Depth32Stencil8))
			throw 'Texture ${tex.id} format ${tex.format} has no exact hxd.Pixels depth readback representation';
		final mipWidth = hxd.Math.imax(1, tex.width >> mipLevel);
		final mipHeight = hxd.Math.imax(1, tex.height >> mipLevel);
		var x = 0;
		var y = 0;
		var width = mipWidth;
		var height = mipHeight;
		if (region != null) {
			final left = hxd.Math.imax(0, hxd.Math.imin(tex.width, region.xMin));
			final top = hxd.Math.imax(0, hxd.Math.imin(tex.height, region.yMin));
			final right = hxd.Math.imax(0, hxd.Math.imin(tex.width, region.xMax));
			final bottom = hxd.Math.imax(0, hxd.Math.imin(tex.height, region.yMax));
			if (right <= left || bottom <= top)
				throw 'Texture ${tex.id} capture region is empty after clipping';
			x = left;
			y = top;
			if (x >= mipWidth || y >= mipHeight)
				throw 'Texture ${tex.id} capture region is outside mip $mipLevel extent ${mipWidth}x$mipHeight after clipping';
			width = hxd.Math.imax(1, (right - left) >> mipLevel);
			height = hxd.Math.imax(1, (bottom - top) >> mipLevel);
			width = hxd.Math.imin(width, mipWidth - x);
			height = hxd.Math.imin(height, mipHeight - y);
		}
		mapping.validateReadbackRegion(x, y, width, height, mipWidth, mipHeight);
		final byteSize = haxe.Int64.ofInt(Std.int((width + mapping.blockWidth - 1) / mapping.blockWidth))
			* haxe.Int64.ofInt(Std.int((height + mapping.blockHeight - 1) / mapping.blockHeight)) * haxe.Int64.ofInt(mapping.bytesPerBlock);
		if (byteSize <= 0 || byteSize > haxe.Int64.ofInt(0x7FFFFFFF))
			throw 'Texture ${tex.id} capture byte size $byteSize is outside the supported CPU range';
		final pixels = hxd.Pixels.alloc(width, height, tex.format);
		if (pixels.dataSize != haxe.Int64.toInt(byteSize))
			throw 'Texture ${tex.id} format ${tex.format} requires conversion not supported by Vulkan capture';
		var aspect = new haxe.EnumFlags<VkImageAspectFlag>();
		aspect.set(tex.isDepth() ? DEPTH : COLOR);
		captureImageSynchronous(image.image, image, aspect, mipLevel, layer, x, y, width, height, image.format, tex.format,
			mapping.blockWidth, mapping.blockHeight, mapping.bytesPerBlock, pixels);
		if (tex.format == ARGB)
			convertBgraReadbackToArgb(pixels);
		return pixels;
	}

	override function captureRenderBuffer(pixels:hxd.Pixels) {
		if (!frameStarted || currentTargetSet == null || currentTargetSet.colors.length == 0)
			throw "Vulkan render-buffer capture requires an active color target";
		final color = currentTargetSet.colors[0];
		if (pixels.width != currentTargetSet.width || pixels.height != currentTargetSet.height)
			throw 'Vulkan render-buffer capture requires ${currentTargetSet.width}x${currentTargetSet.height} pixels, got ${pixels.width}x${pixels.height}';
		if (color.texture != null) {
			final captured = capturePixels(color.texture, color.layer, color.mipLevel);
			pixels.blit(0, 0, captured, 0, 0, captured.width, captured.height);
			captured.dispose();
			return;
		}
		if (!swapchainTransferSource)
			throw "The current Vulkan surface does not support transfer-source swapchain capture";
		beginRendering();
		suspendRendering();
		final swapchain = outImages[currentImageIndex];
		final oldLayout = swapchain.colorLayout;
		VulkanResourceState.recordBarrier();
		command.imageBarrier2(swapchain.img, color.aspect, 0, 1, 0, 1, oldLayout, TRANSFER_SRC_OPTIMAL,
			VkPipelineStage2.COLOR_ATTACHMENT_OUTPUT, VkAccess2.COLOR_ATTACHMENT_WRITE, VkPipelineStage2.COPY, VkAccess2.TRANSFER_READ);
		swapchain.colorLayout = TRANSFER_SRC_OPTIMAL;
		final nativeFormat = VulkanTextureFormat.heapsFormat(outImageFormat);
		final raw = hxd.Pixels.alloc(currentTargetSet.width, currentTargetSet.height, nativeFormat);
		captureImageSynchronous(swapchain.img, null, color.aspect, 0, 0, 0, 0, raw.width, raw.height, outImageFormat, nativeFormat,
			1, 1, 4, raw, oldLayout);
		raw.convert(pixels.format);
		pixels.blit(0, 0, raw, 0, 0, raw.width, raw.height);
		raw.dispose();
	}

	function captureImageSynchronous(source:limen.graphics.vulkan.memory.Memory.VkImage, resource:VulkanTexture,
		aspect:haxe.EnumFlags<VkImageAspectFlag>, mipLevel:Int, layer:Int, x:Int, y:Int, width:Int, height:Int,
		vulkanFormat:VkFormat, heapsFormat:hxd.PixelFormat, blockWidth:Int, blockHeight:Int, bytesPerBlock:Int, pixels:hxd.Pixels,
		rawRestoreLayout:VkImageLayout = UNDEFINED) {
		if (activeQueryIntervals != 0)
			throw "Cannot synchronously capture Vulkan pixels while a query interval is active";
		final savedTarget = currentTargetSet;
		if (resource != null) {
			var active = false;
			for (attachment in currentTargetSet.colors)
				active = active || attachment.overlaps(resource, mipLevel, 1, layer, 1);
			if (currentTargetSet.depth != null)
				active = active || currentTargetSet.depth.overlaps(resource, mipLevel, 1, layer, 1);
			if (active)
				beginRendering();
			suspendRendering();
		}
		final previousState = resource == null ? null : resource.getState(mipLevel, layer, aspect.has(COLOR) ? COLOR : DEPTH);
		if (previousState == Undefined)
			throw "Cannot capture an undefined Vulkan image subresource";
		if (resource != null)
			VulkanResourceState.transitionImage(command, resource, mipLevel, layer, TransferSource, aspect);
		final rowStride = Std.int((width + blockWidth - 1) / blockWidth) * bytesPerBlock;
		final submittedFrame = currentFrameIndex;
		final request = new VulkanImageReadbackRequest(source, resource, aspect, mipLevel, layer, x, y, width, height,
			vulkanFormat, heapsFormat, blockWidth, blockHeight, bytesPerBlock, @:privateAccess pixels.bytes.b, pixels.offset,
			rowStride, currentSubmissionSerial, null);
		readbackManager.requestImage(command, submittedFrame, request);
		if (resource != null)
			VulkanResourceState.transitionImage(command, resource, mipLevel, layer, previousState, aspect);
		else {
			VulkanResourceState.recordBarrier();
			command.imageBarrier2(source, aspect, 0, 1, 0, 1, TRANSFER_SRC_OPTIMAL, rawRestoreLayout,
				VkPipelineStage2.COPY, VkAccess2.TRANSFER_READ, VkPipelineStage2.COLOR_ATTACHMENT_OUTPUT, VkAccess2.COLOR_ATTACHMENT_WRITE);
			outImages[currentImageIndex].colorLayout = rawRestoreLayout;
		}
		if (resource != null)
			resource.lastSubmission = currentSubmissionSerial;
		endFrame();
		submit();
		if (ctx.waitForFence(frames[submittedFrame].fence, -1) != 0)
			throw Runtime.error("Failed to wait for synchronous Vulkan image readback");
		completedSubmissionSerial = hxd.Math.imax(completedSubmissionSerial, frames[submittedFrame].submissionSerial);
		deferredDestroy.collect(completedSubmissionSerial);
		readbackManager.completeFrame(submittedFrame);
		if (swapchainReady)
			beginFrame();
		if (savedTarget != null && !savedTarget.isDefault)
			changeTarget(savedTarget);
	}

	function convertBgraReadbackToArgb(pixels:hxd.Pixels) {
		for (index in 0...pixels.width * pixels.height) {
			final offset = pixels.offset + index * 4;
			final blue = pixels.bytes.get(offset);
			final green = pixels.bytes.get(offset + 1);
			final red = pixels.bytes.get(offset + 2);
			final alpha = pixels.bytes.get(offset + 3);
			pixels.bytes.set(offset, alpha);
			pixels.bytes.set(offset + 1, red);
			pixels.bytes.set(offset + 2, green);
			pixels.bytes.set(offset + 3, blue);
		}
	}

	override function present() {
		if( disposed )
			return;
		if( !frameStarted ) {
			var restoreWindow = hxd.Window.getInstance();
			if( !swapchainReady && !recreateSwapchain(restoreWindow.width, restoreWindow.height) )
				return;
			if( !beginFrame() )
				return;
		}
		endFrame();
		submit();
		var window = hxd.Window.getInstance();
		if( recreatePending || window.vsync != swapchainVsync )
			recreateSwapchain(window.width, window.height);
		if( swapchainReady )
			beginFrame();
	}

	override function resize( width : Int, height : Int ) {
		if( disposed )
			return;
		if( frameStarted ) {
			endFrame();
			submit();
		}
		if( recreateSwapchain(width, height) )
			beginFrame();
	}

	function applyViewport() {
		command.setViewport1(0, 0., 0., viewportWidth, viewportHeight, 0., 1.);
	}

	function applyScissor() {
		command.setScissor1(0, renderZoneX, renderZoneY, renderZoneWidth, renderZoneHeight);
	}

	override function setRenderZone( x : Int, y : Int, width : Int, height : Int ) {
		if( x == 0 && y == 0 && width < 0 && height < 0 ) {
			x = 0;
			y = 0;
			width = viewportWidth;
			height = viewportHeight;
		} else if( width < 0 || height < 0 )
			throw "Vulkan render-zone width and height must be non-negative";
		final right = hxd.Math.imin(viewportWidth, x + width);
		final bottom = hxd.Math.imin(viewportHeight, y + height);
		renderZoneX = hxd.Math.imax(0, hxd.Math.imin(viewportWidth, x));
		renderZoneY = hxd.Math.imax(0, hxd.Math.imin(viewportHeight, y));
		renderZoneWidth = hxd.Math.imax(0, right - renderZoneX);
		renderZoneHeight = hxd.Math.imax(0, bottom - renderZoneY);
		if( renderingStarted )
			applyScissor();
	}

	override function setRenderFlag(flag:RenderFlag, value:Int) {
		switch( flag ) {
		case CameraHandness:
			rightHanded = value != 0;
		}
	}

	override function setDepthClamp(enabled:Bool) {
		if( enabled && !capabilities.depthClamp )
			throw "Vulkan depth clamp is not supported by this device";
		driverDepthClamp = enabled;
	}

	override function setDepthBias(depthBias:Float, slopeScaledBias:Float) {
		this.depthBias = depthBias;
		this.slopeScaledDepthBias = slopeScaledBias;
	}

	function submit() {
		var frame = frames[currentFrameIndex];
		var image = outImages[currentImageIndex];
		if( ctx.submitFrame(frame.command, frame.imageAvailableConsumed ? null : frame.imageAvailable, image.renderFinished, frame.fence) != 0 )
			throw Runtime.error("Failed to submit Vulkan frame");
		frame.imageAvailableConsumed = true;
		frame.submissionSerial = currentSubmissionSerial++;
		queryManager.submitted(currentFrameIndex, frame.submissionSerial);
		var presentStatus = ctx.present(image.renderFinished, currentImageIndex);
		if( presentStatus != Success && presentStatus != Suboptimal && presentStatus != OutOfDate )
			throw Runtime.error('Failed to present Vulkan frame (status $presentStatus)');
		image.initialized = true;
		recreatePending = presentStatus == Suboptimal || presentStatus == OutOfDate;
		currentFrameIndex++;
		currentFrameIndex %= frames.length;
	}

	override function init( onCreate : Bool -> Void, forceSoftware = false ) {
		onCreate(false);
	}

	override function selectShader( shader : hxsl.RuntimeShader ) {
		if( currentShader != null && currentShader.shader == shader )
			return false;
		final knownKey = shaderKeys.get(shader.id);
		var p = knownKey == null ? null : programs.get(knownKey);
		if( p == null ) {
			if( shader.hasBindless() && bindlessDescriptors == null )
				throw 'Vulkan bindless shader requires descriptor indexing support; ${capabilities.diagnostics}';
			final abi = bindlessDescriptors == null
				? new VulkanShaderAbi(shader)
				: new VulkanShaderAbi(shader, bindlessDescriptors.imageCapacity, bindlessDescriptors.samplerCapacity,
					bindlessDescriptors.bufferCapacity);
			abi.validateDeviceLimits(limits);
			validateRuntimeDescriptorLimits(abi);
			validateComputeShaderLimits(shader);
			final data = shaderCompiler.compile(shader, abi);
			validateCompiledShaderLimits(data, shader);
			p = programs.get(data.cacheKey);
			if( p == null ) {
				p = compileShader(shader, abi, data);
				programs.set(data.cacheKey, p);
			}
			shaderKeys.set(shader.id, data.cacheKey);
		}
		if( p.compute != null && !capabilities.graphicsQueueCompute )
			throw 'Vulkan compute is unavailable because graphics queue family ${capabilities.graphicsQueueFamily} lacks VK_QUEUE_COMPUTE_BIT; ${capabilities.diagnostics}';
		currentShader = p;
		textureBindings.clear();
		textureBindingsShaderKey = p.cacheKey;
		bufferBindings.clear();
		bufferBindingKinds.clear();
		bufferBindingsShaderKey = p.cacheKey;
		if( p.compute != null ) {
			boundComputePipeline = null;
			boundComputeDescriptorState = null;
		} else {
			currentVertexLayout = null;
			currentVertexBuffers.resize(0);
			boundPipeline = null;
			boundDescriptorState = null;
		}
		return true;
	}

	function validateComputeShaderLimits(shader:hxsl.RuntimeShader) {
		if( shader.mode != hxsl.RuntimeShader.LinkMode.Compute )
			return;
		var localSizeX = 1;
		var localSizeY = 1;
		var localSizeZ = 1;
		function collect(expression:hxsl.Ast.TExpr) {
			switch( expression.e ) {
			case TCall({e: TGlobal(SetLayout)}, [{e: TConst(CInt(x))}, {e: TConst(CInt(y))}, {e: TConst(CInt(z))}]):
				localSizeX = x;
				localSizeY = y;
				localSizeZ = z;
			case TCall({e: TGlobal(SetLayout)}, [{e: TConst(CInt(x))}, {e: TConst(CInt(y))}]):
				localSizeX = x;
				localSizeY = y;
				localSizeZ = 1;
			case TCall({e: TGlobal(SetLayout)}, [{e: TConst(CInt(x))}]):
				localSizeX = x;
				localSizeY = 1;
				localSizeZ = 1;
			default:
				hxsl.Ast.Tools.iter(expression, collect);
			}
		}
		for( functionData in shader.compute.data.funs )
			collect(functionData.expr);
		validateComputeWorkgroupLimits(localSizeX, localSizeY, localSizeZ, computeSharedMemoryBytes(shader));
	}

	function validateComputeWorkgroupLimits(x:Int, y:Int, z:Int, sharedMemoryBytes:Int) {
		if( x <= 0 || y <= 0 || z <= 0 )
			throw 'Compute shader local size must be positive, got ${x}x${y}x${z}';
		if( x > limits.maxComputeWorkGroupSize || y > limits.maxComputeWorkGroupSize1 || z > limits.maxComputeWorkGroupSize2 )
			throw 'Compute shader local size ${x}x${y}x${z} exceeds device limits '
				+ '${limits.maxComputeWorkGroupSize}x${limits.maxComputeWorkGroupSize1}x${limits.maxComputeWorkGroupSize2}';
		final invocations = haxe.Int64.ofInt(x) * haxe.Int64.ofInt(y) * haxe.Int64.ofInt(z);
		if( invocations > haxe.Int64.ofInt(limits.maxComputeWorkGroupInvocations) )
			throw 'Compute shader local size ${x}x${y}x${z} uses $invocations invocations, device limit is ${limits.maxComputeWorkGroupInvocations}';
		if( sharedMemoryBytes > limits.maxComputeSharedMemorySize )
			throw 'Compute shader requires $sharedMemoryBytes bytes of shared workgroup memory, device limit is ${limits.maxComputeSharedMemorySize}';
	}

	function computeSharedMemoryBytes(shader:hxsl.RuntimeShader):Int {
		var sharedMemoryBytes = 0;
		for( variable in shader.compute.data.vars )
			if( variable.kind == hxsl.Ast.VarKind.Local && hxsl.Ast.Tools.hasQualifier(variable, hxsl.Ast.VarQualifier.Shared) )
				sharedMemoryBytes += hxsl.Ast.Tools.size(variable.type) * 4;
		return sharedMemoryBytes;
	}

	function validateRuntimeDescriptorLimits(abi:VulkanShaderAbi) {
		final dynamicUniformLimit = limits.maxDescriptorSetUniformBuffersDynamic;
		if( dynamicUniformLimit >= 0 && abi.constantBlocks.length > dynamicUniformLimit )
			throw 'Shader ABI requires ${abi.constantBlocks.length} dynamic uniform descriptors, device limit is $dynamicUniformLimit';
		for( block in abi.constantBlocks )
			if( limits.maxUniformBufferRange >= 0 && block.size > limits.maxUniformBufferRange )
				throw 'Constant block ${block.name} requires ${block.size} bytes, maxUniformBufferRange is ${limits.maxUniformBufferRange}';
	}

	function validateCompiledShaderLimits(data:VulkanCompiledProgramData, shader:hxsl.RuntimeShader) {
		for( stage in data.stages )
			if( stage.stage == VulkanShaderStage.Compute ) {
				final size = stage.reflection.localSize;
				validateComputeWorkgroupLimits(size.x, size.y, size.z, computeSharedMemoryBytes(shader));
			}
	}

static var STAGE_NAME = @:privateAccess "main".toUtf8();

	@:generic inline function makeRef<T>( v : T ) : ArrayStruct<T> {
		return Vulkan.makeRef(v);
	}

	@:generic inline function makeArray<T>( a : Array<T>, keepInMemory=true ) {
		var n = new hl.NativeArray<T>(a.length);
		for( i in 0...a.length ) {
			n[i] = a[i];
			if( keepInMemory ) savedPointers.push(a[i]);
		}
		return Vulkan.makeArray(n);
	}

	function compileShader(shader:hxsl.RuntimeShader, abi:VulkanShaderAbi, data:VulkanCompiledProgramData):VulkanCompiledShader {
		var vertex:VulkanShaderStageData = null;
		var fragment:VulkanShaderStageData = null;
		var compute:VulkanShaderStageData = null;
		final modules = [];
		final pipelineStages = [];
		try {
			for( source in data.stages ) {
				final stageName = VulkanShaderAbi.stageName(source.stage).toLowerCase();
				final module = new ShaderModule(ctx, source.spirv, 'hxsl-${data.cacheKey.substr(0, 16)}-$stageName');
				final stageData = new VulkanShaderStageData(source.stage, source, module);
				modules.push(stageData);
				switch( source.stage ) {
				case VulkanShaderStage.Vertex: vertex = stageData;
				case VulkanShaderStage.Fragment: fragment = stageData;
				case VulkanShaderStage.Compute: compute = stageData;
				default: throw 'Unsupported compiled Vulkan stage ${source.stage}';
				}
				final pipelineStage = new VkPipelineShaderStage();
				pipelineStage.module = module.handle;
				pipelineStage.name = STAGE_NAME;
				switch( source.stage ) {
				case VulkanShaderStage.Vertex: pipelineStage.stage.set(VkShaderStageFlag.VERTEX);
				case VulkanShaderStage.Fragment: pipelineStage.stage.set(VkShaderStageFlag.FRAGMENT);
				case VulkanShaderStage.Compute: pipelineStage.stage.set(VkShaderStageFlag.COMPUTE);
				default:
				}
				pipelineStages.push(pipelineStage);
			}

			final layout = pipelineLayoutCache.acquire(abi);
			return new VulkanCompiledShader(shader, data.cacheKey, abi, vertex, fragment, compute, makeArray(pipelineStages), layout.descriptorSetLayouts,
				layout.layout, layout.signature);
		} catch( error:Dynamic ) {
			for( module in modules ) module.dispose();
			throw error;
		}
	}

	override function begin(frame:Int) {
	}

	var tmpClearRect = new VkClearRect();

	override function clear(?color:Vector4, ?depth:Float, ?stencil:Int) {
		if( !renderingStarted ) {
			if( color != null )
				pendingClearColor = new Vector4(color.r, color.g, color.b, color.a);
			if( depth != null )
				pendingClearDepth = depth;
			if( stencil != null )
				pendingClearStencil = stencil;
			return;
		}
		clearNow(color, depth, stencil);
	}

	function clearNow(color:Vector4, depth:Null<Float>, stencil:Null<Int>) {
		var rect = tmpClearRect;
		if( color != null && currentTargetSet.colors.length > 0 )
			clearColorAttachments([for( index in 0...currentTargetSet.colors.length ) index], color);
		if( (depth != null || stencil != null) && currentTargetSet.depth != null ) {
			final clear = new VkClearAttachment();
			clear.aspectMask = new haxe.EnumFlags();
			if( depth != null ) {
				clear.aspectMask.set(DEPTH);
				clear.depth = depth;
			}
			if( stencil != null && currentTargetSet.stencil != null ) {
				clear.aspectMask.set(STENCIL);
				clear.stencil = stencil;
			}
			rect.extendX = viewportWidth;
			rect.extendY = viewportHeight;
			rect.layerCount = 1;
			command.clearAttachments(1, makeRef(clear), 1, makeRef(rect));
		}
	}

	function clearColorAttachments(indices:Array<Int>, color:Vector4) {
		if( indices.length == 0 )
			return;
		if( clearAttachmentScratch.length < indices.length * 6 ) clearAttachmentScratch = new hl.NativeArray<Int>(indices.length * 6);
		for( i in 0...indices.length ) {
			final base = i * 6;
			clearAttachmentScratch[base] = 1;
			clearAttachmentScratch[base + 1] = indices[i];
			clearAttachmentScratch[base + 2] = haxe.io.FPHelper.floatToI32(color.r);
			clearAttachmentScratch[base + 3] = haxe.io.FPHelper.floatToI32(color.g);
			clearAttachmentScratch[base + 4] = haxe.io.FPHelper.floatToI32(color.b);
			clearAttachmentScratch[base + 5] = haxe.io.FPHelper.floatToI32(color.a);
		}
		clearRectScratch[0] = 0;
		clearRectScratch[1] = 0;
		clearRectScratch[2] = viewportWidth;
		clearRectScratch[3] = viewportHeight;
		clearRectScratch[4] = 0;
		clearRectScratch[5] = 1;
		command.clearAttachmentsNative(indices.length, clearAttachmentScratch, 1, clearRectScratch);
	}

	function resolveDefaultTarget(depthBinding:h3d.Engine.DepthBinding):VulkanRenderingTargetSet {
		final swapchain = outImages[currentImageIndex];
		if( swapchain.defaultDepthTexture != defaultDepthBuffer ) {
			swapchain.defaultTargets = [];
			swapchain.defaultDepthTexture = defaultDepthBuffer;
		}
		final index = Type.enumIndex(depthBinding);
		final cached = swapchain.defaultTargets[index];
		if( cached != null ) return cached;
		var colorAspect = new haxe.EnumFlags<VkImageAspectFlag>();
		colorAspect.set(COLOR);
		final colors = depthBinding == DepthOnly ? [] : [new VulkanRenderingAttachment(null, null, swapchain.img, swapchain.view,
			outImageFormat, colorAspect, 0, 0)];
		var depth:VulkanRenderingAttachment = null;
		if( depthBinding != NotBound ) {
			final resource = swapchain.depthResource;
			depth = new VulkanRenderingAttachment(defaultDepthBuffer, resource, resource.image, resource.view, resource.format,
				resource.aspect, 0, 0);
		}
		final target = new VulkanRenderingTargetSet(colors, depth, depth != null && formatHasStencil(depth.format) ? depth : null,
			swapchain.depthResource.width, swapchain.depthResource.height, 1, depthBinding, true,
			'default:$currentImageIndex:${Type.enumIndex(depthBinding)}');
		swapchain.defaultTargets[index] = target;
		return target;
	}

	function resolveTextureAttachment(texture:h3d.mat.Texture, mipLevel:Int, layer:Int, depth:Bool):VulkanRenderingAttachment {
		if( texture == null )
			throw "Vulkan attachment texture must not be null";
		if( texture.t == null )
			@:privateAccess texture.alloc();
		final image:VulkanTexture = texture.t;
		if( image == null || image.disposed )
			throw 'Vulkan attachment texture ${texture.id} is not allocated';
		if( texture.isDepth() != depth )
			throw depth ? 'Texture ${texture.id} is not a depth/stencil texture' : 'Texture ${texture.id} is not a color texture';
		if( !depth && !texture.flags.has(Target) )
			throw 'Texture ${texture.id} was not created with TextureFlags.Target';
		if( mipLevel < 0 || mipLevel >= image.mipCount )
			throw 'Texture ${texture.id} target mip $mipLevel is outside 0...${image.mipCount - 1}';
		if( layer < 0 || layer >= image.layerCount )
			throw 'Texture ${texture.id} target layer $layer is outside 0...${image.layerCount - 1}';
		if( depth ? !image.usage.has(DEPTH_STENCIL_ATTACHMENT) : !image.usage.has(COLOR_ATTACHMENT) )
			throw 'Texture ${texture.id} does not have Vulkan ${depth ? "depth/stencil" : "color"} attachment usage';
		final properties = new VkFormatProperties();
		ctx.getPdeviceFormatProps(image.format, properties);
		final feature:Int = cast (depth ? VkFormatFeature.DEPTH_STENCIL_ATTACHMENT : VkFormatFeature.COLOR_ATTACHMENT);
		if( (properties.optimalTilingFeatures & feature) == 0 )
			throw 'Texture ${texture.id} format ${texture.format} is not ${depth ? "depth/stencil" : "color"} renderable on this device';
		var aspect = new haxe.EnumFlags<VkImageAspectFlag>();
		aspect.set(depth ? DEPTH : COLOR);
		if( depth && texture.hasStencil() )
			aspect.set(STENCIL);
		final view = getImageView(texture, image, depth ? TYPE_2D : TYPE_2D, image.format, aspect, mipLevel, 1, layer, 1);
		image.lastSubmission = currentSubmissionSerial;
		@:privateAccess texture.lastFrame = currentSubmissionSerial;
		return new VulkanRenderingAttachment(texture, image, image.image, view.view, image.format, aspect, mipLevel, layer);
	}

	function resolveDepthAttachment(texture:h3d.mat.Texture, width:Int, height:Int, depthBinding:h3d.Engine.DepthBinding):VulkanRenderingAttachment {
		if( depthBinding == NotBound || texture == null )
			return null;
		final depth = resolveTextureAttachment(texture, 0, 0, true);
		if( texture.width != width || texture.height != height )
			throw 'Depth attachment ${texture.id} size ${texture.width}x${texture.height} does not match color target ${width}x$height';
		return depth;
	}

	function makeTextureTargetSet(textures:Array<h3d.mat.Texture>, mipLevel:Int, layer:Int, depthBinding:h3d.Engine.DepthBinding):VulkanRenderingTargetSet {
		if( textures == null || textures.length == 0 )
			throw "Vulkan MRT requires at least one color attachment";
		if( textures.length > limits.maxColorAttachments )
			throw 'Vulkan MRT requested ${textures.length} color attachments, device limit is ${limits.maxColorAttachments}';
		final resolved = [for( texture in textures ) resolveTextureAttachment(texture, mipLevel, layer, false)];
		final width = hxd.Math.imax(1, textures[0].width >> mipLevel);
		final height = hxd.Math.imax(1, textures[0].height >> mipLevel);
		for( index in 1...textures.length ) {
			final targetWidth = hxd.Math.imax(1, textures[index].width >> mipLevel);
			final targetHeight = hxd.Math.imax(1, textures[index].height >> mipLevel);
			if( targetWidth != width || targetHeight != height )
				throw 'Vulkan MRT attachment $index size ${targetWidth}x$targetHeight does not match attachment 0 size ${width}x$height';
			if( textures[index].depthBuffer != textures[0].depthBuffer )
				throw 'Vulkan MRT attachment $index depth association does not match attachment 0';
		}
		final depth = resolveDepthAttachment(textures[0].depthBuffer, width, height, depthBinding);
		final colors = depthBinding == DepthOnly ? [] : resolved;
		final keyParts = [for( color in colors ) '${color.resource.allocation.debugId}:${cast(color.format, Int)}:${color.mipLevel}:${color.layer}'];
		final depthKey = depth == null ? "none" : '${depth.resource.allocation.debugId}:${cast(depth.format, Int)}';
		return new VulkanRenderingTargetSet(colors, depth, depth != null && formatHasStencil(depth.format) ? depth : null,
			width, height, 1, depthBinding, false, '${keyParts.join(",")}|$depthKey:${Type.enumIndex(depthBinding)}');
	}

	function changeTarget(next:VulkanRenderingTargetSet) {
		if( currentTargetSet != null && currentTargetSet.key == next.key )
			return;
		if( currentTargetSet != null && (pendingClearColor != null || pendingClearDepth != null || pendingClearStencil != null
			|| pendingInitialColorClears.length > 0 || pendingInitialDepthClear) )
			beginRendering();
		suspendRendering();
		currentTargetSet = next;
		viewportWidth = next.width;
		viewportHeight = next.height;
		setRenderZone(0, 0, -1, -1);
		targetColorClears.resize(0);
		pendingInitialColorClears = targetColorClears;
		for( index => color in next.colors )
			if( color.texture != null && !color.texture.flags.has(WasCleared) ) {
				color.texture.flags.set(WasCleared);
				pendingInitialColorClears.push(index);
			}
		pendingInitialDepthClear = next.depth != null && next.depth.texture != defaultDepthBuffer && !next.depth.texture.flags.has(WasCleared);
		if( pendingInitialDepthClear )
			next.depth.texture.flags.set(WasCleared);
		boundPipeline = null;
		boundDescriptorState = null;
		boundDynamicState = false;
	}

	override function setRenderTarget(texture:Null<h3d.mat.Texture>, layer = 0, mipLevel = 0, depthBinding:h3d.Engine.DepthBinding = ReadWrite) {
		if( texture == null ) {
			if( layer != 0 || mipLevel != 0 )
				throw "Default Vulkan target only supports layer 0 and mip 0";
			changeTarget(resolveDefaultTarget(depthBinding));
			return;
		}
		changeTarget(makeTextureTargetSet([texture], mipLevel, layer, depthBinding));
	}

	override function setRenderTargets(textures:Array<h3d.mat.Texture>, depthBinding:h3d.Engine.DepthBinding = ReadWrite) {
		changeTarget(makeTextureTargetSet(textures, 0, 0, depthBinding));
	}

	override function setDepth(texture:Null<h3d.mat.Texture>, layer = 0) {
		if( texture == null )
			throw "Vulkan depth-only rendering requires a depth texture";
		final depth = resolveTextureAttachment(texture, 0, 0, true);
		final key = 'depth:${depth.resource.allocation.debugId}:${cast(depth.format, Int)}:${depth.layer}';
		changeTarget(new VulkanRenderingTargetSet([], depth, formatHasStencil(depth.format) ? depth : null,
			texture.width, texture.height, 1, DepthOnly, false, key));
	}

	override function allocDepthBuffer(texture:h3d.mat.Texture):Texture {
		texture.flags.set(Target);
		return allocTexture(texture);
	}

	override function disposeDepthBuffer(texture:h3d.mat.Texture) {
		disposeTexture(texture);
	}

	override function getDefaultDepthBuffer():h3d.mat.Texture {
		if( defaultDepthBuffer == null ) {
			final engine = h3d.Engine.getCurrent();
			if( engine != null )
				defaultDepthBuffer = new h3d.mat.Texture(0, 0, depthTextureFormat(depthFormat));
			else {
				defaultDepthBuffer = Type.createEmptyInstance(h3d.mat.Texture);
				var flags = new haxe.EnumFlags<h3d.mat.Data.TextureFlags>();
				flags.set(h3d.mat.Data.TextureFlags.NoAlloc);
				@:privateAccess {
					defaultDepthBuffer.id = -1;
					defaultDepthBuffer.flags = flags;
					defaultDepthBuffer.format = depthTextureFormat(depthFormat);
					defaultDepthBuffer.allocPos = hxd.impl.AllocPos.make();
				}
				defaultDepthBuffer.mipMap = h3d.mat.Data.MipMap.None;
				defaultDepthBuffer.filter = h3d.mat.Data.Filter.Nearest;
				defaultDepthBuffer.wrap = h3d.mat.Data.Wrap.Clamp;
				defaultDepthBuffer.lodBias = 0;
				defaultDepthBuffer.startingMip = 0;
				defaultDepthBuffer.anisotropicMaxLevel = 1;
			}
			defaultDepthBuffer.name = "defaultDepthBuffer";
			@:privateAccess {
				defaultDepthBuffer.width = viewportWidth;
				defaultDepthBuffer.height = viewportHeight;
			}
		}
		final engine = h3d.Engine.getCurrent();
		if( engine != null && @:privateAccess defaultDepthBuffer.mem == null )
			@:privateAccess defaultDepthBuffer.mem = engine.mem;
		if( currentImageIndex >= 0 && outImages != null )
			@:privateAccess defaultDepthBuffer.t = outImages[currentImageIndex].depthResource;
		return defaultDepthBuffer;
	}

	override function allocTexture( t : h3d.mat.Texture ) : Texture {
		final mapping = VulkanTextureFormat.resolve(t.format);
		final isDepth = t.isDepth();
		final formatProperties = new VkFormatProperties();
		ctx.getPdeviceFormatProps(mapping.format, formatProperties);
		final formatCapabilities = mapping.capabilities(formatProperties);
		final automaticMipmaps = t.mipLevels > 1 && !t.flags.has(ManualMipMapGen);
		final mipmapMode:VulkanMipmapMode = if (t.mipLevels <= 1) None else if (formatCapabilities.supportsLinearMipmapBlit()) LinearBlit
			else if (formatCapabilities.supportsGraphicsMipmapFallback()) Graphics else None;
		if (automaticMipmaps && mipmapMode == None)
			throw 'Texture format ${t.format} does not support automatic Vulkan mipmap generation; provide mip levels manually with ManualMipMapGen';
		final graphicsMipmapFallback = mipmapMode == Graphics;
		var inf = new VkImageCreateInfo();
		inf.imageType = TYPE_2D;
		inf.width = t.width;
		inf.height = t.height;
		inf.depth = 1;
		inf.arrayLayers = t.layerCount;
		inf.mipLevels = t.mipLevels;
		inf.tiling = OPTIMAL;
		inf.samples = 1;
		inf.format = mapping.format;
		if( t.flags.has(Cube) )
			inf.flags.set(CUBE_COMPATIBLE);
		inf.usage = VulkanTextureFormat.usage(t.flags, isDepth, graphicsMipmapFallback);
		final requiredFeatures = VulkanTextureFormat.requiredFeatures(t.flags, isDepth, graphicsMipmapFallback);
		if( !mapping.uploadCompatible || !mapping.sampledCompatible || (formatProperties.optimalTilingFeatures & requiredFeatures) != requiredFeatures )
			throw 'Texture format ${t.format} does not support Vulkan features 0x${StringTools.hex(requiredFeatures)} required by flags ${t.flags.toInt()}';

		var img = ctx.createImage(inf);
		if( img == null )
			throw Runtime.error('Failed to create Vulkan texture ${t.id}');
		final debugName = t.name == null ? 'texture-${t.id}' : 'texture-${t.id}-${t.name}';
		ctx.setImageName(img, @:privateAccess debugName.toUtf8());

		var requirements = new VkMemoryRequirementsInfo();
		ctx.getImageMemoryRequirements2(img, requirements);
		var deviceLocal = 1 << Type.enumIndex(VkMemoryPropertyFlag.DEVICE_LOCAL);
		var allocation = try allocator.allocate(requirements, DeviceImage, deviceLocal, deviceLocal, null, img, debugName) catch( error : Dynamic ) {
			ctx.destroyImage(img);
			throw error;
		};

		if( !ctx.bindImageMemory64(img, allocation.memory, (allocation.offset : hl.I64)) ) {
			allocation.dispose();
			ctx.destroyImage(img);
			throw Runtime.error('Failed to bind Vulkan texture ${t.id} memory');
		}

		var viewInfo = new VkImageViewCreateInfo();
		viewInfo.image = img;
		viewInfo.viewType = t.flags.has(Cube) ? TYPE_CUBE : t.flags.has(IsArray) ? TYPE_2D_ARRAY : TYPE_2D;
		viewInfo.format = inf.format;
		viewInfo.layerCount = t.layerCount;
		viewInfo.levelCount = t.mipLevels;
		if( isDepth ) {
			viewInfo.aspectMask.set(DEPTH);
			if( t.hasStencil() )
				viewInfo.aspectMask.set(STENCIL);
		} else
			viewInfo.aspectMask.set(COLOR);

		var view = ctx.createImageView(viewInfo);
		if( view == null ) {
			ctx.destroyImage(img);
			allocation.dispose();
			throw Runtime.error('Failed to create Vulkan texture ${t.id} view');
		}
		final viewName = '$debugName-view';
		ctx.setImageViewName(view, @:privateAccess viewName.toUtf8());

		var aspect = new haxe.EnumFlags<limen.graphics.vulkan.memory.Memory.VkImageAspectFlag>();
		if( isDepth ) {
			aspect.set(DEPTH);
			if( t.hasStencil() )
				aspect.set(STENCIL);
		} else
			aspect.set(COLOR);
		var texture = new VulkanTexture(img, view, allocation, requirements.size, inf.format, inf.width, inf.height, inf.depth, inf.mipLevels, inf.arrayLayers,
			aspect, inf.usage, mapping.supportsLinearFiltering(formatProperties), mipmapMode, t.id, debugName);
		liveTextures.push(texture);
		return texture;
	}

	override function disposeTexture( t : h3d.mat.Texture ) {
		if( t.t == null )
			return;
		final texture:VulkanTexture = t.t;
		if( t.realloc == null ) {
			final handles = textureHandles.get(t);
			if( handles != null )
				for( handle in handles )
					@:privateAccess handle.handle = -1;
			textureHandles.remove(t);
			final slots = textureImageSlots.get(t);
			if( slots != null )
				for( slot in slots ) {
					final release = () -> {
						if( bindlessDescriptors != null )
							bindlessDescriptors.releaseImage(slot.index);
						if( slot.index < bindlessTextureSlots.length )
							bindlessTextureSlots[slot.index] = null;
					};
					if( texture.lastSubmission <= completedSubmissionSerial ) release() else deferredDestroy.retire(texture.lastSubmission, release);
				}
			textureImageSlots.remove(t);
		}
		destroyTextureResource(texture);
		t.t = null;
	}

	function destroyTextureResource(texture:VulkanTexture, immediate = false) {
		if( texture.disposed )
			return;
		liveTextures.remove(texture);
		@:privateAccess texture.markDisposed();
		final destroy = () -> {
			@:privateAccess texture.destroyViews(ctx.destroyImageView);
			ctx.destroyImage(texture.image);
			texture.allocation.dispose();
		};
		if( immediate || texture.lastSubmission <= completedSubmissionSerial )
			destroy();
		else
			deferredDestroy.retire(texture.lastSubmission, destroy);
	}

	override function uploadTextureBitmap( t : h3d.mat.Texture, bmp : hxd.BitmapData, mipLevel : Int, layer : Int ) {
		var pixels = bmp.getPixels();
		uploadTexturePixels(t, pixels, mipLevel, layer);
		pixels.dispose();
	}

	override function uploadTexturePixels(t:h3d.mat.Texture, pixels:hxd.Pixels, mipLevel:Int, layer:Int) {
		if( mipLevel < 0 || mipLevel >= t.mipLevels )
			throw 'Mip level $mipLevel is outside texture ${t.id} range 0...${t.mipLevels - 1}';
		var width = t.width >> mipLevel;
		var height = t.height >> mipLevel;
		if( width == 0 ) width = 1;
		if( height == 0 ) height = 1;
		if( pixels.width != width || pixels.height != height )
			throw 'Texture ${t.id} mip $mipLevel upload requires ${width}x$height, got ${pixels.width}x${pixels.height}';
		uploadTextureRegion(t, pixels, 0, 0, mipLevel, layer);
	}

	override function generateMipMaps(t:h3d.mat.Texture) {
		if (!frameStarted)
			throw "Vulkan mipmap generation requires an active frame";
		final texture:VulkanTexture = t.t;
		if (texture == null || texture.disposed)
			throw 'Texture ${t.id} is not allocated';
		if (texture.mipCount <= 1)
			return;
		if (texture.depth != 1)
			throw 'Automatic Vulkan mipmap generation for 3D texture ${t.id} is not supported';
		if (!texture.hasCompleteBaseUploads() && !t.flags.has(Target))
			throw 'Texture ${t.id} automatic mipmap generation requires a complete base-level upload for every layer';
		if (!t.flags.has(ManualMipMapGen) && texture.hasExplicitMipUploads())
			throw 'Texture ${t.id} has explicitly uploaded mip levels; automatic Vulkan mipmap generation would overwrite them';
		if (currentTargetSet != null) {
			var baseLevelActive = false;
			for (attachment in currentTargetSet.colors)
				baseLevelActive = baseLevelActive || attachment.overlaps(texture, 0, 1, 0, texture.layerCount);
			if (baseLevelActive)
				beginRendering();
		}
		suspendRendering();
		switch (texture.mipmapMode) {
		case LinearBlit:
			generateMipMapsWithBlits(texture);
		case Graphics:
			generateMipMapsWithGraphics(t, texture);
		case None:
			throw 'Texture format ${t.format} does not support automatic Vulkan mipmap generation';
		}
		texture.lastSubmission = currentSubmissionSerial;
		@:privateAccess t.lastFrame = currentSubmissionSerial;
	}

	function generateMipMapsWithBlits(texture:VulkanTexture) {
		for (layer in 0...texture.layerCount) {
			for (mip in 1...texture.mipCount) {
				VulkanResourceState.transitionImage(command, texture, mip - 1, layer, TransferSource);
				VulkanResourceState.transitionImage(command, texture, mip, layer, TransferDestination);
				final region = new VkImageBlitRegion();
				region.aspectMask.set(COLOR);
				region.srcMipLevel = mip - 1;
				region.srcBaseArrayLayer = layer;
				region.srcLayerCount = 1;
				region.srcX1 = hxd.Math.imax(1, texture.width >> (mip - 1));
				region.srcY1 = hxd.Math.imax(1, texture.height >> (mip - 1));
				region.srcZ1 = 1;
				region.dstMipLevel = mip;
				region.dstBaseArrayLayer = layer;
				region.dstLayerCount = 1;
				region.dstX1 = hxd.Math.imax(1, texture.width >> mip);
				region.dstY1 = hxd.Math.imax(1, texture.height >> mip);
				region.dstZ1 = 1;
				command.blitImage2(texture.image, TRANSFER_SRC_OPTIMAL, texture.image, TRANSFER_DST_OPTIMAL, VkFilter.LINEAR, 1, makeRef(region));
			}
			for (mip in 0...texture.mipCount)
				VulkanResourceState.transitionImage(command, texture, mip, layer, ShaderRead);
		}
	}

	function generateMipMapsWithGraphics(t:h3d.mat.Texture, texture:VulkanTexture) {
		final savedTarget = currentTargetSet;
		final savedShader = currentShader;
		final savedVertexLayout = currentVertexLayout;
		final savedVertexBuffers = currentVertexBuffers.copy();
		final savedBlendState = currentBlendState;
		currentBlendState = null;
		final savedCullMode = currentCullMode;
		final savedDepthTest = currentDepthTest;
		final savedDepthWrite = currentDepthWrite;
		final savedDepthCompare = currentDepthCompare;
		final savedDepthClamp = currentDepthClamp;
		final savedWireframe = currentWireframe;
		final savedColorMasks = currentColorMasks;
		final savedStencilState = currentStencilState;
		currentStencilState = null;
		final savedMaterialSelected = materialSelected;
		final savedTextureBindings = [for (key => value in textureBindings) {key: key, value: value}];
		final savedTextureBindingsShaderKey = textureBindingsShaderKey;
		final savedStartingMip = t.startingMip;
		final savedMipMap = t.mipMap;
		final savedSlice = t.slice;
		var failure:Dynamic = null;
		try {
			ensureMipmapGraphicsResources();
			for (layer in 0...texture.layerCount)
				for (mip in 1...texture.mipCount) {
					t.startingMip = mip - 1;
					t.mipMap = None;
					t.slice = layer + 1;
					changeTarget(makeTextureTargetSet([t], mip, layer, NotBound));
					selectShader(mipmapShader);
					selectMaterial(mipmapPass);
					selectBuffer(mipmapVertex);
					final buffers = new h3d.shader.Buffers();
					buffers.grow(mipmapShader);
					for (index in 0...buffers.vertex.tex.length) buffers.vertex.tex[index] = t;
					for (index in 0...buffers.fragment.tex.length) buffers.fragment.tex[index] = t;
					uploadShaderBuffers(buffers, h3d.shader.Buffers.BufferKind.Textures);
					draw(mipmapIndex, 0, 2);
				}
			suspendRendering();
			for (layer in 0...texture.layerCount)
				for (mip in 0...texture.mipCount)
					VulkanResourceState.transitionImage(command, texture, mip, layer, ShaderRead);
		} catch (error:Dynamic) {
			failure = error;
		}
		t.startingMip = savedStartingMip;
		t.mipMap = savedMipMap;
		t.slice = savedSlice;
		if (currentTargetSet != savedTarget) {
			suspendRendering();
			currentTargetSet = savedTarget;
			viewportWidth = savedTarget.width;
			viewportHeight = savedTarget.height;
			setRenderZone(0, 0, -1, -1);
		}
		currentShader = savedShader;
		currentVertexLayout = savedVertexLayout;
		currentVertexBuffers = savedVertexBuffers;
		currentBlendState = savedBlendState;
		currentCullMode = savedCullMode;
		currentDepthTest = savedDepthTest;
		currentDepthWrite = savedDepthWrite;
		currentDepthCompare = savedDepthCompare;
		currentDepthClamp = savedDepthClamp;
		currentWireframe = savedWireframe;
		currentColorMasks = savedColorMasks;
		currentStencilState = savedStencilState;
		materialSelected = savedMaterialSelected;
		textureBindings.clear();
		for (binding in savedTextureBindings) textureBindings.set(binding.key, binding.value);
		textureBindingsShaderKey = savedTextureBindingsShaderKey;
		boundPipeline = null;
		boundDescriptorState = null;
		boundDynamicState = false;
		if (failure != null)
			throw failure;
	}

	function ensureMipmapGraphicsResources() {
		if (mipmapShader != null)
			return;
		mipmapShader = new h3d.pass.OutputShader().compileShaders(new hxsl.Globals(), new hxsl.ShaderList(new VulkanMipmapShader()));
		mipmapPass = new h3d.mat.Pass("vulkan-mipmap-fallback");
		mipmapPass.depth(false, Always);
		mipmapPass.culling = None;
		final format = hxd.BufferFormat.make([
			{name: "position", type: DVec2},
			{name: "uv", type: DVec2},
		]);
		mipmapVertex = new h3d.Buffer(4, format, [NoAlloc]);
		@:privateAccess mipmapVertex.vbuf = allocBuffer(mipmapVertex);
		final vertices = new hxd.FloatBuffer(16);
		for (index => value in [
			-1.0, -1.0, 0.0, 0.0,
			 1.0, -1.0, 1.0, 0.0,
			 1.0,  1.0, 1.0, 1.0,
			-1.0,  1.0, 0.0, 1.0,
		]) vertices[index] = value;
		uploadBufferData(mipmapVertex, 0, 4, vertices, 0);
		mipmapIndex = new h3d.Buffer(6, hxd.BufferFormat.INDEX16, [IndexBuffer, NoAlloc]);
		@:privateAccess mipmapIndex.vbuf = allocBuffer(mipmapIndex);
		final indices = new hxd.IndexBuffer(6);
		for (index => value in [0, 1, 2, 0, 2, 3]) indices[index] = value;
		uploadIndexData(mipmapIndex, 0, 6, indices, 0);
	}

	public function uploadTextureRegion(t:h3d.mat.Texture, pixels:hxd.Pixels, x:Int, y:Int, mipLevel = 0, layer = 0) {
		if( !frameStarted )
			throw "Vulkan texture uploads require an active frame";
		if( mipLevel < 0 || mipLevel >= t.mipLevels )
			throw 'Mip level $mipLevel is outside texture ${t.id} range 0...${t.mipLevels - 1}';
		if( layer < 0 || layer >= t.layerCount )
			throw 'Layer $layer is outside texture ${t.id} range 0...${t.layerCount - 1}';
		final texture:VulkanTexture = t.t;
		if( texture == null || texture.disposed )
			throw 'Texture ${t.id} is not allocated';
		pixels.convert(t.format);
		final uploadPixels = if (t.format == ARGB) {
			final converted = pixels.clone();
			converted.convert(BGRA);
			converted;
		} else pixels;
		final mapping = VulkanTextureFormat.resolve(t.format);
		final mipWidth = hxd.Math.imax(1, t.width >> mipLevel);
		final mipHeight = hxd.Math.imax(1, t.height >> mipLevel);
		mapping.validateRegion(x, y, uploadPixels.width, uploadPixels.height, mipWidth, mipHeight);
		final expectedSize = mapping.uploadSize(uploadPixels.width, uploadPixels.height);
		if( uploadPixels.dataSize != expectedSize )
			throw 'Texture ${t.id} upload region requires $expectedSize bytes, got ${uploadPixels.dataSize}';
		suspendRendering();
		uploadManager.uploadImage(command, texture, mipLevel, layer, (uploadPixels.bytes:hl.Bytes), uploadPixels.offset, expectedSize, uploadPixels.width, uploadPixels.height, 1, x, y);
		texture.markUpload(mipLevel, layer, x == 0 && y == 0 && uploadPixels.width == mipWidth && uploadPixels.height == mipHeight);
		if (uploadPixels != pixels)
			uploadPixels.dispose();
		texture.lastSubmission = currentSubmissionSerial;
		t.flags.set(WasCleared);
	}

	function createBufferResource(usage:haxe.EnumFlags<VkBufferUsageFlag>, byteSize:haxe.Int64, stride:Int, memoryClass:VulkanMemoryClass, requiredProperties:Int, preferredProperties:Int,
		state:VulkanBufferState, debugId:Int, debugName:String) {
		var buffer = ctx.createBuffer64((byteSize : hl.I64), usage);
		if( buffer == null )
			throw Runtime.error('Failed to create Vulkan buffer $debugName ($byteSize bytes)');
		ctx.setBufferName(buffer, @:privateAccess debugName.toUtf8());
		var requirements = new VkMemoryRequirementsInfo();
		ctx.getBufferMemoryRequirements2(buffer, requirements);
		var allocation = try allocator.allocate(requirements, memoryClass, requiredProperties, preferredProperties, buffer, null, debugName) catch( error : Dynamic ) {
			ctx.destroyBuffer(buffer);
			throw error;
		};
		if( !ctx.bindBufferMemory64(buffer, allocation.memory, (allocation.offset : hl.I64)) ) {
			allocation.dispose();
			ctx.destroyBuffer(buffer);
			throw Runtime.error('Failed to bind Vulkan buffer $debugName memory');
		}
		var resource = new VulkanBuffer(buffer, allocation, byteSize, usage, stride, state, debugId, debugName);
		liveBuffers.push(resource);
		return resource;
	}

	function createInstanceBufferResource(usage:haxe.EnumFlags<VkBufferUsageFlag>, byteSize:Int, capacity:Int):VulkanInstanceBuffer {
		final buffer = ctx.createBuffer64((haxe.Int64.ofInt(byteSize) : hl.I64), usage);
		if( buffer == null )
			throw Runtime.error('Failed to create Vulkan instance buffer ($byteSize bytes)');
		final id = nextInstanceBufferId++;
		final name = 'instance-buffer-$id';
		ctx.setBufferName(buffer, @:privateAccess name.toUtf8());
		final requirements = new VkMemoryRequirementsInfo();
		ctx.getBufferMemoryRequirements2(buffer, requirements);
		final deviceLocal = 1 << Type.enumIndex(VkMemoryPropertyFlag.DEVICE_LOCAL);
		final allocation = try allocator.allocate(requirements, DeviceBuffer, deviceLocal, deviceLocal, buffer, null, name) catch( error : Dynamic ) {
			ctx.destroyBuffer(buffer);
			throw error;
		};
		if( !ctx.bindBufferMemory64(buffer, allocation.memory, (allocation.offset : hl.I64)) ) {
			allocation.dispose();
			ctx.destroyBuffer(buffer);
			throw Runtime.error('Failed to bind Vulkan instance buffer $name memory');
		}
		final resource = new VulkanInstanceBuffer(buffer, allocation, haxe.Int64.ofInt(byteSize), usage, Undefined, -id, name, capacity);
		liveBuffers.push(resource);
		return resource;
	}

	override function selectBuffer( v : h3d.Buffer ) {
		if( currentShader == null )
			throw "A Vulkan shader must be selected before selecting a vertex buffer";
		final vbuf:VulkanBuffer = @:privateAccess v.vbuf;
		prepareVertexBuffer(vbuf);
		var layouts = vertexLayouts.get(currentShader);
		if( layouts == null ) {
			layouts = new Map();
			vertexLayouts.set(currentShader, layouts);
		}
		var layout = layouts.get(v.format);
		if( layout == null ) {
			final mapping = v.format.resolveMapping(currentShader.shader.getInputFormat());
			final attributes = [];
			for( index => input in currentShader.vertexInterface.inputs ) {
				final entry = mapping[index];
				attributes.push(new VulkanVertexAttribute(input.location, 0, resolveVertexFormat(input.type, entry.precision), entry.offset));
			}
			final bindings = [new VulkanVertexBinding(0, v.format.strideBytes)];
			validateVertexAttributes(attributes, bindings);
			layout = new VulkanVertexLayout(bindings, attributes);
			layouts.set(v.format, layout);
		}
		currentVertexLayout = layout;
		currentVertexBuffers.resize(1);
		currentVertexBuffers[0] = vbuf;
		command.bindVertexBuffer(0, vbuf.buffer, 0);
	}

	override function selectMultiBuffers( format : hxd.BufferFormat.MultiFormat, buffers : Array<h3d.Buffer> ) {
		if( currentShader == null )
			throw "A Vulkan shader must be selected before selecting Vulkan vertex buffers";
		if( buffers.length == 0 )
			throw "Vulkan multi-buffer selection requires at least one buffer";
		currentVertexBuffers.resize(buffers.length);
		if( vertexBufferScratch.length < buffers.length ) vertexBufferScratch = new hl.NativeArray<limen.graphics.vulkan.memory.Memory.VkBuffer>(buffers.length);
		if( vertexOffsetScratch.length < buffers.length ) vertexOffsetScratch = new hl.NativeArray<hl.I64>(buffers.length);
		for( index => buffer in buffers ) {
			final vbuf:VulkanBuffer = @:privateAccess buffer.vbuf;
			prepareVertexBuffer(vbuf);
			currentVertexBuffers[index] = vbuf;
			vertexBufferScratch[index] = vbuf.buffer;
			vertexOffsetScratch[index] = (haxe.Int64.ofInt(0) : hl.I64);
		}
		var layouts = multiVertexLayouts.get(currentShader);
		if( layouts == null ) {
			layouts = new Map();
			multiVertexLayouts.set(currentShader, layouts);
		}
		var layout = layouts.get(format);
		if( layout == null ) {
			final map = format.resolveMapping(currentShader.shader.getInputFormat());
			final usedBindings:Map<Int, Bool> = new Map();
			final attributes = [];
			for( index => input in currentShader.vertexInterface.inputs ) {
				final entry = map[index];
				if( entry.bufferIndex < 0 || entry.bufferIndex >= buffers.length )
					throw 'Vulkan vertex mapping for ${input.name} references missing buffer ${entry.bufferIndex}';
				usedBindings.set(entry.bufferIndex, true);
				attributes.push(new VulkanVertexAttribute(input.location, entry.bufferIndex, resolveVertexFormat(input.type, entry.precision), entry.offset));
			}
			final bindings = [for( index in 0...buffers.length ) if( usedBindings.exists(index) ) new VulkanVertexBinding(index, buffers[index].format.strideBytes)];
			validateVertexAttributes(attributes, bindings);
			layout = new VulkanVertexLayout(bindings, attributes);
			layouts.set(format, layout);
		}
		currentVertexLayout = layout;
		command.bindVertexBuffersNative(0, buffers.length, vertexBufferScratch, vertexOffsetScratch);
	}

	function prepareVertexBuffer(buffer:VulkanBuffer) {
		if( buffer == null || buffer.disposed || !buffer.usage.has(VERTEX_BUFFER) )
			throw "Vulkan draw requires a valid vertex-buffer resource";
		if( renderingStarted && buffer.state != VertexInput )
			suspendRendering();
		VulkanResourceState.transitionBuffer(command, buffer, VertexInput, haxe.Int64.ofInt(0), buffer.size);
		buffer.lastSubmission = currentSubmissionSerial;
	}

	function resolveVertexFormat(type:VulkanShaderType, precision:hxd.BufferFormat.Precision):VkFormat {
		if( type.numericType != VulkanNumericType.Float || type.columns != 1 || type.components < 1 || type.components > 4 )
			throw 'Vulkan vertex input ${type.signature} is not supported by HEAPS-VK-002';
		final format:VkFormat = switch( precision ) {
		case F32:
			switch( type.components ) {
			case 1: R32_SFLOAT;
			case 2: R32G32_SFLOAT;
			case 3: R32G32B32_SFLOAT;
			case 4: R32G32B32A32_SFLOAT;
			default: UNDEFINED;
			}
		case F16:
			switch( type.components ) {
			case 1: R16_SFLOAT;
			case 2: R16G16_SFLOAT;
			case 3: R16G16B16_SFLOAT;
			case 4: R16G16B16A16_SFLOAT;
			default: UNDEFINED;
			}
		case U8:
			switch( type.components ) {
			case 1: R8_UNORM;
			case 2: R8G8_UNORM;
			case 3: R8G8B8_UNORM;
			case 4: R8G8B8A8_UNORM;
			default: UNDEFINED;
			}
		case S8:
			switch( type.components ) {
			case 1: R8_SNORM;
			case 2: R8G8_SNORM;
			case 3: R8G8B8_SNORM;
			case 4: R8G8B8A8_SNORM;
			default: UNDEFINED;
			}
		}
		final properties = new VkFormatProperties();
		ctx.getPdeviceFormatProps(format, properties);
		if( (properties.bufferFeatures & cast VkFormatFeature.VERTEX_BUFFER) == 0 )
			throw 'Physical Vulkan vertex format $format is not supported by this device';
		return format;
	}

	function validateVertexAttributes(attributes:Array<VulkanVertexAttribute>, bindings:Array<VulkanVertexBinding>) {
		if( attributes.length != currentShader.vertexInterface.inputs.length )
			throw 'Vulkan vertex layout resolved ${attributes.length} attributes, shader requires ${currentShader.vertexInterface.inputs.length}';
		if( attributes.length > limits.maxVertexInputAttributes || bindings.length > limits.maxVertexInputBindings )
			throw "Vulkan vertex layout exceeds device attribute or binding limits";
		for( binding in bindings )
			if( binding.stride <= 0 || binding.stride > limits.maxVertexInputBindingStride )
				throw 'Vulkan vertex binding ${binding.binding} has unsupported stride ${binding.stride}';
		for( attribute in attributes )
			if( attribute.offset < 0 || attribute.offset > limits.maxVertexInputAttributeOffset )
				throw 'Vulkan vertex attribute ${attribute.location} has unsupported offset ${attribute.offset}';
	}

	override function allocBuffer( b : h3d.Buffer ) : GPUBuffer {
		var usage = new haxe.EnumFlags<VkBufferUsageFlag>();
		usage.set(TRANSFER_DST);
		usage.set(TRANSFER_SRC);
		if( b.flags.has(IndexBuffer) )
			usage.set(INDEX_BUFFER);
		else
			usage.set(VERTEX_BUFFER);
		if( b.flags.has(UniformBuffer) )
			usage.set(UNIFORM_BUFFER);
		usage.set(STORAGE_BUFFER);
		var deviceLocal = 1 << Type.enumIndex(VkMemoryPropertyFlag.DEVICE_LOCAL);
		final byteSize = haxe.Int64.ofInt(b.vertices) * haxe.Int64.ofInt(b.format.strideBytes);
		return createBufferResource(usage, byteSize, b.format.strideBytes, DeviceBuffer, deviceLocal, deviceLocal, Undefined, b.id, 'buffer-${b.id}');
	}

	override function allocInstanceBuffer(b:InstanceBuffer, bytes:haxe.io.Bytes) {
		if( InstanceBuffer.ELEMENT_SIZE != VulkanInstanceBuffer.COMMAND_STRIDE )
			throw 'Heaps/Vulkan indirect-command stride mismatch: ${InstanceBuffer.ELEMENT_SIZE} != ${VulkanInstanceBuffer.COMMAND_STRIDE}';
		if( b.commandCount <= 0 )
			throw "Vulkan instance-buffer allocation requires at least one command";
		final byteSize = b.commandCount * VulkanInstanceBuffer.COMMAND_STRIDE;
		if( bytes.length != byteSize )
			throw 'Vulkan instance-buffer allocation requires exactly $byteSize bytes, got ${bytes.length}';
		if( !frameStarted )
			throw "Vulkan instance-buffer allocation requires an active frame";
		suspendRendering();
		var usage = new haxe.EnumFlags<VkBufferUsageFlag>();
		usage.set(TRANSFER_DST);
		usage.set(INDIRECT_BUFFER);
		final resource = createInstanceBufferResource(usage, byteSize, b.commandCount);
		uploadManager.uploadBuffer(command, resource, 0, @:privateAccess bytes.b, 0, byteSize);
		resource.updateMetadata(0, b.commandCount, @:privateAccess bytes.b, 0);
		resource.lastSubmission = currentSubmissionSerial;
		@:privateAccess b.data = resource;
	}

	override function uploadInstanceBufferBytes(b:InstanceBuffer, startVertex:Int, vertexCount:Int, bytes:haxe.io.Bytes, bytesPosition:Int) {
		final resource:VulkanInstanceBuffer = cast @:privateAccess b.data;
		if( resource == null || resource.disposed || !resource.usage.has(INDIRECT_BUFFER) )
			throw "Vulkan instance-buffer update requires an allocated indirect buffer";
		if( startVertex < 0 || vertexCount <= 0 || startVertex + vertexCount > resource.capacity )
			throw 'Vulkan instance-buffer update range [$startVertex, ${startVertex + vertexCount}) exceeds ${resource.capacity} commands';
		final byteSize = vertexCount * VulkanInstanceBuffer.COMMAND_STRIDE;
		if( bytesPosition < 0 || bytesPosition + byteSize > bytes.length )
			throw 'Vulkan instance-buffer upload source range [$bytesPosition, ${bytesPosition + byteSize}) exceeds ${bytes.length} bytes';
		if( !frameStarted )
			throw "Vulkan instance-buffer update requires an active frame";
		suspendRendering();
		final destinationOffset = startVertex * VulkanInstanceBuffer.COMMAND_STRIDE;
		uploadManager.uploadBuffer(command, resource, destinationOffset, @:privateAccess bytes.b, bytesPosition, byteSize);
		resource.updateMetadata(startVertex, vertexCount, @:privateAccess bytes.b, bytesPosition);
		resource.lastSubmission = currentSubmissionSerial;
	}

	override function disposeInstanceBuffer(b:InstanceBuffer) {
		final resource:VulkanBuffer = cast @:privateAccess b.data;
		if( resource == null )
			return;
		destroyBufferResource(resource);
		@:privateAccess b.data = null;
	}

	override function disposeBuffer( b : h3d.Buffer ) {
		if( b.vbuf == null )
			return;
		final vbuf:VulkanBuffer = b.vbuf;
		final handle = bufferHandles.get(b);
		if( handle != null ) {
			final index = handle.handle;
			@:privateAccess handle.handle = -1;
			bufferHandles.remove(b);
			final release = () -> {
				if( bindlessDescriptors != null )
					bindlessDescriptors.releaseBuffer(index);
			};
			if( vbuf.lastSubmission <= completedSubmissionSerial ) release() else deferredDestroy.retire(vbuf.lastSubmission, release);
		}
		destroyBufferResource(vbuf);
	}

	function destroyBufferResource(buffer:VulkanBuffer, immediate = false) {
		if( buffer.disposed )
			return;
		liveBuffers.remove(buffer);
		@:privateAccess buffer.markDisposed();
		final destroy = () -> {
			ctx.destroyBuffer(buffer.buffer);
			buffer.allocation.dispose();
		};
		if( immediate || buffer.lastSubmission <= completedSubmissionSerial )
			destroy();
		else
			deferredDestroy.retire(buffer.lastSubmission, destroy);
	}

	function updateBuffer( buffer:VulkanBuffer, bytes:hl.Bytes, offset:Int, size:Int ) {
		if( !frameStarted )
			throw "Vulkan buffer uploads require an active frame";
		suspendRendering();
		uploadManager.uploadBuffer(command, buffer, offset, bytes, 0, size);
		buffer.lastSubmission = currentSubmissionSerial;
	}

	override function uploadIndexData( i : h3d.Buffer, startIndice : Int, indiceCount : Int, buf : hxd.IndexBuffer, bufPos : Int ) {
		var ibuf:VulkanBuffer = @:privateAccess i.vbuf;
		updateBuffer(ibuf, hl.Bytes.getArray(buf.getNative()).offset(Std.int(bufPos * ibuf.stride)), Std.int(startIndice * ibuf.stride), Std.int(indiceCount * ibuf.stride));
	}

	override function uploadBufferData( v : h3d.Buffer, startVertex : Int, vertexCount : Int, buf : hxd.FloatBuffer, bufPos : Int ) {
		var vbuf:VulkanBuffer = @:privateAccess v.vbuf;
		updateBuffer(vbuf, hl.Bytes.getArray(buf.getNative()).offset(bufPos<<2), Std.int(startVertex * vbuf.stride), Std.int(vertexCount * vbuf.stride));
	}

	override function uploadBufferBytes( v : h3d.Buffer, startVertex : Int, vertexCount : Int, buf : haxe.io.Bytes, bufPos : Int ) {
		var vbuf:VulkanBuffer = @:privateAccess v.vbuf;
		updateBuffer(vbuf, @:privateAccess buf.b.offset(bufPos), Std.int(startVertex * vbuf.stride), Std.int(vertexCount * vbuf.stride));
	}

	override function readBufferBytes( b:h3d.Buffer, startVertex:Int, vertexCount:Int, bytes:haxe.io.Bytes, bytesPosition:Int ) {
		if( !frameStarted )
			throw "Vulkan buffer readback requires an active frame";
		if( activeQueryIntervals != 0 )
			throw "Cannot synchronously read a Vulkan buffer while a query interval is active";
		if( renderingStarted )
			throw "Vulkan buffer readback must be recorded before rendering starts";
		final buffer:VulkanBuffer = @:privateAccess b.vbuf;
		final size = vertexCount * buffer.stride;
		final sourceOffset = startVertex * buffer.stride;
		final submittedFrame = currentFrameIndex;
		readbackManager.requestBuffer(command, submittedFrame, buffer, sourceOffset, size, @:privateAccess bytes.b, bytesPosition, null);
		buffer.lastSubmission = currentSubmissionSerial;
		endFrame();
		submit();
		if( ctx.waitForFence(frames[submittedFrame].fence, -1) != 0 )
			throw Runtime.error("Failed to wait for synchronous Vulkan readback");
		readbackManager.completeFrame(submittedFrame);
		if( swapchainReady )
			beginFrame();
	}

	override function readBufferBytesAsync( b:h3d.Buffer, startVertex:Int, vertexCount:Int, bytes:haxe.io.Bytes, bytesPosition:Int, callback:Void->Void ) {
		if( !frameStarted )
			throw "Vulkan buffer readback requires an active frame";
		if( renderingStarted )
			throw "Vulkan buffer readback must be recorded before rendering starts";
		final buffer:VulkanBuffer = @:privateAccess b.vbuf;
		readbackManager.requestBuffer(command, currentFrameIndex, buffer, startVertex * buffer.stride, vertexCount * buffer.stride, @:privateAccess bytes.b, bytesPosition, callback);
		buffer.lastSubmission = currentSubmissionSerial;
	}

	override function selectMaterial( pass : h3d.mat.Pass ) {
		if( pass.wireframe && !capabilities.fillModeNonSolid )
			throw "Vulkan wireframe rendering requires the fillModeNonSolid device feature";
		if( pass.depthClamp && !capabilities.depthClamp )
			throw "Vulkan depth clamp is not supported by this device";
		if( pass.colorMask < 0 )
			throw "Vulkan color mask must be non-negative";
		final opaque = pass.blendSrc == One && pass.blendDst == Zero && pass.blendAlphaSrc == One && pass.blendAlphaDst == Zero
			&& pass.blendOp == Add && pass.blendAlphaOp == Add;
		if( currentBlendState == null )
			currentBlendState = new VulkanBlendState(!opaque, blendFactor(pass.blendSrc), blendFactor(pass.blendDst), blendOperation(pass.blendOp),
				blendFactor(pass.blendAlphaSrc), blendFactor(pass.blendAlphaDst), blendOperation(pass.blendAlphaOp), pass.colorMask);
		else
			currentBlendState.update(!opaque, blendFactor(pass.blendSrc), blendFactor(pass.blendDst), blendOperation(pass.blendOp),
				blendFactor(pass.blendAlphaSrc), blendFactor(pass.blendAlphaDst), blendOperation(pass.blendAlphaOp), pass.colorMask);
		currentColorMasks = pass.colorMask;
		currentDepthClamp = pass.depthClamp;
		currentWireframe = pass.wireframe;
		currentCullMode = switch( pass.culling ) {
		case None: VkCullModeFlags.NONE;
		case Back: VkCullModeFlags.BACK;
		case Front: VkCullModeFlags.FRONT;
		case Both: VkCullModeFlags.FRONT_AND_BACK;
		}
		currentDepthTest = pass.depthTest != Always || pass.depthWrite;
		currentDepthWrite = pass.depthWrite;
		currentDepthCompare = switch( pass.depthTest ) {
		case Always: VkCompareOp.ALWAYS;
		case Never: VkCompareOp.NEVER;
		case Equal: VkCompareOp.EQUAL;
		case NotEqual: VkCompareOp.NOT_EQUAL;
		case Greater: VkCompareOp.GREATER;
		case GreaterEqual: VkCompareOp.GREATER_OR_EQUAL;
		case Less: VkCompareOp.LESS;
		case LessEqual: VkCompareOp.LESS_OR_EQUAL;
		}
		if( pass.stencil == null ) {
			if( currentStencilState == null ) {
				final front = new VulkanStencilFaceState(VkStencilOp.KEEP, VkStencilOp.KEEP, VkStencilOp.KEEP, VkCompareOp.ALWAYS);
				final back = new VulkanStencilFaceState(VkStencilOp.KEEP, VkStencilOp.KEEP, VkStencilOp.KEEP, VkCompareOp.ALWAYS);
				currentStencilState = new VulkanStencilState(false, front, back, 0xFF, 0, 0);
			} else
				currentStencilState.enabled = false;
		} else {
			final stencil = pass.stencil;
			if( currentStencilState == null ) {
				final front = new VulkanStencilFaceState(stencilOp(stencil.frontSTfail), stencilOp(stencil.frontPass),
					stencilOp(stencil.frontDPfail), compareOp(stencil.frontTest));
				final back = new VulkanStencilFaceState(stencilOp(stencil.backSTfail), stencilOp(stencil.backPass),
					stencilOp(stencil.backDPfail), compareOp(stencil.backTest));
				currentStencilState = new VulkanStencilState(true, front, back, stencil.readMask, stencil.writeMask, stencil.reference);
			} else {
				currentStencilState.front.update(stencilOp(stencil.frontSTfail), stencilOp(stencil.frontPass),
					stencilOp(stencil.frontDPfail), compareOp(stencil.frontTest));
				currentStencilState.back.update(stencilOp(stencil.backSTfail), stencilOp(stencil.backPass),
					stencilOp(stencil.backDPfail), compareOp(stencil.backTest));
				currentStencilState.update(true, currentStencilState.front, currentStencilState.back, stencil.readMask, stencil.writeMask, stencil.reference);
			}
		}
		materialSelected = true;
	}

	inline function blendFactor(factor:h3d.mat.Data.Blend):VkBlendFactor {
		return switch( factor ) {
		case One: VkBlendFactor.ONE;
		case Zero: VkBlendFactor.ZERO;
		case SrcAlpha: VkBlendFactor.SRC_ALPHA;
		case SrcColor: VkBlendFactor.SRC_COLOR;
		case DstAlpha: VkBlendFactor.DST_ALPHA;
		case DstColor: VkBlendFactor.DST_COLOR;
		case OneMinusSrcAlpha: VkBlendFactor.ONE_MINUS_SRC_ALPHA;
		case OneMinusSrcColor: VkBlendFactor.ONE_MINUS_SRC_COLOR;
		case OneMinusDstAlpha: VkBlendFactor.ONE_MINUS_DST_ALPHA;
		case OneMinusDstColor: VkBlendFactor.ONE_MINUS_DST_COLOR;
		case SrcAlphaSaturate: VkBlendFactor.SRC_ALPHA_SATURATE;
		case ConstantColor, ConstantAlpha, OneMinusConstantColor, OneMinusConstantAlpha:
			throw 'Vulkan does not support the WebGL-only Heaps blend factor $factor';
		}
	}

	inline function blendOperation(operation:h3d.mat.Data.Operation):VkBlendOp {
		return switch( operation ) {
		case Add: VkBlendOp.ADD;
		case Sub: VkBlendOp.SUBTRACT;
		case ReverseSub: VkBlendOp.REVERSE_SUBTRACT;
		case Min: VkBlendOp.MIN;
		case Max: VkBlendOp.MAX;
		}
	}

	inline function compareOp(compare:h3d.mat.Data.Compare):VkCompareOp {
		return switch( compare ) {
		case Always: VkCompareOp.ALWAYS;
		case Never: VkCompareOp.NEVER;
		case Equal: VkCompareOp.EQUAL;
		case NotEqual: VkCompareOp.NOT_EQUAL;
		case Greater: VkCompareOp.GREATER;
		case GreaterEqual: VkCompareOp.GREATER_OR_EQUAL;
		case Less: VkCompareOp.LESS;
		case LessEqual: VkCompareOp.LESS_OR_EQUAL;
		}
	}

	inline function stencilOp(operation:h3d.mat.Data.StencilOp):VkStencilOp {
		return switch( operation ) {
		case Keep: VkStencilOp.KEEP;
		case Zero: VkStencilOp.ZERO;
		case Replace: VkStencilOp.REPLACE;
		case Increment: VkStencilOp.INCREMENT_AND_CLAMP;
		case IncrementWrap: VkStencilOp.INCREMENT_AND_WRAP;
		case Decrement: VkStencilOp.DECREMENT_AND_CLAMP;
		case DecrementWrap: VkStencilOp.DECREMENT_AND_WRAP;
		case Invert: VkStencilOp.INVERT;
		}
	}

	override function uploadShaderBuffers( buf : h3d.shader.Buffers, which : h3d.shader.Buffers.BufferKind ) {
		if( currentShader == null )
			throw "A Vulkan shader must be selected before uploading shader data";
		if( !frameStarted )
			throw "Vulkan shader uploads require an active frame";
		switch( which ) {
		case Globals:
			uploadStageConstants(buf.vertex, currentShader.shader.mode == hxsl.RuntimeShader.LinkMode.Compute ? currentShader.shader.compute : currentShader.shader.vertex,
				currentShader.shader.mode == hxsl.RuntimeShader.LinkMode.Compute ? VulkanShaderStage.Compute : VulkanShaderStage.Vertex, VulkanConstantFrequency.Globals);
			if( currentShader.shader.mode != hxsl.RuntimeShader.LinkMode.Compute )
				uploadStageConstants(buf.fragment, currentShader.shader.fragment, VulkanShaderStage.Fragment, VulkanConstantFrequency.Globals);
		case Params:
			uploadStageConstants(buf.vertex, currentShader.shader.mode == hxsl.RuntimeShader.LinkMode.Compute ? currentShader.shader.compute : currentShader.shader.vertex,
				currentShader.shader.mode == hxsl.RuntimeShader.LinkMode.Compute ? VulkanShaderStage.Compute : VulkanShaderStage.Vertex, VulkanConstantFrequency.Params);
			if( currentShader.shader.mode != hxsl.RuntimeShader.LinkMode.Compute )
				uploadStageConstants(buf.fragment, currentShader.shader.fragment, VulkanShaderStage.Fragment, VulkanConstantFrequency.Params);
		case Textures:
			textureBindings.clear();
			textureBindingsShaderKey = currentShader.cacheKey;
			if( uploadStageTextures(buf, buf.vertex, currentShader.shader.vertex) )
				return;
			if( currentShader.shader.mode != hxsl.RuntimeShader.LinkMode.Compute && uploadStageTextures(buf, buf.fragment, currentShader.shader.fragment) )
				return;
			if( currentShader.compute == null )
				boundDescriptorState = null;
			else
				boundComputeDescriptorState = null;
		case Buffers:
			bufferBindings.clear();
			bufferBindingKinds.clear();
			bufferBindingsShaderKey = currentShader.cacheKey;
			if( uploadStageBuffers(buf.vertex, currentShader.shader.mode == hxsl.RuntimeShader.LinkMode.Compute ? currentShader.shader.compute : currentShader.shader.vertex) )
				return;
			if( currentShader.shader.mode != hxsl.RuntimeShader.LinkMode.Compute )
				uploadStageBuffers(buf.fragment, currentShader.shader.fragment);
			if( currentShader.compute == null )
				boundDescriptorState = null;
			else
				boundComputeDescriptorState = null;
		}
	}

	function uploadStageBuffers(buffers:h3d.shader.Buffers.ShaderBuffers, shader:hxsl.RuntimeShader.RuntimeShaderData):Bool {
		var allocation = shader.buffers;
		var slot = 0;
		while( allocation != null ) {
			final buffer = buffers.buffers == null ? null : buffers.buffers[slot++];
			if( buffer == null || buffer.isDisposed() )
				throw 'Vulkan shader buffer ${allocation.name} is missing or disposed';
			final resource:VulkanBuffer = @:privateAccess buffer.vbuf;
			if( resource == null || resource.disposed )
				throw 'Vulkan shader buffer ${allocation.name} is not allocated';
			final kind = switch( allocation.type ) {
			case TBuffer(_, _, value): value;
			default: throw 'Unexpected Vulkan shader-buffer allocation type ${allocation.type}';
			}
			switch( kind ) {
			case Uniform, Partial:
				if( !buffer.flags.has(UniformBuffer) || !resource.usage.has(UNIFORM_BUFFER) )
					throw 'Buffer ${buffer.id} was allocated without UniformBuffer flag';
				validateBufferDescriptorRange(allocation.name, resource.size, limits.maxUniformBufferRange);
			case Storage, StoragePartial:
				if( !resource.usage.has(STORAGE_BUFFER) )
					throw 'Buffer ${buffer.id} is missing Vulkan storage-buffer usage';
				validateBufferDescriptorRange(allocation.name, resource.size, limits.maxStorageBufferRange);
			case RW, RWPartial:
				if( !buffer.flags.has(ReadWriteBuffer) )
					throw 'Buffer ${buffer.id} was allocated without ReadWriteBuffer flag';
				if( !resource.usage.has(STORAGE_BUFFER) )
					throw 'Buffer ${buffer.id} is missing Vulkan storage-buffer usage';
				validateBufferDescriptorRange(allocation.name, resource.size, limits.maxStorageBufferRange);
			}
			final key = VulkanShaderAbi.allocationId(allocation);
			final existing = bufferBindings.get(key);
			if( existing != null && existing != buffer )
				throw 'HxSL resource $key resolves to different vertex and fragment buffers';
			bufferBindings.set(key, buffer);
			bufferBindingKinds.set(key, kind);
			@:privateAccess buffer.lastFrame = currentSubmissionSerial;
			allocation = allocation.next;
		}
		return false;
	}

	function validateBufferDescriptorRange(name:String, range:haxe.Int64, limit:Int) {
		if( haxe.Int64.compare(range, haxe.Int64.ofInt(0)) <= 0 )
			throw 'Vulkan descriptor range for $name must be positive, got $range';
		if( limit >= 0 && haxe.Int64.compare(range, haxe.Int64.ofInt(limit)) > 0 )
			throw 'Vulkan descriptor range $range for $name exceeds device limit $limit';
	}

	function uploadStageTextures(allBuffers:h3d.shader.Buffers, buffers:h3d.shader.Buffers.ShaderBuffers, shader:hxsl.RuntimeShader.RuntimeShaderData):Bool {
		var allocation = shader.textures;
		var slot = 0;
		while( allocation != null ) {
			var texture = buffers.tex[slot++];
			if( texture == null || texture.isDisposed() )
				switch( allocation.type ) {
				case TRWTexture(_, _, _), TArray(TRWTexture(_, _, _), _):
					throw 'Vulkan writable texture ${allocation.name} is missing or disposed';
				default:
					texture = getFallbackTexture(allocation.type);
				}
			if( texture.t == null ) {
				if( texture.realloc == null )
					throw 'Vulkan shader texture ${allocation.name} is not allocated';
				final selectedShader = currentShader.shader;
				@:privateAccess texture.alloc();
				texture.realloc();
				if( currentShader == null || currentShader.shader != selectedShader ) {
					currentShader = null;
					selectShader(selectedShader);
					uploadShaderBuffers(allBuffers, Globals);
					uploadShaderBuffers(allBuffers, Params);
					uploadShaderBuffers(allBuffers, Textures);
					return true;
				}
			}
			validateTextureType(texture, allocation.type, allocation.name);
			final key = VulkanShaderAbi.allocationId(allocation);
			final existing = textureBindings.get(key);
			if( existing != null && existing != texture )
				throw 'HxSL resource $key resolves to different vertex and fragment textures';
			textureBindings.set(key, texture);
			@:privateAccess texture.lastFrame = currentSubmissionSerial;
			allocation = allocation.next;
		}
		return false;
	}

	function getFallbackTexture(type:hxsl.Ast.Type):h3d.mat.Texture {
		final samplerType = switch( type ) {
		case TArray(element, _): element;
		default: type;
		}
		final key = switch( samplerType ) {
		case TSampler(TCube, false): "cube";
		case TSampler(T2D, true): "array";
		case TSampler(T2D, false): "2d";
		default: throw 'No Vulkan fallback texture is available for HxSL type $type';
		}
		var texture = fallbackTextures.get(key);
		if( texture != null )
			return texture;
		if( key == "array" ) {
			final array:h3d.mat.TextureArray = Type.createEmptyInstance(h3d.mat.TextureArray);
			@:privateAccess array.layers = 1;
			texture = array;
		} else
			texture = Type.createEmptyInstance(h3d.mat.Texture);
		var flags = new haxe.EnumFlags<h3d.mat.Data.TextureFlags>();
		flags.set(NoAlloc);
		if( key == "array" ) flags.set(IsArray);
		if( key == "cube" ) flags.set(Cube);
		@:privateAccess texture.id = nextFallbackTextureId--;
		@:privateAccess texture.name = 'vulkan-fallback-$key';
		@:privateAccess texture.width = 1;
		@:privateAccess texture.height = 1;
		@:privateAccess texture.flags = flags;
		@:privateAccess texture.format = RGBA;
		texture.mipMap = None;
		texture.filter = Nearest;
		texture.wrap = Clamp;
		texture.lodBias = 0;
		texture.startingMip = 0;
		@:privateAccess texture.t = allocTexture(texture);
		for( layer in 0...texture.layerCount ) {
			final pixels = new hxd.Pixels(1, 1, haxe.io.Bytes.ofHex("202020FF"), RGBA);
			uploadTexturePixels(texture, pixels, 0, layer);
			pixels.dispose();
		}
		fallbackTextures.set(key, texture);
		return texture;
	}

	function validateTextureType(texture:h3d.mat.Texture, type:hxsl.Ast.Type, name:String) {
		switch( type ) {
		case TSampler(dimension, array), TRWTexture(dimension, array, _):
			final arrayView = texture.flags.has(IsArray) && texture.slice == 0;
			if( array != arrayView )
				throw 'Texture $name array shape does not match HxSL type $type';
			switch( dimension ) {
			case T2D if( !texture.flags.has(Cube) && !texture.flags.has(Is3D) ):
			case TCube if( texture.flags.has(Cube) ):
			case T3D:
			throw 'Vulkan 3D texture access is not supported';
			default:
				throw 'Texture $name does not match HxSL type $type';
			}
			final channels = switch( type ) {
			case TRWTexture(_, _, value): value;
			default: 0;
			}
			if( channels != 0 ) {
				if( !texture.flags.has(Writable) )
					throw 'Texture ${texture.id} was allocated without Writable flag';
				final expectedFormat = switch( channels ) {
				case 1: hxd.PixelFormat.R32F;
				case 2: hxd.PixelFormat.RG32F;
				case 4: hxd.PixelFormat.RGBA32F;
				default: throw 'Vulkan storage image $name has unsupported HxSL channel count $channels';
				}
				if( texture.format != expectedFormat )
					throw 'Texture $name format ${texture.format} does not match HxSL storage-image format $expectedFormat';
			}
		case TArray(element, _):
			validateTextureType(texture, element, name);
		default:
		}
	}

	function uploadStageConstants(buffers:h3d.shader.Buffers.ShaderBuffers, shader:hxsl.RuntimeShader.RuntimeShaderData,
		stage:VulkanShaderStage, frequency:VulkanConstantFrequency) {
		var block:VulkanConstantBlock = null;
		for( candidate in currentShader.programLayout.constantBlocks )
			if( candidate.stage == stage && candidate.frequency == frequency ) {
				block = candidate;
				break;
			}
		if( block == null )
			return;
		final source = frequency == VulkanConstantFrequency.Globals ? buffers.globals : buffers.params;
		if( source.length * 4 < block.sourceSize )
			throw '${block.name} requires ${block.sourceSize} CPU bytes, got ${source.length * 4}';
		final bytes = hl.Bytes.getArray(source.toData());
		final alignment = hxd.Math.imax(16, limits.minUniformBufferOffsetAlignment.toInt());
		final frame = frames[currentFrameIndex];
		final blockId = currentShader.constantBlockIds.get(block);
		var upload = frame.shaderConstants.get(blockId);
		if( upload == null ) {
			upload = new VulkanConstantUpload();
			frame.shaderConstants.set(blockId, upload);
		}
		final previousBuffer = upload.buffer;
		uploadManager.uploadConstants(command, bytes, 0, block.sourceSize, alignment, upload, !renderingStarted);
		if( previousBuffer != upload.buffer )
			currentShader.descriptorSets[block.set].revision++;
		final textureStart = frequency == VulkanConstantFrequency.Globals ? shader.paramsTexHandleCount : 0;
		final textureCount = frequency == VulkanConstantFrequency.Globals ? shader.globalsTexHandleCount : shader.paramsTexHandleCount;
		for( index in textureStart...textureStart + textureCount )
			selectTextureHandle(buffers.texHandles[index]);
		final bufferStart = frequency == VulkanConstantFrequency.Globals ? shader.paramsBufHandleCount : 0;
		final bufferCount = frequency == VulkanConstantFrequency.Globals ? shader.globalsBufHandleCount : shader.paramsBufHandleCount;
		for( index in bufferStart...bufferStart + bufferCount )
			selectBufferHandle(buffers.bufHandles[index]);
	}

	override function draw(ibuf:h3d.Buffer, startIndex:Int, ntriangles:Int) {
		if( startIndex < 0 || ntriangles < 0 )
			throw "Vulkan indexed draw requires non-negative startIndex and triangle count";
		prepareIndexedDraw(ibuf);
		command.drawIndexed(ntriangles * 3, 1, startIndex, 0, 0);
	}

	function prepareIndexedDraw(ibuf:h3d.Buffer, indirect:VulkanBuffer = null, count:VulkanBuffer = null):VulkanBuffer {
		if( !frameStarted )
			throw "Vulkan indexed draw requires an active frame";
		if( currentShader == null || currentShader.vertex == null || currentShader.fragment == null )
			throw "Vulkan indexed draw requires an active graphics shader";
		if( currentVertexLayout == null || currentVertexBuffers.length == 0 )
			throw "Vulkan indexed draw requires selected vertex buffers and a resolved vertex layout";
		if( !materialSelected || currentBlendState == null )
			throw "Vulkan indexed draw requires selected material state";
		final b:VulkanBuffer = @:privateAccess ibuf.vbuf;
		if( b == null || b.disposed || !b.usage.has(INDEX_BUFFER) || (b.stride != 2 && b.stride != 4) )
			throw "Vulkan indexed draw requires a valid 16-bit or 32-bit index buffer";
		if( currentTargetSet == null )
			throw "Vulkan indexed draw requires an active attachment set";
		if( currentTargetSet.colors.length > 0 )
			for( output in currentShader.fragmentOutputs.outputs )
				if( output.location >= currentTargetSet.colors.length )
					throw 'Fragment output location ${output.location} exceeds active Vulkan color attachment range 0...${currentTargetSet.colors.length - 1}';
		if( currentBlendState.enabled )
			for( attachment in currentTargetSet.colors ) {
				final format:Int = cast attachment.format;
				var supported = blendFormatSupport.get(format);
				if( supported == null ) {
					final properties = new VkFormatProperties();
					ctx.getPdeviceFormatProps(attachment.format, properties);
					supported = (properties.optimalTilingFeatures & cast VkFormatFeature.COLOR_ATTACHMENT_BLEND) != 0;
					blendFormatSupport.set(format, supported);
				}
				if( !supported )
					throw 'Vulkan color attachment format ${attachment.format} does not support blending';
			}
		validateShaderResources(false);
		var requiresBufferTransition = b.state != IndexInput;
		if( indirect != null && indirect.state != IndirectArgument ) requiresBufferTransition = true;
		if( count != null && count.state != IndirectArgument ) requiresBufferTransition = true;
		if( renderingStarted && requiresBufferTransition )
			suspendRendering();
		VulkanResourceState.transitionBuffer(command, b, IndexInput, haxe.Int64.ofInt(0), b.size);
		b.lastSubmission = currentSubmissionSerial;
		if( indirect != null ) {
			VulkanResourceState.transitionBuffer(command, indirect, IndirectArgument, haxe.Int64.ofInt(0), indirect.size);
			indirect.lastSubmission = currentSubmissionSerial;
		}
		if( count != null ) {
			VulkanResourceState.transitionBuffer(command, count, IndirectArgument, haxe.Int64.ofInt(0), count.size);
			count.lastSubmission = currentSubmissionSerial;
		}
		prepareShaderBuffers(false);
		prepareShaderTextures(false);
		beginRendering();
		beginActiveSampleQuery();
		final targetDepthFormat = currentTargetSet.depth == null ? VkFormat.UNDEFINED : currentTargetSet.depth.format;
		final targetStencilFormat = currentTargetSet.stencil == null ? VkFormat.UNDEFINED : currentTargetSet.stencil.format;
		final stencilState = effectiveStencilState();
		final colorCount = currentTargetSet.colors.length;
		if( pipelineColorFormats.length != colorCount ) {
			pipelineColorFormats.resize(colorCount);
			pipelineColorMasks.resize(colorCount);
		}
		for( index in 0...colorCount ) {
			pipelineColorFormats[index] = currentTargetSet.colors[index].format;
			pipelineColorMasks[index] = (currentColorMasks >> (index * 4)) & 15;
		}
		if( colorCount > 1 && !capabilities.independentBlend )
			for( index in 1...colorCount )
				if( pipelineColorMasks[index] != pipelineColorMasks[0] )
					throw "Vulkan per-target color masks require the independentBlend device feature";
		pipelineDescription.update(currentShader, currentVertexLayout, pipelineColorFormats, targetDepthFormat, targetStencilFormat,
			currentTargetSet.samples, currentBlendState, pipelineColorMasks, stencilState, currentDepthClamp || driverDepthClamp, currentWireframe);
		final pipeline = pipelineManager.get(pipelineDescription);
		if( boundPipeline != pipeline ) {
			command.bindPipeline(GRAPHICS, pipeline);
			boundPipeline = pipeline;
			boundDynamicState = false;
		}
		applyDynamicDrawState();
		bindShaderDescriptors(false);
		command.bindIndexBuffer64(b.buffer, (haxe.Int64.ofInt(0) : hl.I64), b.stride == 4 ? VkIndexType.UINT32 : VkIndexType.UINT16);
		return b;
	}

	function applyDynamicDrawState() {
		final hasDepth = currentTargetSet != null && currentTargetSet.depth != null;
		final depthTest = hasDepth && currentDepthTest;
		final depthWrite = hasDepth && currentTargetSet.depthBinding != ReadOnly && currentTargetSet.depthBinding != NotBound && currentDepthWrite;
		final frontFace = rightHanded ? VkFrontFace.COUNTER_CLOCKWISE : VkFrontFace.CLOCKWISE;
		final biasEnabled = depthBias != 0 || slopeScaledDepthBias != 0;
		if( !boundDynamicState || boundCullMode != currentCullMode ) command.setCullMode(currentCullMode);
		if( !boundDynamicState || boundFrontFace != frontFace ) command.setFrontFace(frontFace);
		if( !boundDynamicState ) command.setPrimitiveTopology(VkPrimitiveTopology.TRIANGLE_LIST);
		if( !boundDynamicState || boundDepthTest != depthTest ) command.setDepthTestEnable(depthTest);
		if( !boundDynamicState || boundDepthWrite != depthWrite ) command.setDepthWriteEnable(depthWrite);
		if( !boundDynamicState || boundDepthCompare != currentDepthCompare ) command.setDepthCompareOp(currentDepthCompare);
		if( !boundDynamicState || boundBiasEnabled != biasEnabled ) command.setDepthBiasEnable(biasEnabled);
		if( !boundDynamicState || boundDepthBias != depthBias || boundSlopeScaledDepthBias != slopeScaledDepthBias )
			command.setDepthBias(depthBias, 0, slopeScaledDepthBias);
		boundCullMode = currentCullMode;
		boundFrontFace = frontFace;
		boundDepthTest = depthTest;
		boundDepthWrite = depthWrite;
		boundDepthCompare = currentDepthCompare;
		boundBiasEnabled = biasEnabled;
		boundDepthBias = depthBias;
		boundSlopeScaledDepthBias = slopeScaledDepthBias;
		boundDynamicState = true;
	}

	function effectiveStencilState():VulkanStencilState {
		if( currentStencilState == null || !currentStencilState.enabled || currentTargetSet == null || currentTargetSet.stencil == null ) {
			if( disabledStencilState == null ) {
				final face = new VulkanStencilFaceState(VkStencilOp.KEEP, VkStencilOp.KEEP, VkStencilOp.KEEP, VkCompareOp.ALWAYS);
				disabledStencilState = new VulkanStencilState(false, face, face, 0xFF, 0, 0);
			}
			return disabledStencilState;
		}
		if( currentTargetSet.depthBinding != ReadOnly )
			return currentStencilState;
		if( readOnlyStencilState == null )
			readOnlyStencilState = new VulkanStencilState(true, currentStencilState.front, currentStencilState.back,
				currentStencilState.readMask, 0, currentStencilState.reference);
		else
			readOnlyStencilState.update(true, currentStencilState.front, currentStencilState.back,
				currentStencilState.readMask, 0, currentStencilState.reference);
		return readOnlyStencilState;
	}

	function bindShaderDescriptors(compute:Bool) {
		final resolvedTextures = resolvedTextureScratch;
		final setCount = currentShader.descriptorSets.length;
		if( setCount == 0 ) {
			if( compute ) boundComputeDescriptorState = currentShader else boundDescriptorState = currentShader;
			return;
		}
		final frame = frames[currentFrameIndex];
		if( descriptorSetScratch.length < setCount ) descriptorSetScratch = new hl.NativeArray<VkDescriptorSet>(setCount);
		final maxOffsets = currentShader.programLayout.constantBlocks.length;
		if( dynamicOffsetScratch.length < maxOffsets ) dynamicOffsetScratch = new hl.NativeArray<Int>(maxOffsets);
		var offsetCount = 0;
		for( setIndex in 0...setCount ) {
			final metadata = currentShader.descriptorSets[setIndex];
			if( metadata.bindless ) {
				if( bindlessDescriptors == null || frame.bindlessGeneration == null )
					throw "Vulkan bindless descriptor generation is unavailable";
				bindlessDescriptors.sync(frame.bindlessGeneration);
				descriptorSetScratch[setIndex] = frame.bindlessGeneration.set;
				continue;
			}
			for( blockIndex in 0...metadata.blocks.length ) {
				final block = metadata.blocks[blockIndex];
				final upload = frame.shaderConstants.get(metadata.blockIds[blockIndex]);
				if( upload == null )
					throw 'Vulkan ${compute ? "dispatch" : "draw"} requires uploaded constant block ${block.name} at set ${block.set}, binding ${block.binding}';
				final alignment = hxd.Math.imax(1, limits.minUniformBufferOffsetAlignment.toInt());
				if( upload.offset % alignment != 0 )
					throw 'Vulkan dynamic constant offset ${upload.offset} for ${block.name} is not aligned to $alignment';
				if( upload.offset + block.size > haxe.Int64.toInt(upload.buffer.size) )
					throw 'Vulkan constant range for ${block.name} exceeds ${upload.buffer.debugName}';
				dynamicOffsetScratch[offsetCount++] = upload.offset;
			}
			final fast = frame.resolvedDescriptorSets.get(metadata.id);
			if( fast != null && fast.revision == metadata.revision && fast.entry.matchesMetadata(metadata, currentShader.descriptorSetLayouts[setIndex]) ) {
				descriptorSetScratch[setIndex] = fast.entry.set;
				frame.descriptorCacheHitCount++;
				continue;
			}
			var hash = metadata.id;
			for( blockIndex in 0...metadata.blocks.length )
				hash = (hash * 31) ^ frame.shaderConstants.get(metadata.blockIds[blockIndex]).buffer.debugId;
			for( resource in metadata.resources )
				switch( resource.descriptorType ) {
				case VulkanDescriptorType.CombinedImageSampler, VulkanDescriptorType.StorageImage:
					for( value in resolvedTextures.get(resource.logicalId) )
						hash = (hash * 31) ^ value.image.allocation.debugId;
				case VulkanDescriptorType.UniformBuffer, VulkanDescriptorType.StorageBuffer:
					for( allocationId in resource.allocationIds ) {
						final buffer = bufferBindings.get(allocationId);
						final native:VulkanBuffer = @:privateAccess buffer.vbuf;
						hash = (hash * 31) ^ native.debugId;
					}
				default:
				}
			final entries = frame.descriptorSets.get(hash);
			var set:VkDescriptorSet = null;
			var resolvedEntry:VulkanDescriptorCacheEntry = null;
			if( entries != null )
				for( entry in entries ) {
					if( !entry.matchesMetadata(metadata, currentShader.descriptorSetLayouts[setIndex]) ) continue;
					var bufferIndex = 0;
					var imageIndex = 0;
					var matches = true;
					for( blockIndex in 0...metadata.blocks.length ) {
						final block = metadata.blocks[blockIndex];
						final buffer = frame.shaderConstants.get(metadata.blockIds[blockIndex]).buffer;
						if( !entry.matchesBuffer(bufferIndex, buffer, haxe.Int64.ofInt(block.size)) ) {
							matches = false;
							break;
						}
						bufferIndex++;
					}
					if( !matches ) continue;
					for( resource in metadata.resources ) {
						switch( resource.descriptorType ) {
						case VulkanDescriptorType.CombinedImageSampler, VulkanDescriptorType.StorageImage:
							for( value in resolvedTextures.get(resource.logicalId) ) {
								if( !entry.matchesImage(imageIndex, value.image, value.view, value.sampler) ) matches = false;
								imageIndex++;
							}
						case VulkanDescriptorType.UniformBuffer, VulkanDescriptorType.StorageBuffer:
							for( allocationId in resource.allocationIds ) {
								final buffer = bufferBindings.get(allocationId);
								final native:VulkanBuffer = @:privateAccess buffer.vbuf;
								if( !entry.matchesBuffer(bufferIndex, native, native.size) ) matches = false;
								bufferIndex++;
							}
						default:
						}
					}
					if( matches ) {
						set = entry.set;
						resolvedEntry = entry;
						frame.descriptorCacheHitCount++;
						break;
					}
				}
			if( set == null ) {
				frame.descriptorCacheMissCount++;
				set = frame.descriptorArena.allocate(currentShader.descriptorSetLayouts[setIndex], metadata.descriptorCount);
				final buffers:Array<VulkanBuffer> = [];
				final bufferHandles:Array<limen.graphics.vulkan.memory.Memory.VkBuffer> = [];
				final bufferRanges:Array<haxe.Int64> = [];
				final images:Array<VulkanTexture> = [];
				final views:Array<VkImageView> = [];
				final samplers:Array<VkSampler> = [];
				for( blockIndex in 0...metadata.blocks.length ) {
					final block = metadata.blocks[blockIndex];
					final upload = frame.shaderConstants.get(metadata.blockIds[blockIndex]);
					buffers.push(upload.buffer);
					bufferHandles.push(upload.buffer.buffer);
					bufferRanges.push(haxe.Int64.ofInt(block.size));
					ctx.updateDescriptorBuffer(set, block.binding, VkDescriptorType.UNIFORM_BUFFER_DYNAMIC, upload.buffer.buffer,
						(haxe.Int64.ofInt(0) : hl.I64), (haxe.Int64.ofInt(block.size) : hl.I64));
					frame.descriptorUpdateCount++;
				}
				for( resource in metadata.resources )
					switch( resource.descriptorType ) {
					case VulkanDescriptorType.CombinedImageSampler:
						final values = resolvedTextures.get(resource.logicalId);
						for( element => value in values ) {
							images.push(value.image);
							views.push(value.view);
							samplers.push(value.sampler);
							ctx.updateDescriptorImageSampler(set, resource.binding, element, value.view, value.sampler, VkImageLayout.SHADER_READ_ONLY_OPTIMAL);
							frame.descriptorUpdateCount++;
						}
					case VulkanDescriptorType.StorageImage:
						final values = resolvedTextures.get(resource.logicalId);
						for( element => value in values ) {
							images.push(value.image);
							views.push(value.view);
							samplers.push(null);
							ctx.updateDescriptorStorageImage(set, resource.binding, element, value.view, VkImageLayout.GENERAL);
							frame.descriptorUpdateCount++;
						}
					case VulkanDescriptorType.UniformBuffer, VulkanDescriptorType.StorageBuffer:
						for( element => allocationId in resource.allocationIds ) {
							final buffer = bufferBindings.get(allocationId);
							final native:VulkanBuffer = @:privateAccess buffer.vbuf;
							buffers.push(native);
							bufferHandles.push(native.buffer);
							bufferRanges.push(native.size);
							ctx.updateDescriptorBufferElement(set, resource.binding, element,
								resource.descriptorType == VulkanDescriptorType.UniformBuffer ? VkDescriptorType.UNIFORM_BUFFER : VkDescriptorType.STORAGE_BUFFER,
								native.buffer, (haxe.Int64.ofInt(0) : hl.I64), (native.size : hl.I64));
							frame.descriptorUpdateCount++;
						}
					default:
					}
				final entry = new VulkanDescriptorCacheEntry(metadata, currentShader.descriptorSetLayouts[setIndex], set,
					buffers, bufferHandles, bufferRanges, images, views, samplers);
				resolvedEntry = entry;
				if( entries == null ) frame.descriptorSets.set(hash, [entry]) else entries.push(entry);
				frame.recordDescriptorEntry();
			}
			frame.resolvedDescriptorSets.set(metadata.id, {revision: metadata.revision, entry: resolvedEntry});
			descriptorSetScratch[setIndex] = set;
		}
		final previousSets = compute ? boundComputeSets : boundGraphicsSets;
		final previousOffsets = compute ? boundComputeOffsets : boundGraphicsOffsets;
		var unchanged = (compute ? boundComputeDescriptorState : boundDescriptorState) == currentShader
			&& (compute ? boundComputeSetCount : boundGraphicsSetCount) == setCount
			&& (compute ? boundComputeOffsetCount : boundGraphicsOffsetCount) == offsetCount;
		if( unchanged ) {
			for( index in 0...setCount ) if( previousSets[index] != descriptorSetScratch[index] ) unchanged = false;
			for( index in 0...offsetCount ) if( previousOffsets[index] != dynamicOffsetScratch[index] ) unchanged = false;
		}
		if( unchanged ) return;
		command.bindDescriptorSetsNative(compute ? COMPUTE : GRAPHICS, currentShader.layout, 0, setCount, descriptorSetScratch, offsetCount, dynamicOffsetScratch);
		if( compute ) {
			if( boundComputeSets.length < setCount ) boundComputeSets = new hl.NativeArray<VkDescriptorSet>(setCount);
			if( boundComputeOffsets.length < offsetCount ) boundComputeOffsets = new hl.NativeArray<Int>(offsetCount);
			for( index in 0...setCount ) boundComputeSets[index] = descriptorSetScratch[index];
			for( index in 0...offsetCount ) boundComputeOffsets[index] = dynamicOffsetScratch[index];
			boundComputeSetCount = setCount;
			boundComputeOffsetCount = offsetCount;
			boundComputeDescriptorState = currentShader;
		} else {
			if( boundGraphicsSets.length < setCount ) boundGraphicsSets = new hl.NativeArray<VkDescriptorSet>(setCount);
			if( boundGraphicsOffsets.length < offsetCount ) boundGraphicsOffsets = new hl.NativeArray<Int>(offsetCount);
			for( index in 0...setCount ) boundGraphicsSets[index] = descriptorSetScratch[index];
			for( index in 0...offsetCount ) boundGraphicsOffsets[index] = dynamicOffsetScratch[index];
			boundGraphicsSetCount = setCount;
			boundGraphicsOffsetCount = offsetCount;
			boundDescriptorState = currentShader;
		}
	}


	function prepareShaderBuffers(compute:Bool) {
		for( allocationId => buffer in bufferBindings ) {
			final native:VulkanBuffer = @:privateAccess buffer.vbuf;
			if( native == null || native.disposed )
				throw 'Vulkan shader buffer $allocationId was disposed before ${compute ? "dispatch" : "draw"}';
			final previous = currentShader.descriptorBuffers.get(allocationId);
			if( previous == null || previous.buffer != native || previous.handle != native.buffer || previous.range != native.size ) {
				currentShader.descriptorBuffers.set(allocationId, {buffer: native, handle: native.buffer, range: native.size});
				final sets = currentShader.bufferDescriptorSets.get(allocationId);
				if( sets != null ) for( set in sets ) set.revision++;
			}
			final kind = bufferBindingKinds.get(allocationId);
			final next = switch( kind ) {
			case Uniform, Partial: compute ? VulkanBufferState.ComputeUniformRead : VulkanBufferState.UniformRead;
			case Storage, StoragePartial: compute ? VulkanBufferState.StorageRead : VulkanBufferState.GraphicsStorageRead;
			case RW, RWPartial: compute ? VulkanBufferState.StorageReadWrite : VulkanBufferState.GraphicsStorageReadWrite;
			}
			if( renderingStarted && native.state != next )
				suspendRendering();
			if( native.state != next )
				VulkanResourceState.transitionBuffer(command, native, next, haxe.Int64.ofInt(0), native.size);
			native.lastSubmission = currentSubmissionSerial;
		}
	}

	function prepareShaderTextures(compute:Bool) {
		final resolved = resolvedTextureScratch;
		for( resource in currentShader.programLayout.descriptors ) {
			final storage = resource.descriptorType == VulkanDescriptorType.StorageImage;
			if( resource.descriptorType != VulkanDescriptorType.CombinedImageSampler && !storage )
				continue;
			if( resource.allocationIds.length != resource.count )
				throw 'Texture resource ${resource.name} has ${resource.allocationIds.length} HxSL slots for ${resource.count} descriptors';
			var values = resolved.get(resource.logicalId);
			if( values == null ) {
				values = [];
				resolved.set(resource.logicalId, values);
			}
			final metadata = currentShader.descriptorSets[resource.set];
			var textureStates = metadata.textureStates.get(resource.logicalId);
			if( textureStates == null ) {
				textureStates = [];
				metadata.textureStates.set(resource.logicalId, textureStates);
			}
			var valueIndex = 0;
			for( allocationId in resource.allocationIds ) {
				final texture = textureBindings.get(allocationId);
				if( texture == null )
					throw 'Vulkan ${compute ? "dispatch" : "draw"} requires uploaded texture resource $allocationId';
				final image:VulkanTexture = texture.t;
				if( image == null || image.disposed )
					throw 'Vulkan texture resource $allocationId is not allocated';
				if( storage && (!texture.flags.has(Writable) || !image.usage.has(STORAGE)) )
					throw 'Texture ${texture.id} was allocated without Writable storage-image support';
				final baseMip = texture.startingMip;
				if( baseMip < 0 || baseMip >= image.mipCount )
					throw 'Texture ${texture.id} starting mip $baseMip is outside 0...${image.mipCount - 1}';
				final levelCount = storage || texture.mipMap == None ? 1 : image.mipCount - baseMip;
				final baseLayer = texture.slice > 0 ? texture.slice - 1 : 0;
				final layerCount = texture.slice > 0 ? 1 : image.layerCount;
				if( baseLayer < 0 || baseLayer + layerCount > image.layerCount )
					throw 'Texture ${texture.id} view layers [$baseLayer, ${baseLayer + layerCount}) exceed ${image.layerCount}';
				if( !compute && currentTargetSet != null ) {
					for( attachment in currentTargetSet.colors )
						if( attachment.overlaps(image, baseMip, levelCount, baseLayer, layerCount) )
							throw 'Texture ${texture.id} mip/layer range is simultaneously bound as a color attachment and sampled texture';
					if( currentTargetSet.depth != null && currentTargetSet.depth.overlaps(image, baseMip, levelCount, baseLayer, layerCount) )
						throw 'Texture ${texture.id} mip/layer range is simultaneously bound as a depth/stencil attachment and sampled texture';
				}
				var sampleAspect = new haxe.EnumFlags<VkImageAspectFlag>();
				sampleAspect.set(texture.isDepth() ? DEPTH : COLOR);
				final targetState = storage ? VulkanImageState.ShaderStorageReadWrite
					: compute ? VulkanImageState.ComputeShaderRead : VulkanImageState.ShaderRead;
				for( layer in baseLayer...baseLayer + layerCount )
					for( mip in baseMip...baseMip + levelCount )
						if( image.getState(mip, layer, texture.isDepth() ? DEPTH : COLOR) != targetState ) {
							suspendRendering();
							VulkanResourceState.transitionImage(command, image, mip, layer, targetState, sampleAspect);
						}
				image.lastSubmission = currentSubmissionSerial;
				if( valueIndex == values.length ) values.push(new VulkanResolvedTexture());
				final value = values[valueIndex];
				final bits = @:privateAccess texture.bits;
				final flags = texture.flags.toInt();
				if( value.texture != texture || value.image != image || value.bits != bits || value.flags != flags || value.filterable != image.filterable || value.storage != storage ) {
					if( storage ) {
						final properties = new VkFormatProperties();
						ctx.getPdeviceFormatProps(image.format, properties);
						if( (properties.optimalTilingFeatures & cast VkFormatFeature.STORAGE_IMAGE) == 0 )
							throw 'Texture ${texture.id} format ${texture.format} does not support Vulkan storage images';
					}
					final viewData = getTextureView(texture, image, baseMip, levelCount, baseLayer, layerCount);
					var sampler:VkSampler = null;
					var samplerKey = "storage";
					if( !storage ) {
						final resolvedSampler = samplerCache.get(texture, image.filterable);
						samplerKey = resolvedSampler.key;
						sampler = resolvedSampler.sampler;
					}
					value.update(texture, image, bits, flags, storage, viewData.view, viewData.key, sampler, samplerKey,
						baseMip, levelCount, baseLayer, layerCount);
				}
				final previousState = valueIndex < textureStates.length ? textureStates[valueIndex] : null;
				if( previousState == null || previousState.image != value.image || previousState.view != value.view || previousState.sampler != value.sampler ) {
					if( previousState == null )
						textureStates.push({image: value.image, view: value.view, sampler: value.sampler});
					else {
						previousState.image = value.image;
						previousState.view = value.view;
						previousState.sampler = value.sampler;
					}
					metadata.revision++;
				}
				valueIndex++;
			}
			if( values.length != valueIndex ) values.resize(valueIndex);
			if( textureStates.length != valueIndex ) {
				textureStates.resize(valueIndex);
				metadata.revision++;
			}
		}
	}

	function getTextureView(texture:h3d.mat.Texture, image:VulkanTexture, baseMip:Int, levelCount:Int, baseLayer:Int, layerCount:Int):VulkanImageViewEntry {
		final type:VkImageViewType = texture.slice > 0 ? TYPE_2D : texture.flags.has(Cube) ? TYPE_CUBE : texture.flags.has(IsArray) ? TYPE_2D_ARRAY : TYPE_2D;
		final defaultView = texture.slice == 0 && baseMip == 0 && levelCount == image.mipCount && baseLayer == 0 && layerCount == image.layerCount && !texture.hasStencil();
		if( defaultView )
			return image.defaultViewEntry;
		var aspect = new haxe.EnumFlags<VkImageAspectFlag>();
		aspect.set(texture.isDepth() ? DEPTH : COLOR);
		return getImageView(texture, image, type, image.format, aspect, baseMip, levelCount, baseLayer, layerCount);
	}

	function getImageView(texture:h3d.mat.Texture, image:VulkanTexture, type:VkImageViewType, format:VkFormat,
		aspect:haxe.EnumFlags<VkImageAspectFlag>, baseMip:Int, levelCount:Int, baseLayer:Int, layerCount:Int):VulkanImageViewEntry {
		final aspectBits = aspect.toInt();
		final cached = @:privateAccess image.getExtraView(type, format, aspectBits, baseMip, levelCount, baseLayer, layerCount);
		if( cached != null ) return cached;
		final key = '${cast(type, Int)}:${cast(format, Int)}:$aspectBits:$baseMip:$levelCount:$baseLayer:$layerCount';
		final info = new VkImageViewCreateInfo();
		info.image = image.image;
		info.viewType = type;
		info.format = format;
		info.baseMipLevel = baseMip;
		info.levelCount = levelCount;
		info.baseArrayLayer = baseLayer;
		info.layerCount = layerCount;
		info.aspectMask = aspect;
		final view = ctx.createImageView(info);
		if( view == null )
			throw Runtime.error('Failed to create Vulkan texture view ${image.debugName}[$key]');
		ctx.setImageViewName(view, @:privateAccess '${image.debugName}-view-$key'.toUtf8());
		final entry = new VulkanImageViewEntry(type, format, aspectBits, baseMip, levelCount, baseLayer, layerCount, view, key);
		@:privateAccess image.setExtraView(entry);
		return entry;
	}

	function validateShaderResources(compute:Bool) {
		for( resource in currentShader.programLayout.descriptors )
			switch( resource.descriptorType ) {
			case VulkanDescriptorType.CombinedImageSampler:
				if( textureBindingsShaderKey != currentShader.cacheKey )
					throw 'Vulkan ${compute ? "dispatch" : "draw"} requires texture uploads for shader ${currentShader.cacheKey}';
				for( allocationId in resource.allocationIds )
					if( !textureBindings.exists(allocationId) )
						throw 'Vulkan ${compute ? "dispatch requires texture-resource" : "draw requires sampled-resource"} binding for $allocationId';
			case VulkanDescriptorType.StorageImage:
				if( textureBindingsShaderKey != currentShader.cacheKey )
					throw 'Vulkan ${compute ? "dispatch" : "draw"} requires texture uploads for shader ${currentShader.cacheKey}';
				for( allocationId in resource.allocationIds )
					if( !textureBindings.exists(allocationId) )
						throw 'Vulkan ${compute ? "dispatch" : "draw"} requires storage-image binding for $allocationId';
			case VulkanDescriptorType.UniformBuffer, VulkanDescriptorType.StorageBuffer:
				if( bufferBindingsShaderKey != currentShader.cacheKey )
					throw 'Vulkan ${compute ? "dispatch" : "draw"} requires buffer uploads for shader ${currentShader.cacheKey}';
				for( allocationId in resource.allocationIds )
					if( !bufferBindings.exists(allocationId) )
						throw 'Vulkan ${compute ? "dispatch" : "draw"} requires buffer-resource binding for $allocationId';
			default:
		}
	}

	inline function bindlessTextureBits(texture:h3d.mat.Texture):Int {
		return @:privateAccess texture.bits & (h3d.mat.Texture.__startingMip_mask | h3d.mat.Texture.slice_mask);
	}

	function bindlessTextureView(texture:h3d.mat.Texture, image:VulkanTexture):VulkanBindlessResolvedView {
		final baseMip = texture.startingMip;
		if( baseMip < 0 || baseMip >= image.mipCount )
			throw 'Texture ${texture.id} starting mip $baseMip is outside 0...${image.mipCount - 1}';
		final levelCount = image.mipCount - baseMip;
		final baseLayer = texture.slice > 0 ? texture.slice - 1 : 0;
		final layerCount = texture.slice > 0 ? 1 : image.layerCount;
		if( baseLayer < 0 || baseLayer + layerCount > image.layerCount )
			throw 'Texture ${texture.id} view layers [$baseLayer, ${baseLayer + layerCount}) exceed ${image.layerCount}';
		final resolved = getTextureView(texture, image, baseMip, levelCount, baseLayer, layerCount);
		bindlessResolvedView.image = image;
		bindlessResolvedView.view = resolved.view;
		bindlessResolvedView.key = resolved.key;
		bindlessResolvedView.baseMip = baseMip;
		bindlessResolvedView.levelCount = levelCount;
		bindlessResolvedView.baseLayer = baseLayer;
		bindlessResolvedView.layerCount = layerCount;
		return bindlessResolvedView;
	}

	function refreshBindlessTextureSlot(slot:VulkanBindlessTextureSlot):VulkanBindlessResolvedView {
		final texture = slot.texture;
		final image:VulkanTexture = texture.t;
		if( image == null || image.disposed )
			throw 'Vulkan bindless texture ${texture.id} is not allocated';
		final previousBits = @:privateAccess texture.bits;
		if( previousBits != slot.bits )
			@:privateAccess texture.loadBits(slot.bits);
		var resolved:VulkanBindlessResolvedView;
		try {
			resolved = bindlessTextureView(texture, image);
		} catch( error:Dynamic ) {
			if( previousBits != slot.bits )
				@:privateAccess texture.loadBits(previousBits);
			throw error;
		}
		if( previousBits != slot.bits )
			@:privateAccess texture.loadBits(previousBits);
		if( slot.image != image || slot.viewKey != resolved.key ) {
			bindlessDescriptors.updateImage(slot.index, resolved.view, VkImageLayout.SHADER_READ_ONLY_OPTIMAL);
			slot.image = image;
			slot.viewKey = resolved.key;
		}
		return resolved;
	}

	override function getTextureHandle(texture:h3d.mat.Texture):h3d.mat.TextureHandle {
		if( bindlessDescriptors == null )
			throw 'Vulkan bindless textures are unavailable; ${capabilities.diagnostics}';
		if( texture.t == null ) {
			if( texture.realloc == null )
				throw 'Cannot create a Vulkan bindless handle for disposed texture ${texture.id}';
			texture.alloc();
			texture.realloc();
		}
		final bits = @:privateAccess texture.bits;
		var handles = textureHandles.get(texture);
		if( handles == null ) {
			handles = new Map();
			textureHandles.set(texture, handles);
		}
		var handle = handles.get(bits);
		if( handle != null )
			return handle;
		final image:VulkanTexture = texture.t;
		final sampler = samplerCache.get(texture, image.filterable);
		var samplerIndex = samplerHandles.get(sampler.key);
		if( samplerIndex == null ) {
			samplerIndex = bindlessDescriptors.allocateSampler(sampler.sampler);
			samplerHandles.set(sampler.key, samplerIndex);
		}
		final viewBits = bindlessTextureBits(texture);
		var imageSlots = textureImageSlots.get(texture);
		if( imageSlots == null ) {
			imageSlots = new Map();
			textureImageSlots.set(texture, imageSlots);
		}
		var imageSlot = imageSlots.get(viewBits);
		if( imageSlot == null ) {
			final resolved = bindlessTextureView(texture, image);
			final imageIndex = bindlessDescriptors.allocateImage(resolved.view, VkImageLayout.SHADER_READ_ONLY_OPTIMAL);
			imageSlot = new VulkanBindlessTextureSlot(texture, viewBits, imageIndex, image, resolved.key);
			imageSlots.set(viewBits, imageSlot);
			if( imageIndex >= bindlessTextureSlots.length )
				bindlessTextureSlots.resize(imageIndex + 1);
			bindlessTextureSlots[imageIndex] = imageSlot;
		} else
			refreshBindlessTextureSlot(imageSlot);
		handle = @:privateAccess new h3d.mat.TextureHandle(texture, haxe.Int64.make(samplerIndex, imageSlot.index));
		handles.set(bits, handle);
		return handle;
	}

	override function getBufferHandle(buffer:h3d.Buffer):h3d.BufferHandle {
		if( bindlessDescriptors == null )
			throw 'Vulkan bindless buffers are unavailable; ${capabilities.diagnostics}';
		final native:VulkanBuffer = @:privateAccess buffer.vbuf;
		if( native == null || native.disposed )
			throw 'Cannot create a Vulkan bindless handle for disposed buffer ${buffer.id}';
		var handle = bufferHandles.get(buffer);
		if( handle == null ) {
			final index = bindlessDescriptors.allocateBuffer(native.buffer, native.size);
			handle = @:privateAccess new h3d.BufferHandle(buffer, index);
			bufferHandles.set(buffer, handle);
		}
		return handle;
	}

	function selectTextureHandle(handle:h3d.mat.TextureHandle) {
		final compute = currentShader != null && currentShader.compute != null;
		if( handle == null || handle.handle == -1 )
			throw "Vulkan bindless texture handle is invalid";
		final texture = handle.texture;
		if( texture == null )
			throw "Vulkan bindless texture handle has no texture";
		if( texture.t == null ) {
			if( texture.realloc == null )
				throw 'Vulkan bindless texture ${texture.id} was disposed';
			final selectedShader = currentShader == null ? null : currentShader.shader;
			texture.alloc();
			texture.realloc();
			if( selectedShader != null && (currentShader == null || currentShader.shader != selectedShader) )
				throw "Shader change detected while reallocating a Vulkan bindless texture";
		}
		final index = handle.handle.low;
		final slot = index < 0 || index >= bindlessTextureSlots.length ? null : bindlessTextureSlots[index];
		if( slot == null || slot.texture != texture || slot.index != index )
			throw 'Vulkan bindless texture handle index $index is stale';
		final resolved = refreshBindlessTextureSlot(slot);
		if( !compute && currentTargetSet != null ) {
			for( attachment in currentTargetSet.colors )
				if( attachment.overlaps(resolved.image, resolved.baseMip, resolved.levelCount, resolved.baseLayer, resolved.layerCount) )
					throw 'Texture ${texture.id} is simultaneously bound as a color attachment and bindless sampled texture';
			if( currentTargetSet.depth != null && currentTargetSet.depth.overlaps(resolved.image, resolved.baseMip,
				resolved.levelCount, resolved.baseLayer, resolved.layerCount) )
				throw 'Texture ${texture.id} is simultaneously bound as a depth/stencil attachment and bindless sampled texture';
		}
		final targetState = compute ? VulkanImageState.ComputeShaderRead : VulkanImageState.ShaderRead;
		var aspect = new haxe.EnumFlags<VkImageAspectFlag>();
		aspect.set(texture.isDepth() ? DEPTH : COLOR);
		for( layer in resolved.baseLayer...resolved.baseLayer + resolved.layerCount )
			for( mip in resolved.baseMip...resolved.baseMip + resolved.levelCount )
				if( resolved.image.getState(mip, layer, texture.isDepth() ? DEPTH : COLOR) != targetState ) {
					suspendRendering();
					VulkanResourceState.transitionImage(command, resolved.image, mip, layer, targetState, aspect);
				}
		resolved.image.lastSubmission = currentSubmissionSerial;
		@:privateAccess texture.lastFrame = currentSubmissionSerial;
	}

	override function selectTextureHandles(handles:Array<h3d.mat.TextureHandle>) {
		for( handle in handles )
			selectTextureHandle(handle);
	}

	function selectBufferHandle(handle:h3d.BufferHandle) {
		final targetState = currentShader != null && currentShader.compute != null
			? VulkanBufferState.StorageRead : VulkanBufferState.GraphicsStorageRead;
		if( handle == null || handle.handle < 0 )
			throw "Vulkan bindless buffer handle is invalid";
		final buffer = handle.buffer;
		final native:VulkanBuffer = buffer == null ? null : @:privateAccess buffer.vbuf;
		if( native == null || native.disposed || bufferHandles.get(buffer) != handle )
			throw 'Vulkan bindless buffer handle index ${handle.handle} is stale';
		if( renderingStarted && native.state != targetState )
			suspendRendering();
		if( native.state != targetState )
			VulkanResourceState.transitionBuffer(command, native, targetState, haxe.Int64.ofInt(0), native.size);
		native.lastSubmission = currentSubmissionSerial;
		@:privateAccess buffer.lastFrame = currentSubmissionSerial;
	}

	override function selectBufferHandles(handles:Array<h3d.BufferHandle>) {
		for( handle in handles )
			selectBufferHandle(handle);
	}

	override function computeDispatch(x:Int = 1, y:Int = 1, z:Int = 1, barrier:Bool = true) {
		if( !frameStarted )
			throw "Vulkan compute dispatch requires an active frame";
		if( !capabilities.graphicsQueueCompute )
			throw 'Vulkan compute is unavailable because graphics queue family ${capabilities.graphicsQueueFamily} lacks VK_QUEUE_COMPUTE_BIT';
		if( currentShader == null || currentShader.compute == null || currentShader.vertex != null || currentShader.fragment != null )
			throw "Vulkan compute dispatch requires an active compute shader";
		if( x < 0 || y < 0 || z < 0 )
			throw 'Vulkan compute dispatch group counts must be non-negative, got ${x}x${y}x${z}';
		if( x > limits.maxComputeWorkGroupCount || y > limits.maxComputeWorkGroupCount1 || z > limits.maxComputeWorkGroupCount2 )
			throw 'Vulkan compute dispatch ${x}x${y}x${z} exceeds device limits '
				+ '${limits.maxComputeWorkGroupCount}x${limits.maxComputeWorkGroupCount1}x${limits.maxComputeWorkGroupCount2}';
		if( x == 0 || y == 0 || z == 0 )
			return;
		suspendRendering();
		validateShaderResources(true);
		prepareShaderBuffers(true);
		prepareShaderTextures(true);
		final pipeline = computePipelineManager.get(currentShader);
		if( boundComputePipeline != pipeline ) {
			command.bindComputePipeline(pipeline.handle);
			boundComputePipeline = pipeline;
		}
		pipeline.lastSubmission = currentSubmissionSerial;
		bindShaderDescriptors(true);
		command.dispatch(x, y, z);
		if( barrier )
			memoryBarrier();
	}

	override function memoryBarrier() {
		if( !frameStarted )
			throw "Vulkan memoryBarrier requires an active frame";
		suspendRendering();
		final destinationStages:hl.I64 = cast ((VkPipelineStage2.COMPUTE_SHADER : haxe.Int64)
			| (VkPipelineStage2.VERTEX_SHADER : haxe.Int64) | (VkPipelineStage2.FRAGMENT_SHADER : haxe.Int64));
		final destinationAccess:hl.I64 = cast ((VkAccess2.SHADER_READ : haxe.Int64) | (VkAccess2.SHADER_WRITE : haxe.Int64));
		VulkanResourceState.recordBarrier();
		command.memoryBarrier2(VkPipelineStage2.COMPUTE_SHADER, VkAccess2.SHADER_WRITE, destinationStages, destinationAccess);
	}

	// Timestamp intervals use TOP_OF_PIPE for their start and BOTTOM_OF_PIPE for their end.
	// Standalone timestamps use the same late boundary as elapsed-query completion.
	override function allocQuery(kind:QueryKind):Query {
		return queryManager.alloc(kind);
	}

	override function deleteQuery(q:Query) {
		queryManager.delete(q);
	}

	override function beginQuery(q:Query) {
		final query:VulkanQuery = q;
		if (!frameStarted)
			throw "Vulkan query begin requires an active frame";
		if (query.kind == TimeStamp)
			throw "use endQuery() for timestamp queries";
		if (query.kind == Samples && activeSampleQuery != null)
			throw "Nested Vulkan Samples queries are not supported";
		if (query.kind == Samples && renderingStarted)
			suspendRendering();
		final generation = queryManager.start(query, currentFrameIndex, command, suspendRendering);
		activeQueryIntervals++;
		switch (query.kind) {
		case Samples:
			activeSampleQuery = query;
			activeSampleGeneration = generation;
			activeSampleNativeStarted = false;
		case TimeElapsed:
			command.writeTimestamp2(VkPipelineStage2.TOP_OF_PIPE, generation.page.pool, generation.firstSlot);
		case TimeStamp:
		}
	}

	override function endQuery(q:Query) {
		final query:VulkanQuery = q;
		if (!frameStarted)
			throw "Vulkan query end requires an active frame";
		switch (query.kind) {
		case TimeStamp:
			final generation = queryManager.start(query, currentFrameIndex, command, suspendRendering);
			command.writeTimestamp2(VkPipelineStage2.BOTTOM_OF_PIPE, generation.page.pool, generation.firstSlot);
			queryManager.endTimestamp(query);
		case Samples:
			if (query != activeSampleQuery || query.state != Recording)
				throw "Vulkan Samples query end called without a matching beginQuery";
			if (!activeSampleNativeStarted) {
				beginRendering();
				beginActiveSampleQuery();
			}
			command.endQuery(activeSampleGeneration.page.pool, activeSampleGeneration.firstSlot);
			activeSampleQuery = null;
			activeSampleGeneration = null;
			activeSampleNativeStarted = false;
			activeQueryIntervals--;
			queryManager.end(query);
		case TimeElapsed:
			if (query.state != Recording)
				throw "Vulkan TimeElapsed query end called without a matching beginQuery";
			final generation = query.current;
			command.writeTimestamp2(VkPipelineStage2.BOTTOM_OF_PIPE, generation.page.pool, generation.firstSlot + 1);
			activeQueryIntervals--;
			queryManager.end(query);
		}
	}

	override function queryResultAvailable(q:Query) {
		final query:VulkanQuery = q;
		if (query.resultValid)
			return true;
		refreshQueryCompletions();
		return queryManager.available(query);
	}

	override function queryResult(q:Query):Float {
		final query:VulkanQuery = q;
		if (query.resultValid)
			return query.result;
		if (query.state == Idle || query.state == Recording)
			return queryManager.requireResult(query);
		if (query.state == PendingSubmission)
			submitQuerySynchronously(query);
		else if (query.state == InFlight)
			waitForQuerySubmission(query.current);
		return queryManager.requireResult(query);
	}

	function beginActiveSampleQuery() {
		if (activeSampleQuery == null || activeSampleNativeStarted)
			return;
		var flags = new haxe.EnumFlags<VkQueryControlFlag>();
		flags.set(PRECISE);
		command.beginQuery(activeSampleGeneration.page.pool, activeSampleGeneration.firstSlot, flags);
		activeSampleNativeStarted = true;
	}

	function refreshQueryCompletions() {
		for (index => frame in frames) {
			if (!queryManager.hasSubmitted(index))
				continue;
			if (frame.submissionSerial <= completedSubmissionSerial) {
				queryManager.completeFrame(index);
				continue;
			}
			final status = ctx.getFenceStatus(frame.fence);
			if (status == 0) {
				completedSubmissionSerial = hxd.Math.imax(completedSubmissionSerial, frame.submissionSerial);
				queryManager.completeFrame(index);
			} else if (status != 1)
				throw Runtime.error("Failed to poll Vulkan query submission fence");
		}
	}

	function submitQuerySynchronously(query:VulkanQuery) {
		if (activeQueryIntervals != 0)
			throw "Cannot synchronously resolve a Vulkan query while another query interval is active";
		final savedTarget = currentTargetSet;
		final submittedFrame = currentFrameIndex;
		if (query.current.frameIndex != submittedFrame)
			throw "Vulkan pending query belongs to a different frame";
		suspendRendering();
		if (command.end() != 0)
			throw Runtime.error("Failed to end Vulkan query command buffer");
		frameStarted = false;
		final frame = frames[submittedFrame];
		if (ctx.submitFrame(frame.command, frame.imageAvailableConsumed ? null : frame.imageAvailable, null, frame.fence) != 0)
			throw Runtime.error("Failed to submit Vulkan query command buffer");
		frame.imageAvailableConsumed = true;
		frame.submissionSerial = currentSubmissionSerial++;
		queryManager.submitted(submittedFrame, frame.submissionSerial);
		waitForQuerySubmission(query.current);
		deferredDestroy.collect(completedSubmissionSerial);
		readbackManager.completeFrame(submittedFrame);
		uploadManager.beginFrame(submittedFrame);
		frame.reclaimDescriptors();
		frame.shaderConstants.clear();
		if (ctx.resetFence(frame.fence) != 0)
			throw Runtime.error("Failed to reset Vulkan query submission fence");
		if (frame.command.reset() != 0)
			throw Runtime.error("Failed to reset Vulkan query command buffer");
		final inf = new VkCommandBufferBeginInfo();
		inf.flags.set(ONE_TIME_SUBMIT);
		command = frame.command;
		if (command.begin(inf) != 0)
			throw Runtime.error("Failed to resume Vulkan command recording after query submission");
		queryManager.beginFrame(submittedFrame, command);
		frameStarted = true;
		renderingStarted = false;
		renderingResume = true;
		boundPipeline = null;
		boundDescriptorState = null;
		boundComputePipeline = null;
		boundComputeDescriptorState = null;
		boundDynamicState = false;
		currentVertexLayout = null;
		currentVertexBuffers.resize(0);
		currentTargetSet = savedTarget;
		if (!query.resultValid)
			throw "Vulkan query did not resolve after its synchronous submission completed";
	}

	function waitForQuerySubmission(generation:VulkanQueryGeneration) {
		final frame = frames[generation.frameIndex];
		if (ctx.waitForFence(frame.fence, -1) != 0)
			throw Runtime.error("Failed to wait for Vulkan query submission");
		completedSubmissionSerial = hxd.Math.imax(completedSubmissionSerial, generation.submissionSerial);
		queryManager.completeFrame(generation.frameIndex);
	}

	@:noCompletion public function getQueryDebugStats() {
		return queryManager.pageCounts();
	}

	@:noCompletion public function getBindlessDebugStats() {
		var descriptorWrites = 0;
		var descriptorUpdateCalls = 0;
		if( frames != null )
			for( frame in frames )
				if( frame.bindlessGeneration != null ) {
					descriptorWrites += frame.bindlessGeneration.descriptorWrites;
					descriptorUpdateCalls += frame.bindlessGeneration.descriptorUpdateCalls;
				}
		return {
			supported: bindlessDescriptors != null,
			capabilityMode: VulkanShaderAbi.CAPABILITY_MODE,
			features: capabilities == null ? "" : capabilities.diagnostics,
			imageCapacity: bindlessDescriptors == null ? 0 : bindlessDescriptors.imageCapacity,
			samplerCapacity: bindlessDescriptors == null ? 0 : bindlessDescriptors.samplerCapacity,
			bufferCapacity: bindlessDescriptors == null ? 0 : bindlessDescriptors.bufferCapacity,
			imageCount: bindlessDescriptors == null ? 0 : bindlessDescriptors.imageCount(),
			samplerCount: bindlessDescriptors == null ? 0 : bindlessDescriptors.samplerCount(),
			bufferCount: bindlessDescriptors == null ? 0 : bindlessDescriptors.bufferCount(),
			imageHighWater: bindlessDescriptors == null ? 0 : bindlessDescriptors.imageHighWater(),
			samplerHighWater: bindlessDescriptors == null ? 0 : bindlessDescriptors.samplerHighWater(),
			bufferHighWater: bindlessDescriptors == null ? 0 : bindlessDescriptors.bufferHighWater(),
			generations: bindlessDescriptors == null ? 0 : frameCount,
			descriptorWrites: descriptorWrites,
			descriptorUpdateCalls: descriptorUpdateCalls,
			slotRetirements: bindlessDescriptors == null ? 0 : bindlessDescriptors.slotRetirements,
			slotReuses: bindlessDescriptors == null ? 0 : bindlessDescriptors.slotReuses,
		};
	}

	public function getDrawDebugStats() {
		var descriptorPools = 0;
		var descriptorAllocations = 0;
		var descriptorCacheEntries = 0;
		var descriptorCachePeakEntries = 0;
		var descriptorCacheResets = 0;
		var descriptorCacheHits = 0;
		var descriptorCacheMisses = 0;
		var descriptorUpdates = 0;
		var descriptorPoolPages = 0;
		var descriptorPoolResets = 0;
		if( frames != null )
			for( frame in frames ) {
				descriptorPools += frame.descriptorArena.poolCreationCount;
				descriptorAllocations += frame.descriptorArena.allocationCount;
				descriptorCacheEntries += frame.descriptorCacheEntries;
				descriptorCachePeakEntries += frame.descriptorCachePeakEntries;
				descriptorCacheResets += frame.descriptorCacheResetCount;
				descriptorCacheHits += frame.descriptorCacheHitCount;
				descriptorCacheMisses += frame.descriptorCacheMissCount;
				descriptorUpdates += frame.descriptorUpdateCount;
				descriptorPoolPages += frame.descriptorArena.pageCount;
				descriptorPoolResets += frame.descriptorArena.poolResetCount;
			}
		return {
			graphicsPipelines: pipelineManager == null ? 0 : pipelineManager.createdCount,
			pipelineCacheHits: pipelineManager == null ? 0 : pipelineManager.hitCount,
			computePipelines: computePipelineManager == null ? 0 : computePipelineManager.createdCount,
			computePipelineCacheHits: computePipelineManager == null ? 0 : computePipelineManager.hitCount,
			pipelineLayouts: pipelineLayoutCache == null ? 0 : pipelineLayoutCache.createdCount,
			pipelineLayoutCacheHits: pipelineLayoutCache == null ? 0 : pipelineLayoutCache.hitCount,
			descriptorPools: descriptorPools,
			descriptorAllocations: descriptorAllocations,
			descriptorCacheEntries: descriptorCacheEntries,
			descriptorCachePeakEntries: descriptorCachePeakEntries,
			descriptorCacheResets: descriptorCacheResets,
			descriptorCacheHits: descriptorCacheHits,
			descriptorCacheMisses: descriptorCacheMisses,
			descriptorUpdates: descriptorUpdates,
			descriptorPoolPages: descriptorPoolPages,
			descriptorPoolResets: descriptorPoolResets,
			constantUploadPages: uploadManager == null ? 0 : uploadManager.pageCreationCount,
			readbackBuffers: readbackManager == null ? 0 : readbackManager.bufferCreationCount,
			uploadedBytes: uploadManager == null ? haxe.Int64.ofInt(0) : uploadManager.uploadedBytes,
			readbackBytes: readbackManager == null ? haxe.Int64.ofInt(0) : readbackManager.readbackBytes,
			barriers: VulkanResourceState.barrierCount,
			memoryReserved: allocator == null ? haxe.Int64.ofInt(0) : allocator.reservedBytes,
			memoryUsed: allocator == null ? haxe.Int64.ofInt(0) : allocator.usedBytes,
			pendingDestructions: deferredDestroy.pendingCount,
			samplerCreations: samplerCache == null ? 0 : samplerCache.creationCount,
			samplerCacheHits: samplerCache == null ? 0 : samplerCache.cacheHitCount,
		};
	}

	@:noCompletion public function requestDefaultTargetReadbackForTest(target:haxe.io.Bytes, callback:Void->Void):Bool {
		if( !swapchainTransferSource )
			return false;
		final required = viewportWidth * viewportHeight * 4;
		if( target.length < required )
			throw 'Vulkan test framebuffer readback requires $required bytes, got ${target.length}';
		captureRenderBuffer(new hxd.Pixels(viewportWidth, viewportHeight, target, VulkanTextureFormat.heapsFormat(outImageFormat)));
		if( callback != null )
			callback();
		return true;
	}

	@:noCompletion public function getDefaultTargetReadbackFormatForTest():VkFormat {
		return outImageFormat;
	}

	override function drawInstanced(ibuf:h3d.Buffer, commands:InstanceBuffer) {
		if( commands == null )
			throw "Vulkan instanced draw requires commands";
		if( commands.commandCount < 0 )
			throw "Vulkan instanced draw requires a non-negative command count";
		if( @:privateAccess commands.data == null ) {
			if( @:privateAccess commands.indexCount < 0 || @:privateAccess commands.startIndex < 0 )
				throw "Vulkan direct instancing requires non-negative indexCount and startIndex";
			prepareIndexedDraw(ibuf);
			command.drawIndexed(@:privateAccess commands.indexCount, commands.commandCount, @:privateAccess commands.startIndex, 0, 0);
			return;
		}

		final indirectBuffer:VulkanBuffer = cast @:privateAccess commands.data;
		if( indirectBuffer == null || indirectBuffer.disposed || !indirectBuffer.usage.has(INDIRECT_BUFFER) )
			throw "Vulkan indirect draw requires a buffer created with INDIRECT_BUFFER usage";
		final indirect:VulkanInstanceBuffer = cast indirectBuffer;
		final firstCommand = @:privateAccess commands.offset;
		final drawCount = commands.commandCount;
		if( firstCommand < 0 || firstCommand + drawCount > indirect.capacity )
			throw 'Vulkan indirect command range [$firstCommand, ${firstCommand + drawCount}) exceeds ${indirect.capacity} commands';
		if( limits.maxDrawIndirectCount >= 0 && drawCount > limits.maxDrawIndirectCount )
			throw 'Vulkan indirect draw count $drawCount exceeds device limit ${limits.maxDrawIndirectCount}';
		if( !capabilities.drawIndirectFirstInstance && indirect.hasNonZeroFirstInstance(firstCommand, drawCount) )
			throw "Vulkan indirect commands with non-zero firstInstance require drawIndirectFirstInstance";
		if( drawCount == 0 )
			return;
		final indirectOffset = firstCommand * VulkanInstanceBuffer.COMMAND_STRIDE;
		final indirectEnd = indirectOffset + drawCount * VulkanInstanceBuffer.COMMAND_STRIDE;
		if( indirectEnd > haxe.Int64.toInt(indirect.size) )
			throw 'Vulkan indirect byte range [$indirectOffset, $indirectEnd) exceeds ${indirect.size} bytes';

		final count:VulkanBuffer = cast @:privateAccess commands.countBuffer;
		if( count != null ) {
			if( !capabilities.drawIndirectCount )
				throw "Vulkan indirect-count drawing requires drawIndirectCount";
			if( count.disposed || !count.usage.has(INDIRECT_BUFFER) )
				throw "Vulkan indirect count requires a buffer created with INDIRECT_BUFFER usage";
			final countOffset = @:privateAccess commands.countOffset * 4;
			if( countOffset < 0 || countOffset + 4 > haxe.Int64.toInt(count.size) )
				throw 'Vulkan indirect count range [$countOffset, ${countOffset + 4}) exceeds ${count.size} bytes';
		}
		prepareIndexedDraw(ibuf, indirect, count);
		if( count != null ) {
			final countOffset = @:privateAccess commands.countOffset * 4;
			command.drawIndexedIndirectCount(indirect.buffer, (haxe.Int64.ofInt(indirectOffset) : hl.I64), count.buffer,
				(haxe.Int64.ofInt(countOffset) : hl.I64), drawCount, VulkanInstanceBuffer.COMMAND_STRIDE);
		} else if( drawCount == 1 || capabilities.multiDrawIndirect )
			command.drawIndexedIndirect(indirect.buffer, (haxe.Int64.ofInt(indirectOffset) : hl.I64), drawCount, VulkanInstanceBuffer.COMMAND_STRIDE);
		else
			for( index in 0...drawCount )
				command.drawIndexedIndirect(indirect.buffer,
					(haxe.Int64.ofInt(indirectOffset + index * VulkanInstanceBuffer.COMMAND_STRIDE) : hl.I64), 1, VulkanInstanceBuffer.COMMAND_STRIDE);
	}

}

#end
