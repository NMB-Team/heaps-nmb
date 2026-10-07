package h3d.impl.driver.dx12.memory;

#if (limen && gfx_dx12)
import limen.graphics.renderer.d3d12.internal.D3D12Bindings as Dx12;
import limen.graphics.renderer.d3d12.resource.Resources.Heap;
import limen.graphics.renderer.d3d12.resource.Resources.ResourceAllocationInfo;
import limen.graphics.renderer.d3d12.resource.Resources.ResourceDesc;

import h3d.impl.allocator.FreeListAllocator;
import h3d.impl.allocator.ScalePolicy;
import h3d.impl.driver.dx12.resource.TextureData;

class TextureAllocator extends FreeListAllocator {
	static inline var SMALL_ALIGN = 4096;
	var pageSize : Int;
	var allocInfo = new ResourceAllocationInfo();

	public function new(pageSize:Int) {
		this.pageSize = pageSize;
		var policy = new ScalePolicy(pageSize, 1);
		super(new TextureMemoryType(), policy);
		name = "TextureHeap";
	}

	public function getAllocSize(t:h3d.mat.Texture, desc:ResourceDesc) {
		if( t.flags.has(Is3D) || hxd.Pixels.calcDataSize(desc.width.low, desc.height, t.format) * t.layerCount > 65536 )
			return -1;
		desc.alignment = SMALL_ALIGN;
		Dx12.getResourceAllocationInfo(desc, allocInfo);
		if( allocInfo.alignment != SMALL_ALIGN || allocInfo.sizeInBytes.high != 0 || allocInfo.sizeInBytes.low <= 0 ) {
			desc.alignment = 0;
			return -1;
		}
		return allocInfo.sizeInBytes.low;
	}

	public function allocTexture(td:TextureData, desc:ResourceDesc, size:Int) {
		var memory = try alloc(size, null, desc.alignment.low) catch( e : String ) {
			if( e == "Out of memory" )
				return null;
			throw e;
		}
		var heap : Heap = memory.page.ref;
		var res = Dx12.createPlacedResource(heap, memory.offset, desc, td.state, null);
		if( res == null ) {
			free(memory);
			trim(pageSize);
			return null;
		}
		td.memory = memory;
		td.needsAliasingBarrier = true;
		return res;
	}

	public function freeTexture(td:TextureData) {
		if( td.memory == null )
			return;
		free(td.memory);
		td.memory = null;
		trim(pageSize);
	}
}
#end
