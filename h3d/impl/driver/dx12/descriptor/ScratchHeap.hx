package h3d.impl.driver.dx12.descriptor;

#if (limen && gfx_dx12)
import limen.d3d12.descriptor.DescriptorHeap.DescriptorHeapType;

class ScratchHeap extends DescriptorHeapBase {
	var cursor : Int;
	public var available(get,never) : Int;

	override function allocHeap(size:Int) {
		var limit = DescriptorHeapBase.shaderVisibleCapacity(type);
		if(shaderVisible && size > limit)
			throw new h3d.impl.DescriptorAllocationError('Shader-visible descriptor heap exhausted (type=$type, requested=$size, limit=$limit)', true);

		super.allocHeap(size);
		cursor = 0;
	}

	public function alloc(count:Int) {
		#if dx12_descriptor_profile
		var started = haxe.Timer.stamp();
		#end
		if(cursor + count > size) {
			if( shaderVisible )
				throw new h3d.impl.DescriptorAllocationError('D3D12 shader-visible descriptor heap exhausted (type=$type, capacity=$size)', true);
			var prevCursor = cursor;
			// onFree may preserve the old descriptors and restore the cursor.
			var nextSize = hxd.Math.imax(getNextHeapSize(), cursor + count);
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
