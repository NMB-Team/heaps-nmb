package h3d.impl.driver.dx12.descriptor;

#if (limen && gfx_dx12)
import limen.graphics.renderer.d3d12.descriptor.DescriptorHeap.DescriptorHeapType;

class ScratchHeap extends DescriptorHeapBase {
	var cursor : Int;
	public var available(get,never) : Int;

	override function allocHeap(size:Int) {
		if(shaderVisible && type == SAMPLER && size > 2048)
			throw 'Shader-visible sampler heap exhausted (requested=$size, limit=2048)';

		cursor = 0;
		super.allocHeap(size);
	}

	public function alloc(count:Int) {
		#if dx12_descriptor_profile
		var started = haxe.Timer.stamp();
		#end
		if(cursor + count > size) {
			var prevCursor = cursor;
			// onFree may preserve the old descriptors and restore the cursor.
			var nextSize = hxd.Math.imax(getNextHeapSize(), cursor + count);
			if(shaderVisible && type == SAMPLER && cursor + count <= 2048)
				nextSize = hxd.Math.imin(nextSize, 2048);
			var prev = heap;
			allocHeap(nextSize);
			onFree(prev, prevCursor);
		}
		var pos = cursor;
		cursor += count;
		#if dx12_descriptor_profile
		allocations++;
		allocatedDescriptors += count;
		peakUsage = hxd.Math.imax(peakUsage, cursor);
		allocationSeconds += haxe.Timer.stamp() - started;
		#end
		return address.offset(pos * stride);
	}

	inline function get_available() {
		return size - cursor;
	}

	public function clear() {
		#if dx12_descriptor_profile
		var started = haxe.Timer.stamp();
		#end
		cursor = 0;
		#if dx12_descriptor_profile
		resets++;
		resetSeconds += haxe.Timer.stamp() - started;
		#end
	}
}
#end
