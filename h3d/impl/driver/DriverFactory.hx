package h3d.impl.driver;

import hxd.GraphicsDriverApi;

final class DriverFactory {

	public static function create(api:GraphicsDriverApi, antiAlias:Int):Driver {
		#if macro
		return new h3d.impl.driver.nulls.NullDriver();
		#elseif hlsdl
		return switch (api) {
			case Dx12:
				#if gfx_dx12
				new h3d.impl.driver.dx12.DX12Driver();
				#else
				createFallback(antiAlias);
				#end
			case Dx11:
				#if gfx_dx11
				new h3d.impl.driver.dx11.DX11Driver();
				#else
				createFallback(antiAlias);
				#end
			case Vulkan:
				#if gfx_vulkan
				new h3d.impl.driver.vulkan.VulkanDriver();
				#else
				createFallback(antiAlias);
				#end
			case OpenGL | Auto:
				#if (gfx_opengl || (!gfx_dx11 && !gfx_dx12 && !gfx_vulkan))
				new h3d.impl.driver.opengl.OpenGLDriver(antiAlias);
				#else
				createFallback(antiAlias);
				#end
		}
		#elseif (js || usegl)
		#if js
		return js.Browser.supported ? new h3d.impl.driver.opengl.OpenGLDriver(antiAlias) : new h3d.impl.driver.nulls.NullDriver();
		#else
		return new h3d.impl.driver.opengl.OpenGLDriver(antiAlias);
		#end
		#elseif (hldx && gfx_dx12)
		return new h3d.impl.driver.dx12.DX12Driver();
		#elseif hldx
		return new h3d.impl.driver.dx11.DX11Driver();
		#elseif usesys
		return new haxe.GraphicsDriver(antiAlias);
		#else
		#if sys Sys.println #else trace #end("No output driver available." #if hl + " Compile with -lib hlsdl or -lib hldx" #end);
		return new h3d.impl.driver.nulls.NullDriver();
		#end
	}

	private static function createFallback(antiAlias:Int):Driver {
		#if macro
		return new h3d.impl.driver.nulls.NullDriver();
		#elseif (hlsdl && gfx_dx11)
		return new h3d.impl.driver.dx11.DX11Driver();
		#elseif (hlsdl && gfx_dx12)
		return new h3d.impl.driver.dx12.DX12Driver();
		#elseif (hlsdl && gfx_vulkan)
		return new h3d.impl.driver.vulkan.VulkanDriver();
		#elseif (hlsdl && (gfx_opengl || (!gfx_dx11 && !gfx_dx12 && !gfx_vulkan)))
		return new h3d.impl.driver.opengl.OpenGLDriver(antiAlias);
		#else
		return new h3d.impl.driver.nulls.NullDriver();
		#end
	}
}
