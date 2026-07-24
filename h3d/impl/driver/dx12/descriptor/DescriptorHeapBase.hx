package h3d.impl.driver.dx12.descriptor;

#if ((hldx && gfx_dx12) || (hlsdl && gfx_dx12))
import dx.Dx12;
import haxe.Int64;
import h3d.impl.driver.dx12.DX12Driver;

@:allow(h3d.impl.driver.dx12.descriptor)
class DescriptorHeapBase {
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
		this.size = size;
		address = heap.getHandle(false);
		cpuToGpu = desc.flags == SHADER_VISIBLE ? (heap.getHandle(true).value - address.value) : 0;
	}

	public dynamic function onFree(prev:DescriptorHeap, prevSize:Int) {
		throw "Too many buffers";
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
		return (size * 3) >> 1;
	}
}
#end
