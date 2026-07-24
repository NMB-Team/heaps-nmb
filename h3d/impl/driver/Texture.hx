package h3d.impl.driver;

#if macro
typedef Texture = {};
#elseif js
typedef Texture = { t : js.html.webgl.Texture, width : Int, height : Int, internalFmt : Int, pixelFmt : Int, bits : Int, bind : Int #if multidriver, driver : Driver #end };
#elseif (hlsdl && ((gfx_dx11 && (gfx_dx12 || gfx_vulkan || gfx_opengl)) || (gfx_dx12 && (gfx_vulkan || gfx_opengl)) || (gfx_vulkan && gfx_opengl)))
typedef Texture = Dynamic;
#elseif (hlsdl && gfx_vulkan)
typedef Texture = { img : sdl.Vulkan.VkImage, mem : sdl.Vulkan.VkDeviceMemory, view : sdl.Vulkan.VkImageView };
#elseif (hlsdl && gfx_dx12)
typedef Texture = h3d.impl.driver.dx12.resource.TextureData;
#elseif (hlsdl && gfx_dx11)
typedef Texture = { res : dx.Resource, view : dx.Driver.ShaderResourceView, ?depthView : dx.Driver.DepthStencilView, ?readOnlyDepthView : dx.Driver.DepthStencilView, rt : Array<dx.Driver.RenderTargetView>, ?views : Array<dx.Driver.ShaderResourceView> };
#elseif hlsdl
typedef Texture = { t : sdl.GL.Texture, width : Int, height : Int, internalFmt : Int, pixelFmt : Int, bits : Int, bind : Int #if multidriver, driver : Driver #end };
#elseif usegl
typedef Texture = { t : haxe.GLTypes.Texture, width : Int, height : Int, internalFmt : Int, pixelFmt : Int, bits : Int, bind : Int };
#elseif (hldx && gfx_dx12)
typedef Texture = h3d.impl.driver.dx12.resource.TextureData;
#elseif hldx
typedef Texture = { res : dx.Resource, view : dx.Driver.ShaderResourceView, ?depthView : dx.Driver.DepthStencilView, ?readOnlyDepthView : dx.Driver.DepthStencilView, rt : Array<dx.Driver.RenderTargetView>, ?views : Array<dx.Driver.ShaderResourceView> };
#elseif usesys
typedef Texture = haxe.GraphicsDriver.Texture;
#else
typedef Texture = {};
#end
