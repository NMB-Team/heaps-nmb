package h3d.impl.driver.vulkan.resource;

#if (limen && gfx_vulkan)
import haxe.Int64;
import limen.graphics.vulkan.format.Formats.VkFormat;
import limen.graphics.vulkan.memory.Memory.VkImage;
import limen.graphics.vulkan.memory.Memory.VkImageAspectFlag;
import limen.graphics.vulkan.memory.Memory.VkImageUsageFlag;
import limen.graphics.vulkan.memory.Memory.VkImageView;
import limen.graphics.vulkan.memory.Memory.VkImageViewType;

enum abstract VulkanImageState(Int) {
	var Undefined;
	var TransferSource;
	var TransferDestination;
	var ShaderRead;
	var ComputeShaderRead;
	var ShaderStorageRead;
	var ShaderStorageWrite;
	var ShaderStorageReadWrite;
	var ColorAttachment;
	var DepthStencilAttachment;
	var DepthStencilReadOnly;
	var General;
	var Present;
}

enum abstract VulkanMipmapMode(Int) {
	var None;
	var LinearBlit;
	var Graphics;
}

class VulkanImage {
	public var image(default, null):VkImage;
	public var allocation(default, null):VulkanAllocation;
	public var size(default, null):Int64;
	public var format(default, null):VkFormat;
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var depth(default, null):Int;
	public var mipCount(default, null):Int;
	public var layerCount(default, null):Int;
	public var aspect(default, null):haxe.EnumFlags<VkImageAspectFlag>;
	public var usage(default, null):haxe.EnumFlags<VkImageUsageFlag>;
	final colorStates:Array<VulkanImageState>;
	final depthStates:Array<VulkanImageState>;
	final stencilStates:Array<VulkanImageState>;
	public var debugId(default, null):Int;
	public var debugName(default, null):String;
	public var lastSubmission = 0;
	public var disposed(default, null) = false;

	public function new(image:VkImage, allocation:VulkanAllocation, size:Int64, format:VkFormat, width:Int, height:Int, depth:Int, mipCount:Int, layerCount:Int,
		aspect:haxe.EnumFlags<VkImageAspectFlag>, usage:haxe.EnumFlags<VkImageUsageFlag>, debugId:Int, debugName:String) {
		this.image = image;
		this.allocation = allocation;
		this.size = size;
		this.format = format;
		this.width = width;
		this.height = height;
		this.depth = depth;
		this.mipCount = mipCount;
		this.layerCount = layerCount;
		this.aspect = aspect;
		this.usage = usage;
		this.debugId = debugId;
		this.debugName = debugName;
		final subresourceCount = mipCount * layerCount;
		colorStates = [for (_ in 0...subresourceCount) VulkanImageState.Undefined];
		depthStates = [for (_ in 0...subresourceCount) VulkanImageState.Undefined];
		stencilStates = [for (_ in 0...subresourceCount) VulkanImageState.Undefined];
	}

	public inline function getState(mipLevel:Int, layer:Int, ?aspect:VkImageAspectFlag):VulkanImageState {
		final index = layer * mipCount + mipLevel;
		return switch (aspect) {
		case STENCIL: stencilStates[index];
		case DEPTH: depthStates[index];
		case COLOR: colorStates[index];
		case null: this.aspect.has(COLOR) ? colorStates[index] : depthStates[index];
		default: throw 'Unsupported Vulkan image aspect $aspect';
		}
	}

	public inline function setState(mipLevel:Int, layer:Int, aspect:VkImageAspectFlag, state:VulkanImageState) {
		final index = layer * mipCount + mipLevel;
		switch (aspect) {
		case COLOR: colorStates[index] = state;
		case DEPTH: depthStates[index] = state;
		case STENCIL: stencilStates[index] = state;
		default: throw 'Unsupported Vulkan image aspect $aspect';
		}
	}

	@:allow(h3d.impl.driver.vulkan.VulkanDriver)
	function markDisposed() {
		disposed = true;
	}
}

class VulkanImageViewEntry {
	public final type:VkImageViewType;
	public final format:VkFormat;
	public final aspect:Int;
	public final baseMip:Int;
	public final levelCount:Int;
	public final baseLayer:Int;
	public final layerCount:Int;
	public final view:VkImageView;
	public final key:String;

	public function new(type:VkImageViewType, format:VkFormat, aspect:Int, baseMip:Int, levelCount:Int, baseLayer:Int, layerCount:Int, view:VkImageView, key:String) {
		this.type = type;
		this.format = format;
		this.aspect = aspect;
		this.baseMip = baseMip;
		this.levelCount = levelCount;
		this.baseLayer = baseLayer;
		this.layerCount = layerCount;
		this.view = view;
		this.key = key;
	}
}

class VulkanTexture extends VulkanImage {
	public var view(default, null):VkImageView;
	public var filterable(default, null):Bool;
	public var mipmapMode(default, null):VulkanMipmapMode;
	final extraViews:Array<VulkanImageViewEntry> = [];
	public final defaultViewEntry:VulkanImageViewEntry;
	final baseUploads:Array<Bool>;
	final explicitMipUploads:Array<Bool>;

	public function new(image:VkImage, view:VkImageView, allocation:VulkanAllocation, size:Int64, format:VkFormat, width:Int, height:Int, depth:Int, mipCount:Int, layerCount:Int,
		aspect:haxe.EnumFlags<VkImageAspectFlag>, usage:haxe.EnumFlags<VkImageUsageFlag>, filterable:Bool, mipmapMode:VulkanMipmapMode, debugId:Int, debugName:String) {
		super(image, allocation, size, format, width, height, depth, mipCount, layerCount, aspect, usage, debugId, debugName);
		this.view = view;
		defaultViewEntry = new VulkanImageViewEntry(VkImageViewType.TYPE_2D, format, 0, 0, mipCount, 0, layerCount, view, "default");
		this.filterable = filterable;
		this.mipmapMode = mipmapMode;
		baseUploads = [for (_ in 0...layerCount) false];
		explicitMipUploads = [for (_ in 0...layerCount) false];
	}

	public inline function markUpload(mipLevel:Int, layer:Int, completeBase:Bool) {
		if (mipLevel == 0)
			baseUploads[layer] = baseUploads[layer] || completeBase;
		else
			explicitMipUploads[layer] = true;
	}

	public function hasCompleteBaseUploads():Bool {
		for (uploaded in baseUploads)
			if (!uploaded)
				return false;
		return true;
	}

	public function hasExplicitMipUploads():Bool {
		for (uploaded in explicitMipUploads)
			if (uploaded)
				return true;
		return false;
	}

	@:allow(h3d.impl.driver.vulkan.VulkanDriver)
	function getExtraView(type:VkImageViewType, format:VkFormat, aspect:Int, baseMip:Int, levelCount:Int, baseLayer:Int, layerCount:Int):VulkanImageViewEntry {
		for (entry in extraViews)
			if (entry.type == type && entry.format == format && entry.aspect == aspect && entry.baseMip == baseMip
				&& entry.levelCount == levelCount && entry.baseLayer == baseLayer && entry.layerCount == layerCount)
				return entry;
		return null;
	}

	@:allow(h3d.impl.driver.vulkan.VulkanDriver)
	function setExtraView(entry:VulkanImageViewEntry) {
		extraViews.push(entry);
	}

	@:allow(h3d.impl.driver.vulkan.VulkanDriver)
	function destroyViews(destroy:VkImageView->Void) {
		destroy(view);
		for (extra in extraViews)
			destroy(extra.view);
		extraViews.resize(0);
	}
}
#end
