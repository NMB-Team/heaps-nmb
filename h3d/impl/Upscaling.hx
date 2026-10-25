package h3d.impl;

import h3d.impl.driver.Driver;


enum UpscalingFeature {
	Upscaler;
	FrameGen;
	LowLatency;
}

enum abstract UpscalingProvider(String) from String to String {
	var AUTO = "auto";
	var DLSS = "dlss";
	var FSR = "fsr";
}

enum UpscalingMode {
	Off;
	NativeAA;
	Quality;
	Balanced;
	Performance;
	UltraPerformance;
}

enum FrameGenMode {
	Off;
	On;
	Auto;
	Dynamic;
}

enum FrameGenUIMode {
	BackBuffer;
	HudLess;
	UITexture;
}

enum LowLatencyMode {
	Off;
	On;
	OnWithBoost;
}

enum LatencyMarker {
	SimulationStart;
	SimulationEnd;
	TriggerFlash;
}

class UpscalingInputs {
	public var color : h3d.mat.Texture;
	public var depth : h3d.mat.Texture;
	public var motionVectors : h3d.mat.Texture;
	public var output : h3d.mat.Texture;
	public function new() {
	}
}

@:struct class UpscalingParams {
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

class UpscalingSettings {
	public var renderWidth : Int;
	public var renderHeight : Int;
	public function new() {
	}
}

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

@:allow(h3d.impl.Upscaling)
class UpscalingBackend {

	public var provider(default, null) : UpscalingProvider;
	public var wanted(default, null) : haxe.EnumFlags<UpscalingFeature>;
	public var supported(default, null) : haxe.EnumFlags<UpscalingFeature>;

	public function new( provider : UpscalingProvider ) {
		this.provider = provider;
	}

	public function beforeCreateDevice() {
	}

	public function afterCreateDevice() {
	}

	public function release( unused : haxe.EnumFlags<UpscalingFeature> ) {
	}

	public function afterCreateQueue() {
	}

	public function afterCreateSwapChain() {
	}

	public function beginFrame() {
	}

	public function begin() {
	}

	public function beforePresent() {
	}

	public function beforeQueuePresent() {
	}

	public function afterQueuePresent() {
	}

	public function beforeResize() {
	}

	public function releaseResizeResources() {
	}

	public function afterResize() {
	}

	public function dispose() {
	}

	public function isAvailable( f : UpscalingFeature ) : Bool {
		return supported.has(f);
	}

	public function getName( f : UpscalingFeature ) : String {
		return (provider : String).toUpperCase();
	}

	public function getStatus( f : UpscalingFeature ) : String {
		return wanted.has(f) ? "not supported" : "not selected";
	}

	public function debug( f : UpscalingFeature ) : String {
		return "";
	}

	public function getRenderSize( mode : UpscalingMode, targetWidth : Int, targetHeight : Int ) : UpscalingSettings {
		return null;
	}

	public function upscale( inputs : UpscalingInputs, params : UpscalingParams, mode : UpscalingMode ) {
	}

	public function releaseUpscaler() {
	}

	public function setFrameGenMode( mode : FrameGenMode, numFramesToGenerate : Int, releaseResources : Bool ) : Bool {
		return false;
	}

	public function getFrameGenMode() : FrameGenMode {
		return Off;
	}

	public function getFrameGenSettings() : FrameGenSettings {
		return null;
	}

	public function prepareFrameGen( inputs : UpscalingInputs, params : UpscalingParams ) {
	}

	public function setFrameGenUI( hudless : h3d.mat.Texture, ui : h3d.mat.Texture ) {
	}

	public function composesFrameGenUI() : Bool {
		return false;
	}

	public function getHudlessBufferCount() : Int {
		return 1;
	}

	public function setLowLatencyMode( mode : LowLatencyMode, frameLimitUs : Int ) : Bool {
		return false;
	}

	public function lowLatencySleep() {
	}

	public function latencyMarker( m : LatencyMarker ) {
	}

	public function isFlashIndicatorDriverControlled() : Bool {
		return false;
	}
}

class Upscaling {

	public static var ENABLED = true;
	public static var UPSCALER : UpscalingProvider = AUTO;
	public static var FRAME_GEN = true;
	public static var FRAME_GEN_PROVIDER : UpscalingProvider = AUTO;
	public static var LOW_LATENCY = true;
	public static var DEBUG = false;
	public static var PRIORITY : Array<UpscalingProvider> = [DLSS, FSR];

	var driver : Driver;
	var backends : Array<UpscalingBackend>;
	var upscaler : UpscalingBackend;
	var frameGen : UpscalingBackend;
	var latency : UpscalingBackend;
	var pendingRelease : Array<UpscalingBackend> = [];
	var resetHistory = false;
	var lowLatencyMode : LowLatencyMode = Off;
	var frameLimitUs = 0;
	var presentCount = 0;

	var lastInputs = new UpscalingInputs();
	var lastFrame = -1;
	var lastMode : UpscalingMode = Off;

	var frameGenUIMode : FrameGenUIMode = BackBuffer;
	var hudlessTextures : Array<h3d.mat.Texture> = [];
	var hudlessCaptured = -1;
	var frameGenUITarget : h3d.mat.Texture;
	var frameGenUIDrawn = -1;

	public function new( driver : Driver, backends : Array<UpscalingBackend> ) {
		this.driver = driver;
		this.backends = backends;
	}

	public function isSupported( f : UpscalingFeature ) : Bool {
		var b = getBackend(f);
		return b != null && b.isAvailable(f);
	}

	public function getName( f : UpscalingFeature ) : String {
		var b = getBackend(f);
		return b == null ? null : b.getName(f);
	}

	public function getUpscalers() : Array<UpscalingProvider> {
		return [for( b in backends ) if( b.supported.has(Upscaler) ) b.provider];
	}

	public function getUpscaler() : UpscalingProvider {
		return upscaler == null ? null : upscaler.provider;
	}

	public function setUpscaler( provider : UpscalingProvider ) : Bool {
		for( b in backends ) {
			if( b.provider != provider || !b.supported.has(Upscaler) )
				continue;
			if( b != upscaler ) {
				pendingRelease.remove(b);
				if( upscaler != null && !pendingRelease.contains(upscaler) )
					pendingRelease.push(upscaler);
				upscaler = b;
				resetHistory = true;
			}
			return true;
		}
		return false;
	}

	public function getRenderSize( mode : UpscalingMode, targetWidth : Int, targetHeight : Int ) : UpscalingSettings {
		return upscaler == null ? null : upscaler.getRenderSize(mode, targetWidth, targetHeight);
	}

	public function upscale( inputs : UpscalingInputs, params : UpscalingParams, mode : UpscalingMode ) {
		if( upscaler == null )
			return;
		if( resetHistory ) {
			params.reset = true;
			resetHistory = false;
		}
		lastFrame = hxd.Timer.frameCount;
		lastMode = mode;
		lastInputs.color = inputs.color;
		lastInputs.depth = inputs.depth;
		lastInputs.motionVectors = inputs.motionVectors;
		lastInputs.output = inputs.output;
		upscaler.upscale(inputs, params, mode);
	}

	public function setFrameGenMode( mode : FrameGenMode, numFramesToGenerate = 1, releaseResources = false ) : Bool {
		if( frameGen == null )
			return false;
		if( mode != Off && latency != null && lowLatencyMode == Off )
			latency.setLowLatencyMode(On, frameLimitUs);
		return frameGen.setFrameGenMode(mode, numFramesToGenerate, releaseResources);
	}

	public function getFrameGenMode() : FrameGenMode {
		return frameGen == null ? Off : frameGen.getFrameGenMode();
	}

	public function getFrameGenSettings() : FrameGenSettings {
		return frameGen == null ? null : frameGen.getFrameGenSettings();
	}

	public function prepareFrameGen( inputs : UpscalingInputs, params : UpscalingParams ) {
		if( frameGen != null )
			frameGen.prepareFrameGen(inputs, params);
	}

	public function setFrameGenUIMode( mode : FrameGenUIMode ) {
		if( mode == frameGenUIMode )
			return;
		frameGenUIMode = mode;
		disposeFrameGenTextures();
	}

	public function getFrameGenUIMode() : FrameGenUIMode {
		return frameGenUIMode;
	}

	public function markFrameGenHudless( ?source : h3d.mat.Texture ) {
		var hudless = getHudlessTexture();
		if( hudless == null )
			return;
		if( source == null )
			driver.copyBackBuffer(hudless);
		else if( !driver.copyTexture(source, hudless) )
			h3d.pass.Copy.run(source, hudless);
		hudlessCaptured = presentCount;
	}

	public function getFrameGenUITarget() : h3d.mat.Texture {
		if( frameGenUIMode != UITexture )
			return null;
		var engine = h3d.Engine.getCurrent();
		var t = frameGenUITarget;
		if( t == null || t.isDisposed() || t.width != engine.width || t.height != engine.height ) {
			if( t != null )
				t.dispose();
			t = new h3d.mat.Texture(engine.width, engine.height, [Target], RGBA);
			t.setName("frameGenUI");
			t.preventAutoDispose();
			frameGenUITarget = t;
		}
		return t;
	}

	public function compositeFrameGenUI() {
		var ui = frameGenUITarget;
		if( ui == null || ui.t == null || frameGenUIMode != UITexture )
			return;
		frameGenUIDrawn = presentCount;
		if( frameGen != null && frameGen.composesFrameGenUI() )
			return;
		markFrameGenHudless();
		h3d.pass.Copy.run(ui, null, AlphaAdd);
	}

	public function setLowLatencyMode( mode : LowLatencyMode, frameLimitUs = 0 ) : Bool {
		lowLatencyMode = mode;
		this.frameLimitUs = frameLimitUs;
		if( latency == null )
			return false;
		if( mode == Off && getFrameGenMode() != Off )
			mode = On;
		return latency.setLowLatencyMode(mode, frameLimitUs);
	}

	public function getLowLatencyMode() : LowLatencyMode {
		return lowLatencyMode;
	}

	public function lowLatencySleep() {
		if( latency != null )
			latency.lowLatencySleep();
	}

	public function latencyMarker( m : LatencyMarker ) {
		if( latency != null )
			latency.latencyMarker(m);
	}

	public function isFlashIndicatorDriverControlled() : Bool {
		return latency != null && latency.isFlashIndicatorDriverControlled();
	}

	public function debug( f : UpscalingFeature ) : String {
		var buf = new StringBuf();
		buf.add(switch( f ) {
			case Upscaler: "=== Upscaling Debug ===\n";
			case FrameGen: "=== Frame Generation Debug ===\n";
			case LowLatency: "=== Low Latency Debug ===\n";
		});
		if( !ENABLED ) {
			buf.add("Upscaling is disabled (Upscaling.ENABLED = false)\n");
			return buf.toString();
		}
		if( f == FrameGen && !FRAME_GEN ) {
			buf.add("Frame generation is disabled (Upscaling.FRAME_GEN = false)\n");
			return buf.toString();
		}
		var b = getBackend(f);
		if( b == null ) {
			buf.add('No provider (UPSCALER = $UPSCALER, FRAME_GEN_PROVIDER = $FRAME_GEN_PROVIDER, LOW_LATENCY = $LOW_LATENCY)\n');
			if( backends.length == 0 )
				buf.add("No backend for this driver\n");
			for( b in backends )
				buf.add('${b.getName(f)}: ${b.getStatus(f)}\n');
			return buf.toString();
		}
		buf.add('provider=${b.getName(f)} upscaler=${getName(Upscaler)} frameGen=${getName(FrameGen)} lowLatency=${getName(LowLatency)}\n');
		if( f == Upscaler )
			debugUpscaler(buf);
		else
			buf.add(b.debug(f));
		return buf.toString();
	}

	function debugUpscaler( buf : StringBuf ) {
		buf.add('mode=$lastMode available=${getUpscalers()}\n');
		var input = lastInputs.color;
		var output = lastInputs.output;
		if( lastFrame < 0 || input == null || output == null ) {
			buf.add("Upscaling was never applied\n");
			return;
		}
		buf.add('render=${input.width}x${input.height} output=${output.width}x${output.height}\n');
		var issues = [];
		var age = hxd.Timer.frameCount - lastFrame;
		if( age > 1 )
			issues.push('not applied for $age frames');
		function checkInput( t : h3d.mat.Texture, name : String ) {
			if( t == null )
				issues.push('missing $name');
			else if( t.width != input.width || t.height != input.height )
				issues.push('$name is ${t.width}x${t.height}');
		}
		checkInput(lastInputs.depth, "depth");
		checkInput(lastInputs.motionVectors, "motion vectors");
		if( lastMode != Off && lastMode != NativeAA ) {
			var optimal = getRenderSize(lastMode, output.width, output.height);
			if( optimal != null && (optimal.renderWidth != input.width || optimal.renderHeight != input.height) )
				issues.push('render size differs from optimal ${optimal.renderWidth}x${optimal.renderHeight}');
		} else if( input.width != output.width || input.height != output.height )
			issues.push("render size differs from output size");
		for( issue in issues )
			buf.add('status: $issue\n');
		var details = upscaler.debug(Upscaler);
		buf.add(details);
		if( issues.length == 0 && details.indexOf("status:") < 0 )
			buf.add("status=Ok\n");
	}

	public function beforeCreateDevice() {
		upscaler = null;
		frameGen = null;
		latency = null;
		pendingRelease = [];
		for( b in backends ) {
			b.wanted = getWanted(b);
			b.supported = new haxe.EnumFlags();
			b.beforeCreateDevice();
		}
	}

	public function afterCreateDevice() {
		for( b in backends )
			b.afterCreateDevice();
		frameGen = getPreferred(FrameGen);
		latency = frameGen != null && frameGen.supported.has(LowLatency) ? frameGen : getPreferred(LowLatency);
		for( b in backends ) {
			var unused = new haxe.EnumFlags<UpscalingFeature>();
			if( b != frameGen && b.supported.has(FrameGen) )
				unused.set(FrameGen);
			if( b != latency && b.supported.has(LowLatency) )
				unused.set(LowLatency);
			if( unused.toInt() == 0 )
				continue;
			b.release(unused);
			b.supported = new haxe.EnumFlags(b.supported.toInt() & ~unused.toInt());
		}
		refresh();
	}

	public function afterCreateQueue() {
		for( b in backends )
			b.afterCreateQueue();
		refresh();
	}

	public function afterCreateSwapChain() {
		for( b in backends )
			b.afterCreateSwapChain();
		refresh();
	}

	public function beginFrame() {
		while( pendingRelease.length > 0 )
			pendingRelease.pop().releaseUpscaler();
		for( b in backends )
			b.beginFrame();
	}

	public function begin() {
		for( b in backends )
			b.begin();
	}

	public function beforePresent() {
		for( b in backends )
			b.beforePresent();
		prepareFrameGenUI();
	}

	public function beforeQueuePresent() {
		for( b in backends )
			b.beforeQueuePresent();
	}

	public function afterQueuePresent() {
		presentCount++;
		for( b in backends )
			b.afterQueuePresent();
	}

	public function beforeResize() {
		for( b in backends )
			b.beforeResize();
	}

	public function releaseResizeResources() {
		for( b in backends )
			b.releaseResizeResources();
		disposeFrameGenTextures();
	}

	public function afterResize() {
		for( b in backends )
			b.afterResize();
	}

	public function dispose() {
		disposeFrameGenTextures();
		var i = backends.length;
		while( i-- > 0 )
			backends[i].dispose();
		upscaler = null;
		frameGen = null;
		latency = null;
		pendingRelease = [];
	}

	function getWanted( b : UpscalingBackend ) {
		var f = new haxe.EnumFlags<UpscalingFeature>();
		if( !ENABLED )
			return f;
		if( UPSCALER == AUTO || UPSCALER == b.provider )
			f.set(Upscaler);
		if( FRAME_GEN && (FRAME_GEN_PROVIDER == AUTO || FRAME_GEN_PROVIDER == b.provider) )
			f.set(FrameGen);
		if( LOW_LATENCY )
			f.set(LowLatency);
		return f;
	}

	function getPreferred( f : UpscalingFeature ) {
		for( p in PRIORITY )
			for( b in backends )
				if( b.provider == p && b.supported.has(f) )
					return b;
		for( b in backends )
			if( b.supported.has(f) )
				return b;
		return null;
	}

	function getBackend( f : UpscalingFeature ) {
		return switch( f ) {
			case Upscaler: upscaler;
			case FrameGen: frameGen;
			case LowLatency: latency;
		}
	}

	function refresh() {
		if( upscaler == null || !upscaler.supported.has(Upscaler) )
			upscaler = getPreferred(Upscaler);
		if( frameGen != null && !frameGen.supported.has(FrameGen) )
			frameGen = null;
		if( latency != null && !latency.supported.has(LowLatency) )
			latency = null;
	}

	@:allow(h3d.impl)
	function getHudlessTexture() : h3d.mat.Texture {
		if( getFrameGenMode() == Off )
			return null;
		switch( frameGenUIMode ) {
		case HudLess:
		case UITexture if( !frameGen.composesFrameGenUI() ):
		default: return null;
		}
		var engine = h3d.Engine.getCurrent();
		var index = presentCount % frameGen.getHudlessBufferCount();
		var t = hudlessTextures[index];
		if( t == null || t.isDisposed() || t.width != engine.width || t.height != engine.height ) {
			if( t != null )
				t.dispose();
			t = new h3d.mat.Texture(engine.width, engine.height, [Target], RGBA);
			t.setName('frameGenHudless$index');
			t.preventAutoDispose();
			hudlessTextures[index] = t;
		}
		if( t.t == null )
			t.alloc();
		return t;
	}

	function prepareFrameGenUI() {
		if( frameGen == null || frameGenUIMode == BackBuffer )
			return;
		var hudless = getHudlessTexture();
		if( hudless != null && hudlessCaptured != presentCount )
			driver.copyBackBuffer(hudless);
		var ui = frameGenUIMode == UITexture && frameGenUIDrawn == presentCount ? frameGenUITarget : null;
		frameGen.setFrameGenUI(hudless, ui);
	}

	function disposeFrameGenTextures() {
		if( frameGen != null )
			frameGen.setFrameGenUI(null, null);
		for( t in hudlessTextures )
			if( t != null )
				t.dispose();
		hudlessTextures = [];
		hudlessCaptured = -1;
		if( frameGenUITarget != null ) {
			frameGenUITarget.dispose();
			frameGenUITarget = null;
		}
		frameGenUIDrawn = -1;
	}
}
