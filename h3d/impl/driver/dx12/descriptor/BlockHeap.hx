package h3d.impl.driver.dx12.descriptor;

#if (limen && gfx_dx12)
class BlockHeap extends DescriptorHeapBase {
	var freeList : Array<Int>;
	public var available(get,never) : Int;

	override public function new(type,size,shaderVisible) {
		if(shaderVisible)
			throw "BlockHeap cannot be shader visible as its content is copied on resize";
		super(type, size, false);
		freeList = [for(i in 0...size) i];
	}

	function resize() {
		var prevSize = size;
		var prev = heap;
		allocHeap(getNextHeapSize());
		for(i in prevSize + 1...size)
			freeList.push(i);
		onFree(prev, prevSize);
	}

	public function allocIndex():Int {
		#if dx12_descriptor_profile
		var started = haxe.Timer.stamp();
		#end
		var idx = freeList.pop();
		if(idx == null) {
			idx = size;
			resize();
		}
		#if dx12_descriptor_profile
		allocations++;
		allocatedDescriptors += 1;
		peakUsage = hxd.Math.imax(peakUsage, size - freeList.length);
		allocationSeconds += haxe.Timer.stamp() - started;
		#end
		return idx;
	}

	public function disposeIndex(index:Int) {
		freeList.push(index);
	}

	inline function get_available() {
		return freeList.length;
	}

	public inline function isEmpty() {
		return available == size;
	}
}
#end
