package h3d.impl.driver.dlss;

@:struct
class DLSSParams {
	public var cameraViewToClip : h3d.Matrix;
	public var clipToCameraView : h3d.Matrix;
	public var clipToPrevClip : h3d.Matrix;
	public var prevClipToClip : h3d.Matrix;
	public var jitterOffsetX : Float;
	public var jitterOffsetY : Float;
	public var mvecScaleX : Float;
	public var mvecScaleY : Float;
	public var cameraPos : h3d.Vector;
	public var cameraUp : h3d.Vector;
	public var cameraRight : h3d.Vector;
	public var cameraFwd : h3d.Vector;
	public var cameraNear : Float;
	public var cameraFar : Float;
	public var cameraFOV : Float;
	public var cameraAspectRatio : Float;
	public var motionVectorsInvalidValue : Float;
	public var depthInverted : Bool;
	public var cameraMotionIncluded : Bool;
	public var reset : Bool;
	public var orthographicProjection : Bool;
	public var motionVectorsDilated : Bool;
	public var motionVectorsJittered : Bool;
	public var colorBufferHDR : Bool;
	public var autoExposure : Bool;

	public function new() {
	}
}
