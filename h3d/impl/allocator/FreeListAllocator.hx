package h3d.impl.allocator;

#if hl
class FreeListAllocator extends Allocator {
	private var lists : Array<FreeList> = [];

	override private function init() {
		super.init();
		useMemoryPool = true;
	}

	override public function dispose() {
		super.dispose();
		lists = [];
	}

	override private function freePage(page:MemoryPage) {
		var index = pages.indexOf(page);
		lists.splice(index, 1);
		super.freePage(page);
	}

	private function tryAlloc(size:Int, alignment:Int, out:MemoryBlock):Int {
		for(index => page in pages) {
			var freeList = lists[index];
			if(freeList == null) {
				freeList = new FreeList(page.size);
				lists[index] = freeList;
			}
			var position = freeList.alloc(size, alignment, true);
			if(position >= 0) {
				out.page = page;
				return position;
			}
		}
		return -1;
	}

	public function getUsedSize() {
		var free = 0.;
		for(list in lists)
			free += list.getFreeSize();
		return getTotalSize() - free * mem.stride;
	}

	public function free(memory:MemoryBlock) {
		if(memory.page == null)
			throw "assert";
		var index = pages.indexOf(memory.page);
		var freeList = lists[index];
		freeList.free(mem.stride == 1 ? memory.offset : Std.int(memory.offset / mem.stride), memory.size);
		memory.page = null;
		if(useMemoryPool)
			pool.push(memory);
	}

	public function trim(maxSize:Float) {
		var total = getTotalSize();
		while(total > maxSize) {
			var largest : MemoryPage = null;
			for(index => page in pages)
				if(lists[index] != null && lists[index].isFullyFree(page.size) && (largest == null || page.size > largest.size))
					largest = page;
			if(largest == null)
				break;
			total -= largest.size * mem.stride;
			freePage(largest);
		}
	}
}
#end
