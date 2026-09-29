package h3d.impl.driver.dx12.readback;

#if (limen && gfx_dx12)
import limen.graphics.renderer.d3d12.resource.Resources.ResourceBarrier;

import h3d.Buffer;
import haxe.Int64;

class AsyncReadbackRequest {
	public var b : Buffer;
	public var startVertex : Int;
	public var vertexCount : Int;
	public var buf : haxe.io.Bytes;
	public var bufPos : Int;
	public var callback : Void -> Void;
	public var tmpBufOffset : Int;
	public var tmpBufSize : Int;
	public var barrier : ResourceBarrier;
	public var fenceValue : Int64;

	public function new() {
	}
}
#end
