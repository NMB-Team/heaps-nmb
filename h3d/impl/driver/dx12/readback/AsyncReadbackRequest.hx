package h3d.impl.driver.dx12.readback;

#if ((hldx && gfx_dx12) || (hlsdl && gfx_dx12))
import dx.Dx12.ResourceBarrier;
import h3d.Buffer;

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
	public var frame : Int;

	public function new() {
	}
}
#end
