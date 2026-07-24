package h3d.impl.driver.opengl;

#if ((js||hlsdl||usegl) && !(hlsdl && gfx_vulkan && !gfx_opengl))
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
