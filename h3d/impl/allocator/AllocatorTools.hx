package h3d.impl.allocator;

#if hl
@:noCompletion
final class AllocatorTools {
	public static inline function align(value:Int, alignment:Int) {
		var remainder = value % alignment;
		return remainder == 0 ? value : value + alignment - remainder;
	}
}
#end
