package h3d.impl.driver.vulkan.attachment;

#if (limen && gfx_vulkan)
import h3d.Engine.DepthBinding;
import h3d.impl.driver.vulkan.resource.VulkanImage.VulkanTexture;
import limen.graphics.vulkan.format.Formats.VkFormat;
import limen.graphics.vulkan.memory.Memory.VkImage;
import limen.graphics.vulkan.memory.Memory.VkImageAspectFlag;
import limen.graphics.vulkan.memory.Memory.VkImageView;

enum abstract VulkanAttachmentLoad(Int) {
	var Preserve;
	var Clear;
	var Discard;
}

class VulkanRenderingAttachment {
	public final texture:h3d.mat.Texture;
	public final resource:VulkanTexture;
	public final image:VkImage;
	public final view:VkImageView;
	public final format:VkFormat;
	public final aspect:haxe.EnumFlags<VkImageAspectFlag>;
	public final mipLevel:Int;
	public final layer:Int;
	public var load:VulkanAttachmentLoad;
	public var store:Bool;

	public function new(texture:h3d.mat.Texture, resource:VulkanTexture, image:VkImage, view:VkImageView, format:VkFormat,
		aspect:haxe.EnumFlags<VkImageAspectFlag>, mipLevel:Int, layer:Int, load = Preserve, store = true) {
		this.texture = texture;
		this.resource = resource;
		this.image = image;
		this.view = view;
		this.format = format;
		this.aspect = aspect;
		this.mipLevel = mipLevel;
		this.layer = layer;
		this.load = load;
		this.store = store;
	}

	public inline function overlaps(other:VulkanTexture, baseMip:Int, levelCount:Int, baseLayer:Int, layerCount:Int):Bool {
		return resource == other && mipLevel >= baseMip && mipLevel < baseMip + levelCount
			&& layer >= baseLayer && layer < baseLayer + layerCount;
	}
}

class VulkanRenderingTargetSet {
	public final colors:Array<VulkanRenderingAttachment>;
	public final depth:VulkanRenderingAttachment;
	public final stencil:VulkanRenderingAttachment;
	public final width:Int;
	public final height:Int;
	public final samples:Int;
	public final depthBinding:DepthBinding;
	public final isDefault:Bool;
	public final key:String;

	public function new(colors:Array<VulkanRenderingAttachment>, depth:VulkanRenderingAttachment, stencil:VulkanRenderingAttachment,
		width:Int, height:Int, samples:Int, depthBinding:DepthBinding, isDefault:Bool, key:String) {
		this.colors = colors;
		this.depth = depth;
		this.stencil = stencil;
		this.width = width;
		this.height = height;
		this.samples = samples;
		this.depthBinding = depthBinding;
		this.isDefault = isDefault;
		this.key = key;
	}

	public inline function hasDepth():Bool {
		return depth != null;
	}

	public inline function hasStencil():Bool {
		return stencil != null;
	}
}
#end
