package h3d.impl.driver.dx11;

#if (limen && gfx_dx11)
import limen.graphics.d3d11.DX11Core.Resource;
import limen.graphics.d3d11.DX11Resources.ShaderResourceView;
import limen.graphics.d3d11.DX11States.SamplerState;

class PipelineState {
	public var kind : PipelineKind;
	public var samplers = new hl.NativeArray<SamplerState>(64);
	public var samplerBits = new Array<Int>();
	public var resources = new hl.NativeArray<ShaderResourceView>(64);
	public var buffers = new hl.NativeArray<Resource>(16);

	public function new(kind) {
		this.kind = kind;
		for(i in 0...64)
			samplerBits[i] = -1;
	}
}
#end
