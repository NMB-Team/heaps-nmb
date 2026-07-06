package hxd;

final class GraphicsDriverConfig {
	static var current:GraphicsDriverApi = Auto;

	public static function setCurrent(api:GraphicsDriverApi):Void {
		current = api;
	}

	public static function getCurrent():GraphicsDriverApi {
		return current;
	}

	public static function getCurrentOrDefault():GraphicsDriverApi {
		return current == Auto ? getDefault() : current;
	}

	public static function usesDirectX():Bool {
		return switch (getCurrentOrDefault()) {
			case Dx11 | Dx12: true;
			default: false;
		}
	}

	public static function usesVulkan():Bool {
		return getCurrentOrDefault() == Vulkan;
	}

	public static function getDefault():GraphicsDriverApi {
		#if default_gfx_dx12
		return Dx12;
		#elseif default_gfx_dx11
		return Dx11;
		#elseif default_gfx_vulkan
		return Vulkan;
		#elseif default_gfx_opengl
		return OpenGL;
		#elseif (gfx_dx12 || dx12)
		return Dx12;
		#elseif (gfx_dx11 || dx11)
		return Dx11;
		#elseif (gfx_vulkan || vulkan)
		return Vulkan;
		#else
		return OpenGL;
		#end
	}
}
