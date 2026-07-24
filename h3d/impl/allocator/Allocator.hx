package h3d.impl.allocator;

#if hl
@:allow(h3d.impl.allocator)
abstract class Allocator {
	public var mem : MemoryType;
	public var policy : AllocatorPolicy;
	public var pages : Array<MemoryPage> = [];
	public var debug = false;
	public var name : String;
	public var useMemoryPool = false;
	private var tmp = new MemoryBlock();
	private var lastLogTime : Float;
	private var allocCounter : Int;
	private var pool : Array<MemoryBlock> = [];

	public static var MAX_DEBUG_FREQ = 1.;

	public function new(mem:MemoryType, policy:AllocatorPolicy) {
		name = Type.getClassName(Type.getClass(this));
		this.mem = mem;
		this.policy = policy;
		init();
	}

	private function init() {
	}

	public function getTotalSize() {
		var total : Float = 0.;
		for(page in pages)
			total += page.size;
		return total * mem.stride;
	}

	public function dispose() {
		for(page in pages)
			mem.free(page);
		pages = [];
		pool = [];
	}

	private function toString() {
		var total = getTotalSize();
		var used = getUsedSize();
		return name + "[" + formatSize(total) + "/" + Std.int(total == 0 ? 0 : used * 100 / total) + "%]";
	}

	private function formatSize(size:Float) {
		static final units = ["B", "KB", "MB", "GB"];
		var unit = 0;
		while(size > 1024 && unit < units.length - 1) {
			size /= 1024;
			unit++;
		}
		return (Std.int(size * 100) / 100) + units[unit];
	}

	private function freePage(page:MemoryPage) {
		mem.free(page);
		pages.remove(page);
		if(debug)
			trace(this + " free " + formatSize(page.size));
	}

	private function allocPage(minSize:Int):MemoryPage {
		var size = policy.getNewPageSize(pages, minSize);
		if(minSize > size)
			size = minSize;
		if(size <= 0)
			throw "assert";
		if(mem.alignment != 1) {
			var difference = size % mem.alignment;
			if(difference != 0)
				size += mem.alignment - difference;
		}
		var page = mem.alloc(size);
		if(page == null) {
			policy.garbageMem();
			page = mem.alloc(size);
		}
		if(page == null)
			throw "Out of memory";
		pages.push(page);
		if(debug)
			trace(this + " alloc-page " + formatSize(page.size));
		return page;
	}

	public function alloc(size:Int, ?out:MemoryBlock, alignment = 1) {
		if(size <= 0 || alignment <= 0)
			throw "Invalid allocation size or alignment";
		if(useMemoryPool) {
			if(out != null)
				throw "assert";
			out = pool.pop();
			if(out == null)
				out = new MemoryBlock();
		} else if(out == null)
			out = tmp;
		if(alignment < mem.alignment)
			alignment = mem.alignment;
		if(alignment != 1) {
			var difference = size % alignment;
			if(difference != 0)
				size += alignment - difference;
		}
		out.page = null;
		out.size = size;
		var position = tryAlloc(size, alignment, out);
		if(position < 0) {
			allocPage(size);
			position = tryAlloc(size, alignment, out);
			if(position < 0)
				throw "assert";
		}
		out.offset = position * mem.stride;
		allocCounter++;
		if(debug) {
			frequentLog(() -> {
				trace(this + " " + allocCounter + " allocs");
				allocCounter = 0;
			});
		}
		return out;
	}

	private inline function frequentLog(callback:Void->Void) {
		var time = haxe.Timer.stamp();
		if(time - lastLogTime > MAX_DEBUG_FREQ) {
			lastLogTime = time;
			callback();
		}
	}

	public abstract function free(memory:MemoryBlock):Void;
	private abstract function tryAlloc(size:Int, alignment:Int, out:MemoryBlock):Int;
	public abstract function getUsedSize():Float;
}
#end
