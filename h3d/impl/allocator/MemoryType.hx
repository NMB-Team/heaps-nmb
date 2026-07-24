package h3d.impl.allocator;

#if hl
abstract class MemoryType {
	public var stride : Int = 1;
	public var alignment : Int = 1;

	abstract public function alloc(size:Int):MemoryPage;
	abstract public function free(memory:MemoryPage):Void;
}
#end
