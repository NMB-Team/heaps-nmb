package h3d.impl.driver;

#if macro
typedef Texture = {};
#elseif js
typedef Texture = { t : js.html.webgl.Texture, width : Int, height : Int, internalFmt : Int, pixelFmt : Int, bits : Int, bind : Int #if multidriver, driver : Driver #end };
#elseif (limen && ((gfx_dx11 && (gfx_dx12 || gfx_vulkan || gfx_opengl)) || (gfx_dx12 && (gfx_vulkan || gfx_opengl)) || (gfx_vulkan && gfx_opengl)))
typedef Texture = Dynamic;
#elseif (limen && gfx_vulkan)
typedef Texture = { img : limen.graphics.vulkan.memory.Memory.VkImage, mem : limen.graphics.vulkan.memory.Memory.VkDeviceMemory, view : limen.graphics.vulkan.memory.Memory.VkImageView };
#elseif (limen && gfx_dx12)
typedef Texture = h3d.impl.driver.dx12.resource.TextureData;
#elseif (limen && gfx_dx11)
typedef Texture = { res : limen.graphics.d3d11.DX11Core.Resource, view : limen.graphics.d3d11.DX11Resources.ShaderResourceView, ?depthView : limen.graphics.d3d11.DX11States.DepthStencilView, ?readOnlyDepthView : limen.graphics.d3d11.DX11States.DepthStencilView, rt : Array<limen.graphics.d3d11.DX11Resources.RenderTargetView>, ?views : Array<limen.graphics.d3d11.DX11Resources.ShaderResourceView> };
#elseif limen
typedef Texture = { t : limen.graphics.opengl.OpenGLTypes.Texture, width : Int, height : Int, internalFmt : Int, pixelFmt : Int, bits : Int, bind : Int #if multidriver, driver : Driver #end };
#elseif usegl
typedef Texture = { t : haxe.GLTypes.Texture, width : Int, height : Int, internalFmt : Int, pixelFmt : Int, bits : Int, bind : Int };
#elseif usesys
typedef Texture = haxe.GraphicsDriver.Texture;
#else
typedef Texture = {};
#end
