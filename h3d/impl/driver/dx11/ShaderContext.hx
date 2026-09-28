package h3d.impl.driver.dx11;

#if (limen && gfx_dx11)
import limen.graphics.renderer.d3d11.resource.Resources.Resource;
import limen.graphics.renderer.d3d11.shader.Shaders.Shader;

@:noCompletion
class ShaderContext {
	public var shader : Shader;
	public var globalsSize : Int;
	public var paramsSize : Int;
	public var texturesCount : Int;
	public var bufferCount : Int;
	public var paramsContent : hl.Bytes;
	public var globals : Resource;
	public var params : Resource;
	public var samplersMap : Array<Int>;
	public var texturesTypes : Array<hxsl.Ast.Type>;
	#if debug
	public var debugSource : String;
	#end

	public function new(shader) {
		this.shader = shader;
	}
}
#end
