package h3d.impl.driver.dx12.descriptor;

#if ((hldx && gfx_dx12) || (hlsdl && gfx_dx12))
import dx.Dx12;

class ScratchHeap extends DescriptorHeapBase {
	var cursor : Int;
	public var available(get,never) : Int;

	override function allocHeap(size:Int) {
		cursor = 0;
		if(type == SAMPLER && size > 2048)
			throw "Max heap size reached";
		super.allocHeap(size);
	}

	public function alloc(count:Int) {
		if(cursor + count > size) {
			var prevCursor = cursor;
			cursor = 0;
			var prev = heap;
			allocHeap(getNextHeapSize());
			onFree(prev, prevCursor);
		}
		var pos = cursor;
		cursor += count;
		return address.offset(pos * stride);
	}

	inline function get_available() {
		return size - cursor;
	}

	public function clear() {
		cursor = 0;
	}
}
#end
