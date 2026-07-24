package h3d.impl.allocator;

#if hl
abstract class AllocatorPolicy {
	public abstract function getNewPageSize(pages:Array<MemoryPage>, requestedSize:Int):Int;

	public dynamic function garbageMem():Void {
		throw "Out of memory";
	}
}
#end
