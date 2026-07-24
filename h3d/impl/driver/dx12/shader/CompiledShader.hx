package h3d.impl.driver.dx12.shader;

#if ((hldx && gfx_dx12) || (hlsdl && gfx_dx12))
import dx.Dx12;
import h3d.impl.PipelineCache;

class CompiledShader {
	public var vertexRegisters : ShaderRegisters;
	public var fragmentRegisters : ShaderRegisters;
	public var format : hxd.BufferFormat;
	public var pipeline : GraphicsPipelineStateDesc;
	public var pipelines : PipelineCache<GraphicsPipelineState> = new PipelineCache();
	public var rootSignature : RootSignature;
	public var inputLayout : hl.CArray<InputElementDesc>;
	public var inputCount : Int;
	public var shader : hxsl.RuntimeShader;
	public var isCompute : Bool;
	public var computePipeline : ComputePipelineState;

	public function new() {
	}
}
#end
