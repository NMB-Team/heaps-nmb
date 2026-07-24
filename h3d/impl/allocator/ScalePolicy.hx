package h3d.impl.allocator;

#if hl
class ScalePolicy extends AllocatorPolicy {
	var minSize : Int;
	var scaleFactor : Float;

	public function new(minSize = 0, scaleFactor = 1.5) {
		if(minSize <= 2)
			minSize = 2;
		this.minSize = minSize;
		this.scaleFactor = scaleFactor;
	}

	public function getNewPageSize(pages:Array<MemoryPage>, requestedSize:Int):Int {
		var size : Float = minSize;
		if(pages.length > 0) {
			for(page in pages)
				if(page.size > size)
					size = page.size;
			size = Math.ceil(size * scaleFactor);
		}
		if(size < requestedSize)
			size = requestedSize;
		if(size > 0x7FFFFFFF)
			throw "Allocation size overflow";
		return Std.int(size);
	}
}
#end
