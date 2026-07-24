package h3d.impl.driver.dx12.shader;

#if ((hldx && gfx_dx12) || (hlsdl && gfx_dx12))
import dx.Dx12.Address;
import h3d.impl.driver.Texture;

class ShaderRegisters {
	public var globals : Int;
	public var params : Int;
	public var buffers : Int;
	public var cbvCount : Int;
	public var storageCount : Int;
	public var textures : Int;
	public var samplers : Int;
	public var texturesCount : Int;
	public var texturesTypes : Array<hxsl.Ast.Type>;
	public var bufferTypes : Array<hxsl.Ast.BufferKind>;
	public var bufferStrides : Array<Int>;
	public var srv : Address;
	public var samplersView : Address;
	public var lastHeapCount : Int;
	public var lastTextures : Array<Texture> = [];
	public var lastTexturesBits : Array<Int> = [];

	public function new() {
	}
}
#end
