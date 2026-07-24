package h3d.impl.driver.opengl;

#if ((js||hlsdl||usegl) && !(hlsdl && gfx_vulkan && !gfx_opengl))
#if js
private typedef Program = js.html.webgl.Program;
#elseif hlsdl
private typedef Program = sdl.GL.Program;
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
