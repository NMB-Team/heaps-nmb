package h3d.impl.driver;

import hxd.GraphicsDriverApi;

final class DriverFactory {
	public static function create(api:GraphicsDriverApi, antiAlias:Int):Driver {
		#if macro
		return new h3d.impl.driver.nulls.NullDriver();
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
