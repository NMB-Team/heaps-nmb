package h3d.impl.driver.dx12;

#if ((hldx && gfx_dx12) || (hlsdl && gfx_dx12))
import dx.Dx12;
import dx.Dx12.Dx12SamplerDesc;
import h3d.impl.driver.dx12.resource.ResourceData;

private typedef Driver = Dx12;

@:noCompletion
@:struct
class TempObjects {
	public var renderTargets : hl.BytesAccess<Address>;
	public var depthStencils : hl.BytesAccess<Address>;
	public var copyableInfosBytes : hl.Bytes;
	public var vertexViews : hl.CArray<VertexBufferView>;
	public var vertexViewCount : Int;
	public var descriptors2 : hl.NativeArray<DescriptorHeap>;
	public var barriers : hl.CArray<ResourceBarrier>;
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
		vertexViewCount = 16;
		vertexViews = hl.CArray.alloc(VertexBufferView, vertexViewCount);
		maxBarriers = 100;
		barriers = hl.CArray.alloc(ResourceBarrier, maxBarriers);
		var allSubresource = #if ((hldx >= version("1.16.0") || hlsdl >= version("1.16.0"))) Driver.getConstant(RESOURCE_BARRIER_ALL_SUBRESOURCES) #else 0xffffffff #end;
		for(i in 0...maxBarriers)
			barriers[i].subResource = allSubresource;
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
}
#end
