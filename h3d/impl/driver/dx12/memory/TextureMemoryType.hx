package h3d.impl.driver.dx12.memory;

#if (limen && gfx_dx12)
import limen.graphics.renderer.d3d12.internal.D3D12Bindings as Dx12;
import limen.graphics.renderer.d3d12.resource.Resources.Heap;
import limen.graphics.renderer.d3d12.resource.Resources.HeapDesc;

import h3d.impl.allocator.MemoryPage;
import h3d.impl.allocator.MemoryType;

class TextureMemoryType extends MemoryType {
	var desc : HeapDesc;

	public function new() {
		desc = new HeapDesc();
		desc.properties.type = DEFAULT;
		desc.alignment = 65536;
		desc.flags.set(DENY_BUFFERS);
		desc.flags.set(DENY_RT_DS_TEXTURES);
		desc.flags.set(CREATE_NOT_ZEROED);
	}

	public function alloc(size:Int) {
		desc.sizeInBytes = (size + 65535) & ~65535;
		var heap = Dx12.createHeap(desc);
		if( heap == null )
			return null;
		heap.setName("TextureHeapPage");
		return new MemoryPage(null, 0, desc.sizeInBytes.low, heap);
	}

	public function free(page:MemoryPage) {
		var heap : Heap = page.ref;
		heap.release();
	}
}
#end
