package h3d.impl.driver.upscaling;

class FrameGenSettings {
	public var status : Int;
	public var minWidthOrHeight : Int;
	public var framesPresented : Int;
	public var maxFramesToGenerate : Int;
	public var dynamicSupported : Bool;
	public var vsyncSupported : Bool;

	public function new() {
	}
}
