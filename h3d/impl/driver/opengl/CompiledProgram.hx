package h3d.impl.driver.opengl;

#if (js || usegl || (limen && (gfx_opengl || (!gfx_dx11 && !gfx_dx12 && !gfx_vulkan))))
#if js
private typedef Program = js.html.webgl.Program;
#elseif limen
private typedef Program = limen.graphics.opengl.OpenGLTypes.Program;
#elseif usegl
private typedef Program = haxe.GLTypes.Program;
#end

@:noCompletion
class CompiledProgram {
	public var p : Program;
	public var vertex : CompiledShader;
	public var fragment : CompiledShader;
	public var format : hxd.BufferFormat;
	public var attribs : Array<CompiledAttribute>;
	public var hasAttribIndex : Int;

	public function new() {
	}
}
#end
