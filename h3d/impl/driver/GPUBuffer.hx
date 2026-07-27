package h3d.impl.driver;

#if macro
typedef GPUBuffer = {};
#elseif js
typedef GPUBuffer = js.html.webgl.Buffer;
#elseif (limen && ((gfx_dx11 && (gfx_dx12 || gfx_vulkan || gfx_opengl)) || (gfx_dx12 && (gfx_vulkan || gfx_opengl)) || (gfx_vulkan && gfx_opengl)))
typedef GPUBuffer = Dynamic;
#elseif (limen && gfx_vulkan)
typedef GPUBuffer = { buf : limen.graphics.vulkan.memory.Memory.VkBuffer, mem : limen.graphics.vulkan.memory.Memory.VkDeviceMemory, stride : Int };
#elseif (limen && gfx_dx12)
typedef GPUBuffer = h3d.impl.driver.dx12.resource.BufferData;
#elseif (limen && gfx_dx11)
typedef GPUBuffer = limen.graphics.d3d11.DX11Core.Resource;
#elseif limen
typedef GPUBuffer = limen.graphics.opengl.OpenGLTypes.Buffer;
#elseif usegl
typedef GPUBuffer = haxe.GLTypes.Buffer;
#elseif usesys
typedef GPUBuffer = haxe.GraphicsDriver.GPUBuffer;
#else
typedef GPUBuffer = {};
#end
