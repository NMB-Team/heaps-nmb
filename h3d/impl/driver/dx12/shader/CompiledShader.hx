package h3d.impl.driver.dx12.shader;

#if (limen && gfx_dx12)
import limen.graphics.d3d12.pipeline.InputLayout.InputElementDesc;
import limen.graphics.d3d12.pipeline.Pipeline.ComputePipelineState;
import limen.graphics.d3d12.pipeline.Pipeline.GraphicsPipelineState;
import limen.graphics.d3d12.pipeline.Pipeline.GraphicsPipelineStateDesc;
import limen.graphics.d3d12.pipeline.RootSignature.RootSignature;

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
	public var usedPSOConfig : Bool;

	public function new() {
	}
}
#end
