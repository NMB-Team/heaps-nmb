package h3d.impl.driver.dx12.resource;

#if (limen && gfx_dx12)
import limen.graphics.renderer.d3d12.resource.Resources.GpuResource;
import limen.graphics.renderer.d3d12.resource.Resources.ResourceState;

class ResourceData {
	public var res : GpuResource;
	public var generation = h3d.impl.driver.dx12.DX12Driver.generation;
	public var lastUseFence : haxe.Int64 = 0;
	public var needsAliasingBarrier = false;
	public var state : ResourceState;
	public var targetState : ResourceState;

	public function new() {
	}
}
#end
