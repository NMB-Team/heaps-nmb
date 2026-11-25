package h3d;

#if (hl && limen)
/**
	Reusable indexed triangle ranges sharing one vertex and index buffer pair.
	Encode and submit on the rendering thread. Each submission uses the active
	material and target. Create a new batch if either buffer backing is replaced.
**/
@:access(h3d.Buffer)
@:allow(h3d.Engine)
class IndexedDrawBatch {
	final vertex:Buffer;
	final index:Buffer;
	final vertexGeneration:hl.NativeArray<Int>;
	final indexGeneration:hl.NativeArray<Int>;
	final words:hl.NativeArray<Int>;
	final capacity:Int;
	var triangles:Float = 0;
	public var count(default, null) = 0;

	public function new(vertex:Buffer, indexes:Indexes, capacity:Int) {
		final index:Buffer = indexes;
		if( vertex.vbuf == null || index.vbuf == null || vertex.engine != index.engine ||
			vertex.flags.has(IndexBuffer) || !index.flags.has(IndexBuffer) )
			throw "Indexed draw batch requires live vertex and index buffers from the same engine";
		// leave room for hashlink array headers and allocator alignment
		if( capacity < 1 || capacity > ((0x7FFE0000 - 4) >> 3) )
			throw "Invalid indexed draw batch capacity";

		this.vertex = vertex;
		this.index = index;
		if( vertex.indexedDrawGeneration == null )
			vertex.indexedDrawGeneration = new hl.NativeArray<Int>(1);
		if( index.indexedDrawGeneration == null )
			index.indexedDrawGeneration = new hl.NativeArray<Int>(1);
		vertexGeneration = vertex.indexedDrawGeneration;
		indexGeneration = index.indexedDrawGeneration;
		this.capacity = capacity;
		words = new hl.NativeArray<Int>(1 + capacity * 2);
		words[0] = 2;
	}

	public inline function clear() {
		count = 0;
		triangles = 0;
	}

	public function add(firstTriangle:Int, triangleCount:Int) {
		final limit = Std.int(index.vertices / 3);
		if( firstTriangle < 0 || firstTriangle > limit || triangleCount <= 0 || triangleCount > limit - firstTriangle )
			throw "Invalid indexed draw range";
		if( count == capacity )
			throw "Indexed draw batch is full";

		final position = 1 + count * 2;
		words[position] = firstTriangle * 3;
		words[position + 1] = triangleCount * 3;
		triangles += triangleCount;
		count++;
	}

	inline function requireBacking(engine:Engine) {
		if( vertex.engine != engine || vertex.indexedDrawGeneration != vertexGeneration || index.indexedDrawGeneration != indexGeneration )
			throw "Indexed draw batch has stale or foreign buffers";
	}
}
#end
