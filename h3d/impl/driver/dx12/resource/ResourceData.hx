package h3d.impl.driver.dx12.resource;

#if ((hldx && gfx_dx12) || (hlsdl && gfx_dx12))
import dx.Dx12;

class ResourceData {
	public var res : GpuResource;
	public var state : ResourceState;
	public var targetState : ResourceState;

	public function new() {
	}
}
#end
