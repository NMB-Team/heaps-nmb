package h3d.impl.driver;

#if macro
typedef Query = {};
#elseif js
typedef Query = {};
#elseif (hlsdl && ((gfx_dx11 && (gfx_dx12 || gfx_vulkan || gfx_opengl)) || (gfx_dx12 && (gfx_vulkan || gfx_opengl)) || (gfx_vulkan && gfx_opengl)))
typedef Query = Dynamic;
#elseif (hlsdl && gfx_vulkan)
typedef Query = {};
#elseif (hlsdl && gfx_dx12)
typedef Query = h3d.impl.driver.dx12.query.QueryData;
#elseif (hlsdl && gfx_dx11)
typedef Query = {};
#elseif hlsdl
typedef Query = { q : sdl.GL.Query, kind : QueryKind };
#elseif usegl
typedef Query = { q : haxe.GLTypes.Query, kind : QueryKind };
#elseif (hldx && gfx_dx12)
typedef Query = h3d.impl.driver.dx12.query.QueryData;
#elseif hldx
typedef Query = {};
#elseif usesys
typedef Query = haxe.GraphicsDriver.Query;
#else
typedef Query = {};
#end
