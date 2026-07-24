package h3d.impl.driver.dx12.frame;

#if ((hldx && gfx_dx12) || (hlsdl && gfx_dx12))
import dx.Dx12;
import haxe.Int64;
import h3d.impl.allocator.BlockAllocator;
import h3d.impl.allocator.MemoryBlock;
import h3d.impl.driver.Query;
import h3d.impl.driver.dx12.descriptor.ScratchHeap;
import h3d.impl.driver.dx12.descriptor.ScratchHeapArray;
import h3d.impl.driver.dx12.resource.ResourceData;

class DX12Frame {
	public var backBuffer : ResourceData;
	public var backBufferView : Address;
	public var depthBuffer : GpuResource;
	public var allocator : CommandAllocator;
	public var commandList : CommandList;
	public var copyAllocator : CommandAllocator;
	public var copyCommandList : CommandList;
	public var fenceValue : Int64;
	public var toRelease : Array<Dx12Resource> = [];
	public var texHandlesToRelease : Array<h3d.mat.TextureHandle> = [];
	public var bufHandlesToRelease : Array<h3d.BufferHandle> = [];
	public var srvHeap : ScratchHeap;
	public var samplerHeap : ScratchHeap;
	public var srvHeapCache : ScratchHeapArray;
	public var samplerHeapCache : ScratchHeapArray;
	public var queryHeaps : Array<QueryHeap> = [];
	public var queriesPending : Array<Query> = [];
	public var queryCurrentHeap : Int;
	public var queryHeapOffset : Int;
	public var queryBuffer : GpuResource;
	public var dynamicBufferAlloc : BlockAllocator;
	public var pendingCopyBuffers : Array<MemoryBlock> = [];

	public function new() {
	}

	public function getSize() {
		var size : Float = 0;
		size += srvHeapCache.getSize();
		size += samplerHeapCache.getSize();
		return size;
	}
}
#end
