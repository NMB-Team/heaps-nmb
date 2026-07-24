package h3d.impl.driver.opengl;

#if ((js||hlsdl||usegl) && !(hlsdl && gfx_vulkan && !gfx_opengl))
#if js
private typedef Uniform = js.html.webgl.UniformLocation;
private typedef GLShader = js.html.webgl.Shader;
#elseif hlsdl
private typedef Uniform = sdl.GL.Uniform;
private typedef GLShader = sdl.GL.Shader;
#elseif usegl
private typedef Uniform = haxe.GLTypes.Uniform;
private typedef GLShader = haxe.GLTypes.Shader;
#end

@:noCompletion
class CompiledShader {
	public var s : GLShader;
	public var kind : hxsl.Ast.FunctionKind;
	public var globals : Uniform;
	public var params : Uniform;
	public var textures : Array<{ u : Uniform, t : hxsl.Ast.Type, mode : Int }>;
	public var buffers : Array<Int>;
	public var bufferTypes : Array<hxsl.Ast.BufferKind>;
	public var shader : hxsl.RuntimeShader.RuntimeShaderData;

	public function new(s,kind,shader) {
		this.s = s;
		this.kind = kind;
		this.shader = shader;
	}
}
#end
