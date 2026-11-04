package h3d.impl.driver.dx12.descriptor;

#if (limen && gfx_dx12)
import limen.graphics.renderer.d3d12.descriptor.DescriptorHeap.DescriptorHeapType;

class ScratchHeapArray {
	#if dx12_descriptor_profile
	public var growths = 0;
	public var resets = 0;
	public var resetSeconds = 0.;
	#end
	var heaps : Array<ScratchHeap>;
	var type : DescriptorHeapType;
	var size : Int;
	var cursor : Int;

	public function new(type,size) {
		this.type = type;
		this.size = size;
		heaps = [];
	}

	public function reset() {
		#if dx12_descriptor_profile
		var started = haxe.Timer.stamp();
		#end
		cursor = 0;
		#if dx12_descriptor_profile
		resets++;
		resetSeconds += haxe.Timer.stamp() - started;
		#end
	}

	public function checkSize(minSize:Int, toRelease:Array<limen.graphics.renderer.d3d12.resource.Resources.Dx12Resource>) {
		if(minSize <= size) return;
		if(type == SAMPLER && minSize > 2048)
			throw 'Shader-visible sampler heap exhausted (requested=$minSize, limit=2048)';
		#if dx12_descriptor_profile
		growths++;
		#end
		size = hxd.Math.imax(minSize, (size * 3) >> 1);
		if(type == SAMPLER)
			size = hxd.Math.imin(size, 2048);
		for(h in heaps) toRelease.push(@:privateAccess h.heap);
		heaps = [];
		cursor = 0;
	}

	public function next() {
		var h = heaps[cursor++];
		if(h == null) {
			h = new ScratchHeap(type, size);
			heaps.push(h);
		} else
			h.clear();
		return h;
	}

	public function getSize() {
		var size : Float = 0;
		for(h in heaps)
			size += h.getSize();
		return size;
	}
}
#end
