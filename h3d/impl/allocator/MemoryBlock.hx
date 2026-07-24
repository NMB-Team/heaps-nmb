package h3d.impl.allocator;

#if hl
class MemoryBlock {
	public var cpuAddress(get,never) : hl.Bytes;
	public var gpuAddress(get,never) : haxe.Int64;
	public var page : MemoryPage;
	public var size : Int;
	public var offset : Int;

	public function new() {
	}

	@:noCompletion
	private inline function get_cpuAddress() {
		return page.cpuAddress.offset(offset);
	}

	@:noCompletion
	private inline function get_gpuAddress() {
		return page.gpuAddress + offset;
	}
}
#end
