package h3d.impl.driver.dx12.descriptor;

#if ((hldx && gfx_dx12) || (hlsdl && gfx_dx12))
import dx.Dx12;

class ScratchHeapArray {
	var heaps : Array<ScratchHeap>;
	var type : DescriptorHeapType;
	var size : Int;
	var cursor : Int;

	public function new(type,size) {
		this.type = type;
		this.size = size;
		heaps = [];
	}

	public function reset() {
		cursor = 0;
	}

	public function next() {
		var h = heaps[cursor++];
		if(h == null) {
			h = new ScratchHeap(type, size);
			heaps.push(h);
		} else
			h.clear();
		return h;
	}

	public function getSize() {
		var size : Float = 0;
		for(h in heaps)
			size += h.getSize();
		return size;
	}
}
#end
