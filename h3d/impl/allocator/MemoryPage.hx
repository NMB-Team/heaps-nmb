package h3d.impl.allocator;

#if hl
class MemoryPage {
	public var cpuAddress : hl.Bytes;
	public var gpuAddress : haxe.Int64;
	public var size : Int;
	public var ref : Dynamic;

	public function new(cpu:hl.Bytes, gpu:haxe.Int64, size:Int, ref:Dynamic) {
		this.cpuAddress = cpu;
		this.gpuAddress = gpu;
		this.size = size;
		this.ref = ref;
	}
}
#end
