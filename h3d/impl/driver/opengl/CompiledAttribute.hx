package h3d.impl.driver.opengl;

#if (js || usegl || (limen && (gfx_opengl || (!gfx_dx11 && !gfx_dx12 && !gfx_vulkan))))
@:noCompletion
class CompiledAttribute {
	public var index : Int;
	public var type : Int;
	public var size : Int;
	public var divisor : Int;

	public function new() {
	}
}
#end
