package h3d.impl.driver.dx12.memory;

#if (limen && gfx_dx12)
import limen.graphics.d3d12.internal.D3D12Bindings as Dx12;
import limen.graphics.d3d12.resource.Resources.Dx12ResourceDimension;
import limen.graphics.d3d12.resource.Resources.GpuResource;
import limen.graphics.d3d12.resource.Resources.HeapFlag;
import limen.graphics.d3d12.resource.Resources.HeapFlag.CREATE_NOT_ZEROED;
import limen.graphics.d3d12.resource.Resources.HeapProperties;
import limen.graphics.d3d12.resource.Resources.HeapType;
import limen.graphics.d3d12.resource.Resources.ResourceDesc;
import limen.graphics.d3d12.resource.Resources.ResourceFlag;
import limen.graphics.d3d12.resource.Resources.ResourceState;
import limen.graphics.d3d12.resource.Resources.TextureLayout;

import h3d.impl.allocator.MemoryPage;
import h3d.impl.allocator.MemoryType;

class BufferMemoryType extends MemoryType {

	var heapType : HeapType;
	var startState : ResourceState;
	var uav : Bool;
	var resourceName : String;

	public function new(heapType, startState, uav = false, resourceName = "BufferAllocator") {
		this.heapType = heapType;
		this.startState = startState;
		this.uav = uav;
		this.resourceName = resourceName;
		alignment = 256;
	}

	public function alloc(size:Int) {
		var heap = new HeapProperties();
		heap.type = heapType;
		var desc = new ResourceDesc();
		desc.dimension = BUFFER;
		desc.width = size;
		desc.height = 1;
		desc.depthOrArraySize = 1;
		desc.mipLevels = 1;
		desc.sampleDesc.count = 1;
		desc.layout = ROW_MAJOR;

		var flags = new haxe.EnumFlags();
		flags.set(CREATE_NOT_ZEROED);
		if(uav)
			desc.flags.set(ALLOW_UNORDERED_ACCESS);

		var res = Dx12.createCommittedResource(heap, flags, desc, startState, null);
		if(res == null)
			return null;
		res.setName(resourceName + "Page");
		var cpuAddress = res.map(0, null);
		return new MemoryPage(cpuAddress, res.getGpuVirtualAddress(), size, res);
	}

	public function free(mem:MemoryPage) {
		var res : GpuResource = mem.ref;
		res.unmap(0, null);
		res.release();
	}
}
#end
