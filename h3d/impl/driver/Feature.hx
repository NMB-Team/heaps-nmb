package h3d.impl.driver;

enum Feature {
	/*
		Do the shaders support standard derivative functions (ddx and ddy).
	*/
	StandardDerivatives;
	/*
		Can allocate floating-point textures.
	*/
	FloatTextures;
	/*
		Can allocate custom depth buffers.
	*/
	AllocDepthBuffer;
	/*
		Is the driver hardware accelerated or CPU emulated.
	*/
	HardwareAccelerated;
	/*
		Allows rendering to several targets with a single draw.
	*/
	MultipleRenderTargets;
	/*
		Supports query objects.
	*/
	Queries;
	/*
		Supports gamma-correct textures.
	*/
	SRGBTextures;
	/*
		Allows advanced shader operations.
	*/
	ShaderModel3;
	/*
		Uses bottom-left coordinates for textures.
	*/
	BottomLeftCoords;
	/*
		Supports wireframe rendering.
	*/
	Wireframe;
	/*
		Supports instanced rendering.
	*/
	InstancedRendering;
	/*
		Supports bindless resources.
	*/
	Bindless;
	/*
		Supports DLSS.
	*/
	DLSS;
	/*
		Can render into a single layer of a depth texture array.
	*/
	DepthTextureArray;
	/*
		Supports compute shaders and read/write storage buffers.
	*/
	ComputeShaders;
	/*
		Sampler arrays can be indexed by a non-constant, dynamically uniform expression.
	*/
	DynamicSamplerIndex;
}
