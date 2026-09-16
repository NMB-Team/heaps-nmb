package h3d.impl.driver.vulkan.sampler;

#if (limen && gfx_vulkan)
import h3d.mat.Texture;
import h3d.mat.Data.Filter;
import h3d.mat.Data.MipMap;
import h3d.mat.Data.Wrap;
import limen.graphics.vulkan.Runtime;
import limen.graphics.vulkan.device.DeviceLimits.VkPhysicalDeviceLimits;
import limen.graphics.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.vulkan.pipeline.Pipeline.VkCompareOp;
import limen.graphics.vulkan.pipeline.Pipeline.VkFilter;
import limen.graphics.vulkan.sampler.Samplers.VkBorderColor;
import limen.graphics.vulkan.sampler.Samplers.VkSampler;
import limen.graphics.vulkan.sampler.Samplers.VkSamplerAddressMode;
import limen.graphics.vulkan.sampler.Samplers.VkSamplerCreateInfo;
import limen.graphics.vulkan.sampler.Samplers.VkSamplerMipmapMode;

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
	final samplers:Map<String, VkSampler> = new Map();
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
		if (Math.abs(texture.lodBias) > limits.maxSamplerLodBias)
			throw 'Texture LOD bias ${texture.lodBias} exceeds Vulkan limit ${limits.maxSamplerLodBias}';

		final anisotropyEnable = anisotropic && anisotropySupported;
		final filter:VkFilter = linear ? VkFilter.LINEAR : VkFilter.NEAREST;
		final mipmapMode:VkSamplerMipmapMode = texture.mipMap == MipMap.Linear ? VkSamplerMipmapMode.LINEAR : VkSamplerMipmapMode.NEAREST;
		final address:VkSamplerAddressMode = switch (texture.wrap) {
		case Wrap.Clamp: VkSamplerAddressMode.CLAMP_TO_EDGE;
		case Wrap.Repeat: VkSamplerAddressMode.REPEAT;
		case Wrap.Mirror: VkSamplerAddressMode.MIRRORED_REPEAT;
		};
		final maxAnisotropy = anisotropyEnable ? Math.min(texture.anisotropicMaxLevel, limits.maxSamplerAnisotropy) : 1.0;
		final maxLod = texture.mipMap == MipMap.None ? 0.0 : 1000.0;
		final compare = VkCompareOp.NEVER;
		final border = VkBorderColor.FLOAT_TRANSPARENT_BLACK;
		final key = '${cast(filter, Int)}:${cast(filter, Int)}:${cast(mipmapMode, Int)}:${cast(address, Int)}:${cast(address, Int)}:${cast(address, Int)}:'
			+ '${anisotropyEnable ? 1 : 0}:$maxAnisotropy:0:${cast(compare, Int)}:${cast(border, Int)}:${texture.lodBias}:0:$maxLod';
		var sampler = samplers.get(key);
		if (sampler != null) {
			cacheHitCount++;
			return new VulkanSamplerHandle(sampler, key);
		}

		final info = new VkSamplerCreateInfo();
		info.magFilter = filter;
		info.minFilter = filter;
		info.mipmapMode = mipmapMode;
		info.addressModeU = address;
		info.addressModeV = address;
		info.addressModeW = address;
		info.mipLodBias = texture.lodBias;
		info.anisotropyEnable = anisotropyEnable;
		info.maxAnisotropy = maxAnisotropy;
		info.compareEnable = false;
		info.compareOp = compare;
		info.minLod = 0;
		info.maxLod = maxLod;
		info.borderColor = border;
		info.unnormalizedCoordinates = false;
		sampler = context.createSampler(info);
		if (sampler == null)
			throw Runtime.error('Failed to create Vulkan sampler for state $key');
		samplers.set(key, sampler);
		creationCount++;
		return new VulkanSamplerHandle(sampler, key);
	}

	public function dispose() {
		for (sampler in samplers)
			context.destroySampler(sampler);
		samplers.clear();
	}
}
#end
