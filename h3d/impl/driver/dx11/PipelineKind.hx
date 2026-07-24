package h3d.impl.driver.dx11;

#if ((hldx && !gfx_dx12) || (hlsdl && gfx_dx11))
enum PipelineKind {
	Vertex;
	Pixel;
}
#end
