package h3d.impl.driver.dx12.shader;

#if (limen && gfx_dx12)
import limen.d3d12.Types.Address;
import limen.d3d12.resource.Resources.GpuResource;

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
	public var textureTable = new TextureTable();
	public var alternateTextureTable = new TextureTable();
	public var boundTextureTable : TextureTable;
	public var textureTableBindingGeneration = -1;
	public var paramsCache = new h3d.impl.driver.ShaderParamCache();
	public var paramsGeneration = -1;

	public function new() {
	}
}

class TextureTable {
	public var srv : Address;
	public var samplers : Address;
	public var heapGeneration = -1;
	public var textures : Array<Texture> = [];
	public var resources : Array<GpuResource> = [];
	public var bits : Array<Int> = [];
	public var residentMips : Array<Int> = [];
	public var flags : Array<Int> = [];

	public function new() {}
}
#end
