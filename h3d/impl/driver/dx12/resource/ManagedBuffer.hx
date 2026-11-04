package h3d.impl.driver.dx12.resource;

#if (limen && gfx_dx12 && gfx_d3d12ma && !console)
import limen.graphics.renderer.d3d12.memory.D3D12MemoryAllocator;

class ManagedBuffer {
	public final allocation : AllocationHandle;
	public final buffer : BufferData;

	public function new(allocation:AllocationHandle, buffer:BufferData) {
		this.allocation = allocation;
		this.buffer = buffer;
	}

	public function release() {
		D3D12MemoryAllocator.release(allocation);
		buffer.res = null;
		buffer.managed = null;
	}
}
#end
