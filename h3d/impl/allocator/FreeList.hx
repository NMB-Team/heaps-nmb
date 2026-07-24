package h3d.impl.allocator;

#if hl
@:noCompletion
class FreeList {
	private var list : Array<Int>;
	private var count : Int;

	public function new(size:Int) {
		list = [size, 0];
		count = 1;
	}

	public function alloc(size:Int, alignment:Int, bestFit:Bool):Int {
		var best = -1;
		var bestLength = -1;
		var bestPosition = -1;
		var bestWaste = -1;
		for(index in 0...count) {
			var length = list[index << 1];
			var position = list[(index << 1) + 1];
			var alignedPosition = AllocatorTools.align(position, alignment);
			var required = alignedPosition - position + size;
			var waste = length - required;
			if(waste >= 0 && (best < 0 || waste < bestWaste)) {
				best = index;
				bestLength = length;
				bestPosition = alignedPosition;
				bestWaste = waste;
				if(!bestFit || required == length)
					break;
			}
		}
		if(best < 0)
			return -1;
		var offset = best << 1;
		var position = list[offset + 1];
		var prefix = bestPosition - position;
		var suffix = bestLength - prefix - size;
		if(prefix == 0 && suffix == 0)
			merge(offset);
		else if(prefix == 0) {
			list[offset] = suffix;
			list[offset + 1] = bestPosition + size;
		} else {
			list[offset] = prefix;
			if(suffix > 0)
				insert(offset + 2, suffix, bestPosition + size);
		}
		return bestPosition;
	}

	private inline function merge(offset:Int) {
		count--;
		blit(offset, offset + 2, (count << 1) - offset);
	}

	private inline function insert(offset:Int, size:Int, position:Int) {
		var max = count << 1;
		if(max == list.length) {
			list.push(0);
			list.push(0);
		}
		blit(offset + 2, offset, max - offset);
		list[offset] = size;
		list[offset + 1] = position;
		count++;
	}

	public function free(position:Int, size:Int) {
		if(size == 0)
			return;
		if(position < 0 || size < 0)
			throw "assert";

		var offset = 0;
		var max = count << 1;
		while(offset < max && list[offset + 1] < position)
			offset += 2;

		if(offset > 0) {
			var previousPosition = list[offset - 1];
			var previousLength = list[offset - 2];
			if(previousPosition + previousLength == position) {
				previousLength += size;
				list[offset - 2] = previousLength;
				if(offset < max) {
					var nextPosition = list[offset + 1];
					if(nextPosition == previousPosition + previousLength) {
						previousLength += list[offset];
						list[offset - 2] = previousLength;
						merge(offset);
					}
				}
				return;
			}
		}

		if(offset < max) {
			var nextPosition = list[offset + 1];
			if(position + size == nextPosition) {
				var nextLength = list[offset] + size;
				list[offset] = nextLength;
				list[offset + 1] = position;
				return;
			}
		}

		insert(offset, size, position);
	}

	public function getFreeSize() {
		var total = 0;
		for(index in 0...count)
			total += list[index << 1];
		return total;
	}

	public inline function isFullyFree(size:Int) {
		return count == 1 && list[0] == size && list[1] == 0;
	}

	public function toString() {
		return Std.string([for(index in 0...count) list[(index << 1) + 1] + ":" + list[index << 1]]);
	}

	private inline function blit(destination:Int, source:Int, size:Int) {
		#if hl
		var bytes = hl.Bytes.getArray(list);
		bytes.blit(destination << 2, bytes, source << 2, size << 2);
		#else
		if(destination < source) {
			for(index in 0...size)
				list[destination + index] = list[source + index];
		} else {
			var index = size - 1;
			while(index >= 0) {
				list[destination + index] = list[source + index];
				index--;
			}
		}
		#end
	}
}
#end
