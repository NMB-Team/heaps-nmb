package h3d.impl.driver;

#if macro
typedef GPUBuffer = {};
#elseif js
typedef GPUBuffer = js.html.webgl.Buffer;
#elseif (hlsdl && ((gfx_dx11 && (gfx_dx12 || gfx_vulkan || gfx_opengl)) || (gfx_dx12 && (gfx_vulkan || gfx_opengl)) || (gfx_vulkan && gfx_opengl)))
typedef GPUBuffer = Dynamic;
#elseif (hlsdl && gfx_vulkan)
typedef GPUBuffer = { buf : sdl.Vulkan.VkBuffer, mem : sdl.Vulkan.VkDeviceMemory, stride : Int };
#elseif (hlsdl && gfx_dx12)
typedef GPUBuffer = h3d.impl.driver.dx12.resource.BufferData;
#elseif (hlsdl && gfx_dx11)
typedef GPUBuffer = dx.Resource;
#elseif hlsdl
typedef GPUBuffer = sdl.GL.Buffer;
#elseif usegl
typedef GPUBuffer = haxe.GLTypes.Buffer;
#elseif (hldx && gfx_dx12)
typedef GPUBuffer = h3d.impl.driver.dx12.resource.BufferData;
#elseif hldx
typedef GPUBuffer = dx.Resource;
#elseif usesys
typedef GPUBuffer = haxe.GraphicsDriver.GPUBuffer;
#else
typedef GPUBuffer = {};
#end
