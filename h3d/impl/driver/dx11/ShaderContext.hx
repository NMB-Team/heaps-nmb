package h3d.impl.driver.dx11;

#if ((hldx && !gfx_dx12) || (hlsdl && gfx_dx11))
import dx.Driver.Shader;

@:noCompletion
class ShaderContext {
	public var shader : Shader;
	public var globalsSize : Int;
	public var paramsSize : Int;
	public var texturesCount : Int;
	public var bufferCount : Int;
	public var paramsContent : hl.Bytes;
	public var globals : dx.Resource;
	public var params : dx.Resource;
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
