package h3d.impl.driver.dx12.descriptor;

#if (limen && gfx_dx12)

import limen.graphics.renderer.d3d12.DX12Core.Address;
import limen.graphics.renderer.d3d12.descriptor.DescriptorHeap.DescriptorHeap;
import limen.graphics.renderer.d3d12.descriptor.DescriptorHeap.DescriptorHeapDesc;
import limen.graphics.renderer.d3d12.descriptor.DescriptorHeap.DescriptorHeapFlags;
import limen.graphics.renderer.d3d12.descriptor.DescriptorHeap.DescriptorHeapType;
import limen.graphics.renderer.d3d12.internal.D3D12Bindings as Dx12;

import haxe.Int64;
import h3d.impl.driver.dx12.DX12Driver;

@:allow(h3d.impl.driver.dx12.descriptor)
class DescriptorHeapBase {
	#if dx12_descriptor_profile
	public var allocations = 0;
	public var allocatedDescriptors = 0.;
	public var peakUsage = 0;
	public var creations = 0;
	public static var totalCreations = 0;
	public static var totalGrowths = 0;
	public var allocationSeconds = 0.;
	public var resetSeconds = 0.;
	public var resets = 0;
	public static var copyCalls = 0;
	public static var copiedDescriptors = 0.;
	public static var copySeconds = 0.;
	#end

	public var stride(default,null) : Int;
	public var size(default,null) : Int;
	public var address(default,null) : Address;
	var type : DescriptorHeapType;
	var heap : DescriptorHeap;
	var cpuToGpu : Int64;
	var shaderVisible : Bool;

	public function new(type,size=8,shaderVisible=true) {
		this.type = type;
		this.shaderVisible = shaderVisible && (type == CBV_SRV_UAV || type == SAMPLER);
		this.stride = Dx12.getDescriptorHandleIncrementSize(type);
		allocHeap(size);
	}

	public function getSize() {
		return size * stride;
	}

	function allocHeap(size:Int) {
		var desc = new DescriptorHeapDesc();
		desc.type = type;
		desc.numDescriptors = size;
		if(shaderVisible)
			desc.flags = SHADER_VISIBLE;
		heap = DX12Driver.allocCheck(() -> new DescriptorHeap(desc));
		#if dx12_descriptor_profile
		if( this.size > 0 ) totalGrowths++;
		totalCreations++;
		creations++;
		#end
		this.size = size;
		address = heap.getHandle(false);
		cpuToGpu = desc.flags == SHADER_VISIBLE ? (heap.getHandle(true).value - address.value) : 0;
	}

	public dynamic function onFree(prev:DescriptorHeap, prevSize:Int) {
		throw 'Descriptor heap exhausted (type=$type, capacity=$size, shaderVisible=$shaderVisible)';
	}

	public inline function toGPU(address:Address):Address {
		return new Address(address.value + cpuToGpu);
	}

	public inline function getIndex(cpuAddress:Address):Int {
		return Std.int((cpuAddress.value - address.value).low / stride);
	}

	public inline function getCpuAddressAt(index:Int):Address {
		return address.offset(index * stride);
	}

	inline function getNextHeapSize():Int {
		return hxd.Math.imax(size + 1, (size * 3) >> 1);
	}
}
#end
