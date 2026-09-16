package h3d.impl.driver.vulkan.texture;

#if (limen && gfx_vulkan)
import h3d.mat.Data.TextureFlags;
import hxd.PixelFormat;
import limen.graphics.vulkan.format.Formats.VkFormat;
import limen.graphics.vulkan.format.Formats.VkFormatFeature;
import limen.graphics.vulkan.format.Formats.VkFormatProperties;
import limen.graphics.vulkan.memory.Memory.VkImageUsageFlag;

class VulkanTextureFormatInfo {
	public final heapsFormat:PixelFormat;
	public final format:VkFormat;
	public final bytesPerBlock:Int;
	public final blockWidth:Int;
	public final blockHeight:Int;
	public final uploadCompatible:Bool;
	public final sampledCompatible:Bool;
	public final filteringAllowed:Bool;
	public final depth:Bool;

	public function new(heapsFormat:PixelFormat, format:VkFormat, bytesPerBlock:Int, blockWidth = 1, blockHeight = 1,
		uploadCompatible = true, sampledCompatible = true, filteringAllowed = true, depth = false) {
		this.heapsFormat = heapsFormat;
		this.format = format;
		this.bytesPerBlock = bytesPerBlock;
		this.blockWidth = blockWidth;
		this.blockHeight = blockHeight;
		this.uploadCompatible = uploadCompatible;
		this.sampledCompatible = sampledCompatible;
		this.filteringAllowed = filteringAllowed;
		this.depth = depth;
	}

	public inline function uploadSize(width:Int, height:Int):Int {
		return Std.int((width + blockWidth - 1) / blockWidth) * Std.int((height + blockHeight - 1) / blockHeight) * bytesPerBlock;
	}

	public function validateRegion(x:Int, y:Int, width:Int, height:Int, mipWidth:Int, mipHeight:Int) {
		if (x < 0 || y < 0 || width <= 0 || height <= 0 || x + width > mipWidth || y + height > mipHeight)
			throw 'Texture upload region ($x,$y ${width}x$height) exceeds mip extent ${mipWidth}x$mipHeight';
		if ((x % blockWidth) != 0 || (y % blockHeight) != 0)
			throw 'Compressed texture upload offset ($x,$y) must align to ${blockWidth}x$blockHeight blocks';
		if ((width % blockWidth) != 0 && x + width != mipWidth)
			throw 'Compressed texture upload width $width must be block-aligned except at the mip edge';
		if ((height % blockHeight) != 0 && y + height != mipHeight)
			throw 'Compressed texture upload height $height must be block-aligned except at the mip edge';
	}

	public function validateReadbackRegion(x:Int, y:Int, width:Int, height:Int, mipWidth:Int, mipHeight:Int) {
		if (x < 0 || y < 0 || width <= 0 || height <= 0 || x + width > mipWidth || y + height > mipHeight)
			throw 'Texture capture region ($x,$y ${width}x$height) exceeds mip extent ${mipWidth}x$mipHeight';
		if ((x % blockWidth) != 0 || (y % blockHeight) != 0)
			throw 'Compressed texture capture offset ($x,$y) must align to ${blockWidth}x$blockHeight blocks';
		if ((width % blockWidth) != 0 && x + width != mipWidth)
			throw 'Compressed texture capture width $width must be block-aligned except at the mip edge';
		if ((height % blockHeight) != 0 && y + height != mipHeight)
			throw 'Compressed texture capture height $height must be block-aligned except at the mip edge';
	}

	public inline function supportsLinearFiltering(properties:VkFormatProperties):Bool {
		return filteringAllowed && (properties.optimalTilingFeatures & cast VkFormatFeature.SAMPLED_IMAGE_FILTER_LINEAR) != 0;
	}

	public function capabilities(properties:VkFormatProperties):VulkanTextureFormatCapabilities {
		return new VulkanTextureFormatCapabilities(this, properties);
	}
}

class VulkanTextureFormatCapabilities {
	public final transferSource:Bool;
	public final transferDestination:Bool;
	public final blitSource:Bool;
	public final blitDestination:Bool;
	public final linearFilterBlit:Bool;
	public final sampledImage:Bool;
	public final colorAttachment:Bool;
	public final depthStencil:Bool;
	public final compressed:Bool;

	public function new(format:VulkanTextureFormatInfo, properties:VkFormatProperties) {
		final features = properties.optimalTilingFeatures;
		transferSource = has(features, VkFormatFeature.TRANSFER_SRC);
		transferDestination = has(features, VkFormatFeature.TRANSFER_DST);
		blitSource = has(features, VkFormatFeature.BLIT_SRC);
		blitDestination = has(features, VkFormatFeature.BLIT_DST);
		linearFilterBlit = format.filteringAllowed && has(features, VkFormatFeature.SAMPLED_IMAGE_FILTER_LINEAR);
		sampledImage = has(features, VkFormatFeature.SAMPLED_IMAGE);
		colorAttachment = has(features, VkFormatFeature.COLOR_ATTACHMENT);
		depthStencil = format.depth;
		compressed = format.blockWidth != 1 || format.blockHeight != 1;
	}

	public inline function supportsLinearMipmapBlit():Bool {
		return !depthStencil && blitSource && blitDestination && linearFilterBlit && transferSource && transferDestination;
	}

	public inline function supportsGraphicsMipmapFallback():Bool {
		return !depthStencil && !compressed && sampledImage && colorAttachment && linearFilterBlit;
	}

	static inline function has(features:Int, feature:VkFormatFeature):Bool {
		return (features & cast feature) != 0;
	}
}

class VulkanTextureFormat {
	public static function resolve(format:PixelFormat):VulkanTextureFormatInfo {
		return switch (format) {
		case ARGB, BGRA: info(format, B8G8R8A8_UNORM, 4);
		case RGBA: info(format, R8G8B8A8_UNORM, 4);
		case RGBA16F: info(format, R16G16B16A16_SFLOAT, 8);
		case RGBA32F: info(format, R32G32B32A32_SFLOAT, 16);
		case R8: info(format, R8_UNORM, 1);
		case R16F: info(format, R16_SFLOAT, 2);
		case R32F: info(format, R32_SFLOAT, 4);
		case RG8: info(format, R8G8_UNORM, 2);
		case RG16F: info(format, R16G16_SFLOAT, 4);
		case RG32F: info(format, R32G32_SFLOAT, 8);
		case RGB8: info(format, R8G8B8_UNORM, 3);
		case RGB16F: info(format, R16G16B16_SFLOAT, 6);
		case RGB32F: info(format, R32G32B32_SFLOAT, 12);
		case SRGB: info(format, R8G8B8A8_SRGB, 4);
		case SRGB_ALPHA: info(format, R8G8B8A8_SRGB, 4);
		case RGB10A2: info(format, A2B10G10R10_UNORM_PACK32, 4);
		case RG11B10UF: info(format, B10G11R11_UFLOAT_PACK32, 4);
		case R16U: info(format, R16_UNORM, 2);
		case RG16U: info(format, R16G16_UNORM, 4);
		case RGB16U: info(format, R16G16B16_UNORM, 6);
		case RGBA16U: info(format, R16G16B16A16_UNORM, 8);
		case S3TC(1): info(format, BC1_RGBA_UNORM_BLOCK, 8, 4, 4);
		case S3TC(2): info(format, BC2_UNORM_BLOCK, 16, 4, 4);
		case S3TC(3): info(format, BC3_UNORM_BLOCK, 16, 4, 4);
		case S3TC(4): info(format, BC4_UNORM_BLOCK, 8, 4, 4);
		case S3TC(5): info(format, BC5_UNORM_BLOCK, 16, 4, 4);
		case S3TC(6): info(format, BC6H_UFLOAT_BLOCK, 16, 4, 4);
		case S3TC(7): info(format, BC7_UNORM_BLOCK, 16, 4, 4);
		case S3TC(_): throw 'Unsupported compressed texture format $format';
		case Depth16: info(format, D16_UNORM, 2, 1, 1, false, true);
		case Depth24: info(format, X8_D24_UNORM_PACK32, 4, 1, 1, false, true);
		case Depth24Stencil8: info(format, D24_UNORM_S8_UINT, 4, 1, 1, false, true);
		case Depth32: info(format, D32_SFLOAT, 4, 1, 1, false, true);
		case Depth32Stencil8: info(format, D32_SFLOAT_S8_UINT, 8, 1, 1, false, true);
		};
	}

	public static function heapsFormat(format:VkFormat):PixelFormat {
		return switch (format) {
		case B8G8R8A8_UNORM, B8G8R8A8_SRGB: BGRA;
		case R8G8B8A8_UNORM: RGBA;
		case R8G8B8A8_SRGB: SRGB_ALPHA;
		default: throw 'Unsupported Vulkan readback format $format';
		}
	}

	public static function usage(flags:haxe.EnumFlags<TextureFlags>, depth:Bool, graphicsMipmapFallback = false):haxe.EnumFlags<VkImageUsageFlag> {
		var usage = new haxe.EnumFlags<VkImageUsageFlag>();
		usage.set(SAMPLED);
		usage.set(TRANSFER_SRC);
		usage.set(TRANSFER_DST);
		if (flags.has(Target) || graphicsMipmapFallback)
			usage.set(depth ? DEPTH_STENCIL_ATTACHMENT : COLOR_ATTACHMENT);
		if (flags.has(Writable))
			usage.set(STORAGE);
		return usage;
	}

	public static function requiredFeatures(flags:haxe.EnumFlags<TextureFlags>, depth:Bool, graphicsMipmapFallback = false):Int {
		var required:Int = cast VkFormatFeature.SAMPLED_IMAGE;
		required |= cast VkFormatFeature.TRANSFER_SRC;
		required |= cast VkFormatFeature.TRANSFER_DST;
		if (flags.has(Target) || graphicsMipmapFallback)
			required |= cast (depth ? VkFormatFeature.DEPTH_STENCIL_ATTACHMENT : VkFormatFeature.COLOR_ATTACHMENT);
		if (flags.has(Writable))
			required |= cast VkFormatFeature.STORAGE_IMAGE;
		return required;
	}

	static inline function info(format:PixelFormat, vk:VkFormat, bytes:Int, blockWidth = 1, blockHeight = 1, filteringAllowed = true, depth = false):VulkanTextureFormatInfo {
		return new VulkanTextureFormatInfo(format, vk, bytes, blockWidth, blockHeight, true, true, filteringAllowed, depth);
	}
}
#end
