package h3d.impl.driver.dx11;

#if ((hldx && !gfx_dx12) || (hlsdl && gfx_dx11))
import dx.Driver.Layout;

@:noCompletion
class CompiledShader {
	public var vertex : ShaderContext;
	public var fragment : ShaderContext;
	public var format : hxd.BufferFormat;
	public var perInst : Array<Int>;
	public var layouts : Map<Int, Layout>;
	public var vertexBytes : haxe.io.Bytes;
	public var semanticNames : Array<String>;

	public function new() {
	}
}
#end
