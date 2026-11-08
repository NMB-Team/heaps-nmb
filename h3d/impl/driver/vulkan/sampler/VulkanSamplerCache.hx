package h3d.impl.driver.vulkan.sampler;

#if (limen && gfx_vulkan)
import h3d.mat.Texture;
import h3d.mat.Data.Filter;
import h3d.mat.Data.MipMap;
import h3d.mat.Data.Wrap;
import limen.graphics.renderer.vulkan.Vulkan as VulkanRuntime;
import limen.graphics.renderer.vulkan.device.DeviceLimits.VkPhysicalDeviceLimits;
import limen.graphics.renderer.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.renderer.vulkan.pipeline.Pipeline.VkCompareOp;
import limen.graphics.renderer.vulkan.pipeline.Pipeline.VkFilter;
import limen.graphics.renderer.vulkan.sampler.Samplers.VkBorderColor;
import limen.graphics.renderer.vulkan.sampler.Samplers.VkSampler;
import limen.graphics.renderer.vulkan.sampler.Samplers.VkSamplerAddressMode;
import limen.graphics.renderer.vulkan.sampler.Samplers.VkSamplerCreateInfo;
import limen.graphics.renderer.vulkan.sampler.Samplers.VkSamplerMipmapMode;

class VulkanSamplerHandle {
	public final sampler:VkSampler;
	public final key:String;

	public function new(sampler:VkSampler, key:String) {
		this.sampler = sampler;
		this.key = key;
	}
}

class VulkanSamplerCache {
	final context:VkContext;
	final limits:VkPhysicalDeviceLimits;
	final anisotropySupported:Bool;
	final samplers:Map<Int, VulkanSamplerHandle> = new Map();
	public var creationCount(default, null) = 0;
	public var cacheHitCount(default, null) = 0;

	public function new(context:VkContext, limits:VkPhysicalDeviceLimits, anisotropySupported:Bool) {
		this.context = context;
		this.limits = limits;
		this.anisotropySupported = anisotropySupported;
	}

	public function get(texture:Texture, formatFilterable:Bool):VulkanSamplerHandle {
		final anisotropic = texture.filter == Filter.AnisotropicNearest || texture.filter == Filter.AnisotropicLinear;
		final linear = texture.filter == Filter.Linear || texture.filter == Filter.AnisotropicLinear || (anisotropic && anisotropySupported);
		if (linear && !formatFilterable)
			throw 'Texture format ${texture.format} does not support the requested filtered sampling';
		final lodBias = texture.lodBias;
		if (Math.abs(lodBias) > limits.maxSamplerLodBias)
			throw 'Texture LOD bias $lodBias exceeds Vulkan limit ${limits.maxSamplerLodBias}';

		final anisotropyEnable = anisotropic && anisotropySupported;
		final anisotropyLevel = anisotropyEnable ? hxd.Math.imin(texture.anisotropicMaxLevel, Math.ceil(limits.maxSamplerAnisotropy)) : 0;
		final mipLinear = texture.mipMap == MipMap.Linear;
		final noMips = texture.mipMap == MipMap.None;
		final wrap = Type.enumIndex(texture.wrap);
		final bias = @:privateAccess texture.packedLodBias;
		// Pack only effective sampler state, excluding texture views and image identity.
		final state = (linear ? 1 : 0) | (mipLinear ? 2 : 0) | (noMips ? 4 : 0) | (wrap << 3)
			| (anisotropyEnable ? 32 : 0) | (anisotropyLevel << 6) | (bias << 11);
		final cached = samplers.get(state);
		if (cached != null) {
			cacheHitCount++;
			return cached;
		}

		final filter:VkFilter = linear ? VkFilter.LINEAR : VkFilter.NEAREST;
		final mipmapMode:VkSamplerMipmapMode = mipLinear ? VkSamplerMipmapMode.LINEAR : VkSamplerMipmapMode.NEAREST;
		final address:VkSamplerAddressMode = switch (texture.wrap) {
		case Wrap.Clamp: VkSamplerAddressMode.CLAMP_TO_EDGE;
		case Wrap.Repeat: VkSamplerAddressMode.REPEAT;
		case Wrap.Mirror: VkSamplerAddressMode.MIRRORED_REPEAT;
		};
		final maxAnisotropy = anisotropyEnable ? Math.min(texture.anisotropicMaxLevel, limits.maxSamplerAnisotropy) : 1.0;
		final maxLod = noMips ? 0.0 : 1000.0;
		final compare = VkCompareOp.NEVER;
		final border = VkBorderColor.FLOAT_TRANSPARENT_BLACK;
		final key = '${cast(filter, Int)}:${cast(filter, Int)}:${cast(mipmapMode, Int)}:${cast(address, Int)}:${cast(address, Int)}:${cast(address, Int)}:'
			+ '${anisotropyEnable ? 1 : 0}:$maxAnisotropy:0:${cast(compare, Int)}:${cast(border, Int)}:$lodBias:0:$maxLod';

		final info = new VkSamplerCreateInfo();
		info.magFilter = filter;
		info.minFilter = filter;
		info.mipmapMode = mipmapMode;
		info.addressModeU = address;
		info.addressModeV = address;
		info.addressModeW = address;
		info.mipLodBias = lodBias;
		info.anisotropyEnable = anisotropyEnable;
		info.maxAnisotropy = maxAnisotropy;
		info.compareEnable = false;
		info.compareOp = compare;
		info.minLod = 0;
		info.maxLod = maxLod;
		info.borderColor = border;
		info.unnormalizedCoordinates = false;
		final sampler = context.createSampler(info);
		if (sampler == null)
			throw VulkanRuntime.error('Failed to create Vulkan sampler for state $key');
		final handle = new VulkanSamplerHandle(sampler, key);
		samplers.set(state, handle);
		creationCount++;
		return handle;
	}

	public function dispose() {
		for (sampler in samplers)
			context.destroySampler(sampler.sampler);
		samplers.clear();
	}
}
#end
