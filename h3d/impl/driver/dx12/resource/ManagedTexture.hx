package h3d.impl.driver.dx12.resource;

#if (limen && gfx_dx12 && gfx_d3d12ma && !console)
import limen.graphics.renderer.d3d12.memory.D3D12MemoryAllocator;

class ManagedTexture {
	public final allocation : AllocationHandle;
	public final texture : TextureData;

	public function new(allocation:AllocationHandle, texture:TextureData) {
		this.allocation = allocation;
		this.texture = texture;
	}

	public function release() {
		D3D12MemoryAllocator.release(allocation);
		texture.res = null;
		texture.managed = null;
	}
}
#end
