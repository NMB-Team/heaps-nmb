package h3d.impl.driver.dx12.query;

#if ((hldx && gfx_dx12) || (hlsdl && gfx_dx12))
class QueryData {
	public var heap : Int;
	public var offset : Int;
	public var result : Float;

	public function new() {
	}
}
#end
