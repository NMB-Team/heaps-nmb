package h3d.impl.driver.dx11;

#if ((hldx && !gfx_dx12) || (hlsdl && gfx_dx11))
import dx.Driver.SamplerState;

class PipelineState {
	public var kind : PipelineKind;
	public var samplers = new hl.NativeArray<SamplerState>(64);
	public var samplerBits = new Array<Int>();
	public var resources = new hl.NativeArray<dx.Driver.ShaderResourceView>(64);
	public var buffers = new hl.NativeArray<dx.Resource>(16);

	public function new(kind) {
		this.kind = kind;
		for(i in 0...64)
			samplerBits[i] = -1;
	}
}
#end
