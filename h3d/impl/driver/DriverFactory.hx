package h3d.impl.driver;

import hxd.GraphicsDriverApi;

final class DriverFactory {
	public static function requestFeature(f:Feature):Bool {
		#if macro
		return false;
		#elseif (js && dx12)
		return @:privateAccess h3d.impl.driver.dx12.js.JSDriver.onFeatureRequested(f);
		#else
		return switch (hxd.GraphicsDriverConfig.getCurrentOrDefault()) {
			#if (limen && gfx_dx12)
			case Dx12: @:privateAccess h3d.impl.driver.dx12.DX12Driver.onFeatureRequested(f);
			#end
			#if (limen && gfx_vulkan)
			case Vulkan: switch (f) { case BottomLeftCoords: false; default: true; };
			#end
			#if (js || usegl || (limen && (gfx_opengl || (!gfx_dx11 && !gfx_dx12 && !gfx_vulkan))))
			case OpenGL | Auto: @:privateAccess h3d.impl.driver.opengl.OpenGLDriver.onFeatureRequested(f);
			#end
			default: false;
		};
		#end
	}

	public static function create(api:GraphicsDriverApi, antiAlias:Int):Driver {
		#if macro
		return new h3d.impl.driver.nulls.NullDriver();
		#elseif (js && dx12)
		return h3d.impl.driver.dx12.js.JSDriver.inst ?? new h3d.impl.driver.dx12.js.JSDriver();
		#elseif limen
		return switch (api) {
			case Dx12:
				#if gfx_dx12
				new h3d.impl.driver.dx12.DX12Driver();
				#else
				throw "The selected D3D12 renderer was not compiled into Heaps";
				#end
			case Dx11:
				#if gfx_dx11
				new h3d.impl.driver.dx11.DX11Driver();
				#else
				throw "The selected D3D11 renderer was not compiled into Heaps";
				#end
			case Vulkan:
				#if gfx_vulkan
				new h3d.impl.driver.vulkan.VulkanDriver();
				#else
				throw "The selected Vulkan renderer was not compiled into Heaps";
				#end
			case OpenGL | Auto:
				#if (gfx_opengl || (!gfx_dx11 && !gfx_dx12 && !gfx_vulkan))
				new h3d.impl.driver.opengl.OpenGLDriver(antiAlias);
				#else
				throw "The selected OpenGL renderer was not compiled into Heaps";
				#end
		}
		#elseif (js || usegl)
		#if js
		return js.Browser.supported ? new h3d.impl.driver.opengl.OpenGLDriver(antiAlias) : new h3d.impl.driver.nulls.NullDriver();
		#else
		return new h3d.impl.driver.opengl.OpenGLDriver(antiAlias);
		#end
		#elseif usesys
		return new haxe.GraphicsDriver(antiAlias);
		#else
		#if sys Sys.println #else trace #end ("No output driver available." #if hl + " Compile with -lib limen" #end);
		return new h3d.impl.driver.nulls.NullDriver();
		#end
	}
}
