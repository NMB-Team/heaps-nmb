package h3d.impl.allocator;

#if hl
class BlockAllocator extends Allocator {
	public static var MAX_KEEP_FRAMES = 3600;

	private var cursor : Int;
	private var currentPage : Int;
	private var unusedFrames : Array<Int> = [];

	override public function dispose() {
		super.dispose();
		cursor = 0;
		currentPage = 0;
		unusedFrames = [];
	}

	override private function freePage(page:MemoryPage) {
		var index = pages.indexOf(page);
		unusedFrames.splice(index, 1);
		if(currentPage == index) {
			cursor = 0;
		} else if(currentPage > index)
			currentPage--;
		super.freePage(page);
	}

	public function free(memory:MemoryBlock) {
		throw "Cannot free in BlockAllocator";
	}

	private function tryAlloc(size:Int, alignment:Int, out:MemoryBlock) {
		while(true) {
			var page = pages[currentPage];
			if(page == null)
				return -1;
			var position = AllocatorTools.align(cursor, alignment);
			if(position + size <= page.size) {
				out.page = page;
				cursor = position + size;
				return position;
			}
			cursor = 0;
			currentPage++;
		}
	}

	public function getUsedSize() {
		var size : Float = cursor;
		for(index in 0...currentPage)
			size += pages[index].size;
		return size * mem.stride;
	}

	public function reset(forceDispose = false) {
		var usedPages = cursor == 0 ? currentPage : currentPage + 1;
		while(unusedFrames.length < pages.length)
			unusedFrames.push(0);
		var index = pages.length - 1;
		while(index > 0) {
			if(index < usedPages)
				unusedFrames[index] = 0;
			else if(forceDispose || ++unusedFrames[index] > MAX_KEEP_FRAMES)
				freePage(pages[index]);
			index--;
		}
		cursor = 0;
		currentPage = 0;
	}
}
#end
