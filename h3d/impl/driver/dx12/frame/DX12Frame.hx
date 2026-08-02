package h3d.impl.driver.dx12.frame;

#if (limen && gfx_dx12)
import limen.graphics.d3d12.DX12Core.Address;
import limen.graphics.d3d12.command.Commands.CommandAllocator;
import limen.graphics.d3d12.command.Commands.CommandList;
import limen.graphics.d3d12.query.Queries.QueryHeap;
import limen.graphics.d3d12.resource.Resources.Dx12Resource;
import limen.graphics.d3d12.resource.Resources.GpuResource;

import haxe.Int64;
import h3d.impl.allocator.BlockAllocator;
import h3d.impl.allocator.MemoryBlock;
import h3d.impl.driver.Query;
import h3d.impl.driver.dx12.descriptor.ScratchHeap;
import h3d.impl.driver.dx12.descriptor.ScratchHeapArray;
import h3d.impl.driver.dx12.resource.ResourceData;
#if dlss_allowed
import limen.graphics.d3d12.dlss.DLSS.DLSSFrameToken;
#end

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
	#if dlss_allowed
	public var dlssFrameToken : DLSSFrameToken;
	#end

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
