package hxd;

enum abstract GraphicsDriverApi(String) from String to String {
	final Auto = "auto";
	final Dx11 = "dx11";
	final Dx12 = "dx12";
	final Vulkan = "vulkan";
	final OpenGL = "opengl";
	final Angle = "angle";
}
