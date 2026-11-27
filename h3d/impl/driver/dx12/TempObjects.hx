package h3d.impl.driver.dx12;

#if (limen && gfx_dx12)

import limen.d3d12.Types.Address;
import limen.d3d12.Types.ClearColor;
import limen.d3d12.Types.ClearValue;
import limen.d3d12.Types.Rect;
import limen.d3d12.Types.Viewport;
import limen.d3d12.command.Commands.VertexBufferView;
import limen.d3d12.descriptor.DescriptorHeap.DescriptorHeap;
import limen.d3d12.descriptor.ResourceViews.BufferSRV;
import limen.d3d12.descriptor.ResourceViews.ConstantBufferViewDesc;
import limen.d3d12.descriptor.ResourceViews.DepthStencilViewDesc;
import limen.d3d12.descriptor.ResourceViews.RenderTargetViewDesc;
import limen.d3d12.descriptor.ResourceViews.ShaderComponentMapping;
import limen.d3d12.descriptor.ResourceViews.Tex2DSRV;
import limen.d3d12.descriptor.ResourceViews.UAVBufferViewDesc;
import limen.d3d12.descriptor.ResourceViews.UAVTextureViewDesc;
import limen.d3d12.pipeline.Pipeline.Dx12SamplerDesc;
import limen.d3d12.resource.Resources.HeapProperties;
import limen.d3d12.resource.Resources.ResourceBarrier;
import limen.d3d12.resource.Resources.SubResourceData;
import limen.d3d12.resource.Resources.TextureCopyLocation;

import h3d.impl.driver.dx12.resource.ResourceData;

@:noCompletion
@:struct
class TempObjects {
	public var renderTargets : hl.BytesAccess<Address>;
	public var depthStencils : hl.BytesAccess<Address>;
	public var copyableInfosBytes : hl.Bytes;
	public var vertexViews : hl.CArray<VertexBufferView>;
	public var vertexViewRefs : Array<VertexBufferView>;
	public var vertexViewCount : Int;
	public var descriptors2 : hl.NativeArray<DescriptorHeap>;
	public var barriers : hl.CArray<ResourceBarrier>;
	// keep the CArray owners alive while reusing their element wrappers
	public var barrierViews : Array<ResourceBarrier>;
	public var resourcesToTransition : hl.NativeArray<ResourceData>;
	public var maxBarriers : Int;
	public var barrierCount : Int;
	public var needUAVBarrier : Bool = false;
	@:packed public var heap(default,null) : HeapProperties;
	@:packed public var barrier(default,null) : ResourceBarrier;
	@:packed public var clearColor(default,null) : ClearColor;
	@:packed public var clearValue(default,null) : ClearValue;
	@:packed public var viewport(default,null) : Viewport;
	@:packed public var rect(default,null) : Rect;
	@:packed public var bufferSRV(default,null) : BufferSRV;
	@:packed public var texViewDesc(default,null) : Tex2DSRV;
	@:packed public var samplerDesc(default,null) : Dx12SamplerDesc;
	@:packed public var vertexGlobalDesc(default,null) : ConstantBufferViewDesc;
	@:packed public var fragmentGlobalDesc(default,null) : ConstantBufferViewDesc;
	@:packed public var cbvDesc(default,null) : ConstantBufferViewDesc;
	@:packed public var rtvDesc(default,null) : RenderTargetViewDesc;
	@:packed public var uavDesc(default,null) : UAVBufferViewDesc;
	@:packed public var wtexDesc(default,null) : UAVTextureViewDesc;
	@:packed public var subResourceData(default, null) : SubResourceData;
	@:packed public var srcTextureLocation(default, null) : TextureCopyLocation;
	@:packed public var dstTextureLocation(default, null) : TextureCopyLocation;
	@:packed public var dstStencilViewDesc(default,null) : DepthStencilViewDesc;
	public var pass : h3d.mat.Pass;

	public function new() {
		renderTargets = new hl.Bytes(8 * 8);
		depthStencils = new hl.Bytes(8);
		copyableInfosBytes = new hl.Bytes(8 * 3);
		allocateVertexViews(16);
		allocateBarriers(100);
		resourcesToTransition = new hl.NativeArray(maxBarriers);
		barrierCount = 0;
		pass = new h3d.mat.Pass("default");
		pass.stencil = new h3d.mat.Stencil();
		bufferSRV.dimension = BUFFER;
		bufferSRV.flags = RAW;
		bufferSRV.shader4ComponentMapping = ShaderComponentMapping.DEFAULT;
		samplerDesc.comparisonFunc = NEVER;
		samplerDesc.maxLod = 1e30;
		descriptors2 = new hl.NativeArray(2);
		uavDesc.viewDimension = BUFFER;
		barrier.subResource = -1;
	}

	public function allocateVertexViews(count : Int) {
		var storage = hl.CArray.alloc(VertexBufferView, count);
		var refs = [for( i in 0...count ) storage[i]];

		// drop old wrappers before replacing their owning block
		vertexViewRefs = refs;
		vertexViews = storage;
		vertexViewCount = count;
	}

	public function allocateBarriers(count : Int) {
		var storage = hl.CArray.alloc(ResourceBarrier, count);
		var refs = [for( i in 0...count ) storage[i]];

		barrierViews = refs;
		barriers = storage;
		maxBarriers = count;
	}
}
#end
