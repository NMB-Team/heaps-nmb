package h3d.impl.driver.dx11;

#if (limen && gfx_dx11)
import limen.graphics.renderer.d3d11.pipeline.InputLayout.Layout;

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
