package hxd;

#if limen
import limen.graphics.GraphicsDriver as LimenGraphicsDriver;
#end

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
		#elseif gfx_dx12
		return Dx12;
		#elseif gfx_dx11
		return Dx11;
		#elseif gfx_vulkan
		return Vulkan;
		#else
		return OpenGL;
		#end
	}

	#if limen
	@:noCompletion
	public static function getLimenPreferred():LimenGraphicsDriver {
		return switch (getCurrentOrDefault()) {
			case OpenGL | Auto: OpenGL;
			case Vulkan: Vulkan;
			case Dx11: D3D11;
			case Dx12: D3D12;
		};
	}

	@:noCompletion
	public static function getLimenSupported():Array<LimenGraphicsDriver> {
		final supported = [];
		#if (gfx_opengl || (!gfx_dx11 && !gfx_dx12 && !gfx_vulkan))
		supported.push(OpenGL);
		#end
		#if gfx_vulkan
		supported.push(Vulkan);
		#end
		#if gfx_dx11
		supported.push(D3D11);
		#end
		#if gfx_dx12
		supported.push(D3D12);
		#end
		return supported;
	}

	@:noCompletion
	public static function setFromLimen(driver:LimenGraphicsDriver):Void {
		current = switch (driver) {
			case OpenGL: OpenGL;
			case Vulkan: Vulkan;
			case D3D11: Dx11;
			case D3D12: Dx12;
			case None: Auto;
		};
	}
	#end
}
