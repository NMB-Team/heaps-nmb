package h3d.impl.driver;

#if macro
typedef GPUBuffer = {};
#elseif js
typedef GPUBuffer = js.html.webgl.Buffer;
#elseif (limen && ((gfx_dx11 && (gfx_dx12 || gfx_vulkan || gfx_opengl)) || (gfx_dx12 && (gfx_vulkan || gfx_opengl)) || (gfx_vulkan && gfx_opengl)))
typedef GPUBuffer = Dynamic;
#elseif (limen && gfx_vulkan)
typedef GPUBuffer = h3d.impl.driver.vulkan.resource.VulkanBuffer;
#elseif (limen && gfx_dx12)
typedef GPUBuffer = h3d.impl.driver.dx12.resource.BufferData;
#elseif (limen && gfx_dx11)
typedef GPUBuffer = limen.graphics.renderer.d3d11.resource.Resources.Resource;
#elseif limen
typedef GPUBuffer = limen.graphics.renderer.opengl.resource.Buffers.Buffer;
#elseif usegl
typedef GPUBuffer = haxe.GLTypes.Buffer;
#elseif usesys
typedef GPUBuffer = haxe.GraphicsDriver.GPUBuffer;
#else
typedef GPUBuffer = {};
#end
