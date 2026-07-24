package h3d.impl.driver.dx12.memory;

#if ((hldx && gfx_dx12) || (hlsdl && gfx_dx12))
import dx.Dx12;
import h3d.impl.allocator.MemoryPage;
import h3d.impl.allocator.MemoryType;

class HeapMemoryType extends MemoryType {

	var type : DescriptorHeapType;
	var shaderVisible : Bool;

	public function new(type,shaderVisible) {
		this.type = type;
		this.shaderVisible = shaderVisible;
		this.stride = Dx12.getDescriptorHandleIncrementSize(type);
	}

	public function alloc(size:Int) {
		var desc = new DescriptorHeapDesc();
		desc.type = type;
		desc.numDescriptors = size;
		if(shaderVisible)
			desc.flags = SHADER_VISIBLE;
		var heap = new DescriptorHeap(desc);
		if(heap == null)
			return null;
		#if (haxe_ver < 5)
		var address = new hl.NativeArray<haxe.Int64>(1);
		address[0] = heap.getHandle(false).value;
		var cpuAddress = (cast address : hl.NativeArray<hl.Bytes>)[0];
		#else
		var cpuAddress : hl.Bytes = hl.Api.unsafeCast(heap.getHandle(false));
		#end
		return new MemoryPage(cpuAddress, heap.getHandle(true).value, size, heap);
	}

	public function free(mem:MemoryPage) {
		var heap : DescriptorHeap = mem.ref;
		(heap : Dx12Resource).release();
	}
}
#end
