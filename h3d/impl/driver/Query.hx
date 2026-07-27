package h3d.impl.driver;

#if macro
typedef Query = {};
#elseif js
typedef Query = {};
#elseif (limen && ((gfx_dx11 && (gfx_dx12 || gfx_vulkan || gfx_opengl)) || (gfx_dx12 && (gfx_vulkan || gfx_opengl)) || (gfx_vulkan && gfx_opengl)))
typedef Query = Dynamic;
#elseif (limen && gfx_vulkan)
typedef Query = {};
#elseif (limen && gfx_dx12)
typedef Query = h3d.impl.driver.dx12.query.QueryData;
#elseif (limen && gfx_dx11)
typedef Query = {};
#elseif limen
typedef Query = { q : limen.graphics.opengl.OpenGLTypes.Query, kind : QueryKind };
#elseif usegl
typedef Query = { q : haxe.GLTypes.Query, kind : QueryKind };
#elseif usesys
typedef Query = haxe.GraphicsDriver.Query;
#else
typedef Query = {};
#end
