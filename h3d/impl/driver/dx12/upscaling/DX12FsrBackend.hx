package h3d.impl.driver.dx12.upscaling;

#if (limen && gfx_dx12 && fsr_allowed && !macro)

import h3d.impl.Upscaling;
import h3d.impl.driver.dx12.DX12Driver;
import limen.graphics.renderer.d3d12.internal.D3D12Bindings;
import limen.graphics.renderer.d3d12.internal.D3D12Bindings.SwapChain;
import limen.graphics.renderer.d3d12.resource.Resources;
import limen.graphics.postprocess.fsr.FSR;
import limen.graphics.postprocess.fsr.FSRContext;
import limen.graphics.postprocess.fsr.FSRDebugLevel;
import limen.graphics.postprocess.fsr.FSRResult;
import limen.graphics.postprocess.fsr.frame.FSRDispatchParams;
import limen.graphics.postprocess.fsr.frame.FSRDispatchFlag;
import limen.graphics.postprocess.fsr.upscaling.FSRCreateFlag;
import limen.graphics.postprocess.fsr.upscaling.FSRQuality;
import limen.graphics.postprocess.fsr.FSREffect;
import limen.graphics.postprocess.fsr.framegen.*;
import limen.graphics.renderer.d3d12.DX12Core.DxgiFormat;

@:access(h3d.impl.driver.dx12.DX12Driver)
@:access(h3d.impl.Upscaling)
class DX12FsrBackend extends UpscalingBackend {

	public static var FRAME_GEN_ASYNC = false;
	public static var FRAME_GEN_DEBUG_FLAGS = 0;
	public static var DEBUG_VIEW = false;

	static inline var FG_STATUS_CONTEXT_FAILED = 1;
	static inline var FG_STATUS_CONFIGURE_FAILED = 2;
	static inline var FG_STATUS_PREPARE_FAILED = 4;
	static inline var FG_STATUS_NOT_PREPARED = 8;

	static var params = new FSRDispatchParams();
	static var fgConfig = new FSRFrameGenConfig();
	static var fgPrepare = new FSRFrameGenPrepareParams();
	static var fgSettings = new FrameGenSettings();

	var driver : DX12Driver;
	var loaded : Bool;
	var initResult = -1;

	var context : FSRContext;
	var contextWidth = -1;
	var contextHeight = -1;
	var contextFlags = -1;
	var lastResult = 0;
	var settings = new UpscalingSettings();
	var settingsMode : UpscalingMode = null;
	var settingsWidth = -1;
	var settingsHeight = -1;

	var proxy : SwapChain;
	var swapChainResult : Int = FSRResult.NotCreated;
	var fgName : String;
	var fgContext : FSRContext;
	var fgContextWidth = -1;
	var fgContextHeight = -1;
	var fgContextFlags = -1;
	var fgContextResult = 0;
	var fgMode : FrameGenMode = Off;
	var fgPendingRelease : Bool;
	var fgFrameId = 0;
	var fgConfiguredFrame = -1;
	var fgPreparedFrame = -1;
	var fgConfigureResult = 0;
	var fgPrepareResult = 0;
	var uiRegistered : Bool;

	var antiLag2Ready : Bool;
	var antiLag2Result = 0;
	var antiLag2Mode : LowLatencyMode = Off;
	var antiLag2MaxFps = 0;

	public function new( driver : DX12Driver ) {
		super(UpscalingProvider.FSR);
		this.driver = driver;
	}

	override function beforeCreateDevice() {
		initResult = -1;
		swapChainResult = FSRResult.NotCreated;
		fgName = null;
		fgMode = Off;
		antiLag2Result = 0;
		antiLag2Mode = Off;
	}

	override function afterCreateDevice() {
		supported = new haxe.EnumFlags();
		var device = driver.nativeDevice;
		if( !FSR.isAvailable() ) return;
		if( wanted.has(Upscaler) || wanted.has(FrameGen) ) {
			initResult = FSR.init(device, Upscaling.DEBUG ? FSRDebugLevel.WARNINGS : FSRDebugLevel.ERRORS);
			loaded = initResult == FSRResult.Ok;
			if( loaded ) {
				if( wanted.has(Upscaler) && FSR.isEffectAvailable(device, FSREffect.UPSCALE) )
					supported.set(Upscaler);
				if( wanted.has(FrameGen) && FSR.isEffectAvailable(device, FSREffect.FRAME_GENERATION) )
					supported.set(FrameGen);
			} else
				trace('FSR unavailable ($initResult)');
		}
		if( wanted.has(LowLatency) ) {
			antiLag2Result = FSR.antiLag2Init(device);
			antiLag2Ready = antiLag2Result == 0;
			if( antiLag2Ready )
				supported.set(LowLatency);
		}
	}

	override function release( unused : haxe.EnumFlags<UpscalingFeature> ) {
		if( unused.has(LowLatency) && antiLag2Ready ) {
			FSR.antiLag2DeInit();
			antiLag2Ready = false;
		}
	}

	override function afterCreateQueue() {
		if( !supported.has(FrameGen) )
			return;
		var res = 0;
		proxy = FSR.createSwapChain(driver.window, driver.nativeFactory, driver.nativeQueue, driver.window.width, driver.window.height, DX12Driver.BUFFER_COUNT, R8G8B8A8_UNORM, res);
		swapChainResult = res;
		if( proxy == null ) {
			trace('FSR frame generation swapchain unavailable ($res)');
			supported.unset(FrameGen);
			return;
		}
		driver.setSwapChain(proxy);
		var version = FSR.getEffectVersion(driver.nativeDevice, FSREffect.FRAME_GENERATION);
		fgName = version == null ? "FSR FG" : "FSR FG " + version;
	}

	override function beforePresent() {
		if( proxy != null )
			finishFrameGen();
	}

	override function beforeQueuePresent() {
		if( antiLag2Ready && proxy != null )
			antiLag2Result = FSR.antiLag2Present(proxy, antiLag2Mode != Off);
	}

	override function afterQueuePresent() {
		if( proxy == null )
			return;
		fgFrameId++;
		if( fgPendingRelease ) {
			fgPendingRelease = false;
			destroyFgContext();
		}
	}

	override function releaseResizeResources() {
		destroyContext();
		destroyFgContext();
	}

	override function dispose() {
		if( proxy != null ) {
			driver.waitGpu();
			destroyFgContext();
			FSR.waitForPresents();
			FSR.destroySwapChainContext();
			var swapChain = driver.swapChain;
			driver.setSwapChain(null);
			var refsLeft = FSR.releaseSwapChain(swapChain);
			if( Upscaling.DEBUG || refsLeft != 0 )
				trace('FSR frame generation swapchain released ($refsLeft refs left)');
			proxy = null;
		}
		destroyContext();
		if( antiLag2Ready ) {
			FSR.antiLag2DeInit();
			antiLag2Ready = false;
		}
		if( loaded ) {
			FSR.shutdown();
			loaded = false;
		}
		uiRegistered = false;
		supported = new haxe.EnumFlags();
	}

	override function getName( f : UpscalingFeature ) : String {
		return switch( f ) {
			case Upscaler: context != null ? "FSR " + FSR.getVersion(context) : "FSR";
			case FrameGen: fgName != null ? fgName : "FSR FG";
			case LowLatency: "Anti-Lag 2";
		}
	}

	override function getStatus( f : UpscalingFeature ) : String {
		if( !wanted.has(f) )
			return "not selected";
		return switch( f ) {
			case Upscaler:
				loaded ? "no upscaler provider for this device" : 'init failed ($initResult)';
			case FrameGen:
				if( !loaded )
					'init failed ($initResult)';
				else if( swapChainResult != FSRResult.Ok && swapChainResult != FSRResult.NotCreated )
					'swapchain creation failed ($swapChainResult)';
				else
					"no frame generation provider for this device";
			case LowLatency:
				'not available ($antiLag2Result)';
		}
	}

	override function debug( f : UpscalingFeature ) : String {
		return switch( f ) {
			case Upscaler: debugFsr();
			case FrameGen: debugFrameGen();
			case LowLatency: debugAntiLag2();
		}
	}

	function getQuality( mode : UpscalingMode ) : FSRQuality {
		return switch( mode ) {
			case Off, NativeAA: FSRQuality.NATIVE_AA;
			case Quality: FSRQuality.QUALITY;
			case Balanced: FSRQuality.BALANCED;
			case Performance: FSRQuality.PERFORMANCE;
			case UltraPerformance: FSRQuality.ULTRA_PERFORMANCE;
		}
	}

	override function getRenderSize( mode : UpscalingMode, targetWidth : Int, targetHeight : Int ) : UpscalingSettings {
		if( mode == settingsMode && targetWidth == settingsWidth && targetHeight == settingsHeight )
			return settings;
		var renderWidth = targetWidth;
		var renderHeight = targetHeight;
		var res = FSR.getRenderResolution(driver.nativeDevice, getQuality(mode), targetWidth, targetHeight, renderWidth, renderHeight);
		if( res != FSRResult.Ok ) {
			trace('FSR render resolution query failed ($res)');
			renderWidth = targetWidth;
			renderHeight = targetHeight;
		}
		settings.renderWidth = renderWidth;
		settings.renderHeight = renderHeight;
		settingsMode = mode;
		settingsWidth = targetWidth;
		settingsHeight = targetHeight;
		return settings;
	}

	override function upscale( inputs : UpscalingInputs, p : UpscalingParams, mode : UpscalingMode ) {
		var color = inputs.color;
		var depth = inputs.depth;
		var motionVectors = inputs.motionVectors;
		var output = inputs.output;
		if( color?.t == null || depth?.t == null || motionVectors?.t == null || output?.t == null )
			return;

		var flags = 0;
		if( p.autoExposure )
			flags |= FSRCreateFlag.AUTO_EXPOSURE;
		if( p.colorBufferHDR )
			flags |= FSRCreateFlag.HIGH_DYNAMIC_RANGE;
		else
			flags |= FSRCreateFlag.NON_LINEAR_COLORSPACE;
		if( p.depthInverted )
			flags |= FSRCreateFlag.DEPTH_INVERTED;
		if( p.motionVectorsJittered )
			flags |= FSRCreateFlag.MOTION_VECTORS_JITTER_CANCELLATION;
		if( Upscaling.DEBUG ) {
			flags |= FSRCreateFlag.DEBUG_CHECKING;
			flags |= FSRCreateFlag.DEBUG_VISUALIZATION;
		}

		if( output.width != contextWidth || output.height != contextHeight || flags != contextFlags ) {
			destroyContext();
			var res = 0;
			context = FSR.createContext(driver.nativeDevice, flags, output.width, output.height, output.width, output.height, res);
			contextWidth = output.width;
			contextHeight = output.height;
			contextFlags = flags;
			if( context == null )
				trace('FSR context creation failed ($res)');
			else
				trace('FSR ${FSR.getVersion(context)} context ${output.width}x${output.height}');
		}
		if( context == null )
			return;

		var cmd = driver.beginExternalCommands();

		var d = params;
		d.color = color.t.res;
		d.colorState = color.t.state;
		d.depth = depth.t.res;
		d.depthState = depth.t.state;
		d.motionVectors = motionVectors.t.res;
		d.motionVectorsState = motionVectors.t.state;
		d.output = output.t.res;
		d.outputState = output.t.state;
		d.jitterOffsetX = p.jitterOffsetX;
		d.jitterOffsetY = p.jitterOffsetY;
		d.motionVectorScaleX = p.mvecScaleX * color.width;
		d.motionVectorScaleY = p.mvecScaleY * color.height;
		d.renderWidth = color.width;
		d.renderHeight = color.height;
		d.upscaleWidth = output.width;
		d.upscaleHeight = output.height;
		d.enableSharpening = false;
		d.sharpness = 0.;
		d.frameTimeDelta = hxd.Timer.elapsedTime * 1000.;
		d.preExposure = 1.;
		d.reset = p.reset;
		d.cameraNear = p.cameraNear;
		d.cameraFar = p.cameraFar;
		d.cameraFovAngleVertical = hxd.Math.degToRad(p.cameraFOV);
		d.viewSpaceToMetersFactor = 1.;
		var dispatchFlags = 0;
		if( !p.colorBufferHDR )
			dispatchFlags |= FSRDispatchFlag.NON_LINEAR_COLOR_SRGB;
		if( Upscaling.DEBUG && DEBUG_VIEW )
			dispatchFlags |= FSRDispatchFlag.DRAW_DEBUG_VIEW;
		d.flags = dispatchFlags;

		driver.beginEvent("FSR");
		var res = FSR.dispatch(context, cmd, d);
		driver.endEvent();
		driver.endExternalCommands();
		if( res != lastResult ) {
			if( res != FSRResult.Ok )
				trace('FSR dispatch failed ($res)');
			lastResult = res;
		}

		driver.markUsed(color);
		driver.markUsed(depth);
		driver.markUsed(motionVectors);
		driver.markUsed(output);
	}

	override function releaseUpscaler() {
		destroyContext();
	}

	function destroyContext() {
		if( context != null ) {
			driver.waitGpu();
			FSR.destroyContext(context);
			context = null;
		}
		contextWidth = -1;
		contextHeight = -1;
		contextFlags = -1;
	}

	override function setFrameGenMode( mode : FrameGenMode, numFramesToGenerate : Int, releaseResources : Bool ) : Bool {
		if( proxy == null )
			return false;
		if( mode == Off ) {
			fgMode = Off;
			if( releaseResources && fgContext != null )
				fgPendingRelease = true;
		} else {
			fgMode = On;
			fgPendingRelease = false;
		}
		return true;
	}

	override function getFrameGenMode() : FrameGenMode {
		return fgMode;
	}

	override function getFrameGenSettings() : FrameGenSettings {
		return proxy != null ? fgSettings : null;
	}

	override function composesFrameGenUI() : Bool {
		return proxy != null;
	}

	override function getHudlessBufferCount() : Int {
		return FRAME_GEN_ASYNC ? 2 : 1;
	}

	override function setFrameGenUI( hudless : h3d.mat.Texture, ui : h3d.mat.Texture ) {
		if( hudless != null || ui != null ) {
			if( hudless != null )
				driver.transition(hudless.t, NON_PIXEL_SHADER_RESOURCE);
			if( ui != null )
				driver.transition(ui.t, ALL_SHADER_RESOURCE);
			driver.flushTransitions();
		}
		if( proxy == null )
			return;
		if( ui != null ) {
			FSR.registerUiResource(ui.t.res, ui.t.state, FSRUiCompositionFlag.USE_PREMUL_ALPHA | FSRUiCompositionFlag.ENABLE_INTERNAL_UI_DOUBLE_BUFFERING);
			uiRegistered = true;
		} else if( uiRegistered ) {
			FSR.registerUiResource(null, COMMON, 0);
			uiRegistered = false;
		}
	}

	function configureFrameGen( enabled : Bool ) : Int {
		var cfg = fgConfig;
		var hudless = enabled ? driver.upscaling.getHudlessTexture() : null;
		cfg.swapChain = proxy;
		cfg.hudless = hudless == null ? null : hudless.t.res;
		cfg.hudlessState = hudless == null ? COMMON : NON_PIXEL_SHADER_RESOURCE;
		cfg.flags = FRAME_GEN_DEBUG_FLAGS;
		cfg.rectX = 0;
		cfg.rectY = 0;
		cfg.rectWidth = driver.currentWidth;
		cfg.rectHeight = driver.currentHeight;
		cfg.frameID = fgFrameId;
		cfg.enabled = enabled;
		cfg.allowAsyncWorkloads = FRAME_GEN_ASYNC;
		cfg.onlyPresentGenerated = false;
		return FSR.configureFrameGen(fgContext, cfg);
	}

	function destroyFgContext() {
		if( fgContext != null ) {
			driver.waitGpu();
			configureFrameGen(false);
			FSR.waitForPresents();
			FSR.destroyContext(fgContext);
			fgContext = null;
		}
		fgContextWidth = -1;
		fgContextHeight = -1;
		fgContextFlags = -1;
		fgContextResult = 0;
	}

	override function prepareFrameGen( inputs : UpscalingInputs, p : UpscalingParams ) {
		var depth = inputs.depth;
		var motionVectors = inputs.motionVectors;
		if( proxy == null || fgConfiguredFrame == fgFrameId )
			return;

		var enabled = fgMode != Off && depth?.t != null && motionVectors?.t != null;
		if( enabled ) {
			var flags = 0;
			if( p.depthInverted )
				flags |= FSRFrameGenCreateFlag.DEPTH_INVERTED;
			if( p.motionVectorsJittered )
				flags |= FSRFrameGenCreateFlag.MOTION_VECTORS_JITTER_CANCELLATION;
			if( Upscaling.DEBUG )
				flags |= FSRFrameGenCreateFlag.DEBUG_CHECKING;
			if( FRAME_GEN_ASYNC )
				flags |= FSRFrameGenCreateFlag.ASYNC_WORKLOAD_SUPPORT;
			if( driver.currentWidth != fgContextWidth || driver.currentHeight != fgContextHeight || flags != fgContextFlags ) {
				destroyFgContext();
				var res = 0;
				fgContext = FSR.createFrameGenContext(driver.nativeDevice, flags, driver.currentWidth, driver.currentHeight, driver.currentWidth, driver.currentHeight, DxgiFormat.R8G8B8A8_UNORM, DxgiFormat.UNKNOWN, res);
				fgContextResult = res;
				fgContextWidth = driver.currentWidth;
				fgContextHeight = driver.currentHeight;
				fgContextFlags = flags;
				if( fgContext == null )
					trace('FSR frame generation context creation failed ($res)');
				else if( Upscaling.DEBUG )
					trace('$fgName context ${driver.currentWidth}x${driver.currentHeight}');
			}
		}
		if( fgContext == null )
			return;

		fgConfigureResult = configureFrameGen(enabled);
		fgConfiguredFrame = fgFrameId;
		if( !enabled || fgConfigureResult != FSRResult.Ok )
			return;

		var cmd = driver.beginExternalCommands();

		var d = fgPrepare;
		d.depth = depth.t.res;
		d.depthState = depth.t.state;
		d.motionVectors = motionVectors.t.res;
		d.motionVectorsState = motionVectors.t.state;
		d.renderWidth = motionVectors.width;
		d.renderHeight = motionVectors.height;
		d.jitterOffsetX = p.jitterOffsetX;
		d.jitterOffsetY = p.jitterOffsetY;
		d.motionVectorScaleX = p.mvecScaleX * motionVectors.width;
		d.motionVectorScaleY = p.mvecScaleY * motionVectors.height;
		d.frameTimeDelta = hxd.Timer.elapsedTime * 1000.;
		d.reset = p.reset;
		d.cameraNear = p.cameraNear;
		d.cameraFar = p.cameraFar;
		d.cameraFovAngleVertical = hxd.Math.degToRad(p.cameraFOV);
		d.viewSpaceToMetersFactor = 1.;
		d.cameraPositionX = p.cameraPos.x;
		d.cameraPositionY = p.cameraPos.y;
		d.cameraPositionZ = p.cameraPos.z;
		d.cameraUpX = p.cameraUp.x;
		d.cameraUpY = p.cameraUp.y;
		d.cameraUpZ = p.cameraUp.z;
		d.cameraRightX = p.cameraRight.x;
		d.cameraRightY = p.cameraRight.y;
		d.cameraRightZ = p.cameraRight.z;
		d.cameraForwardX = p.cameraFwd.x;
		d.cameraForwardY = p.cameraFwd.y;
		d.cameraForwardZ = p.cameraFwd.z;
		d.frameID = fgFrameId;
		d.flags = FRAME_GEN_DEBUG_FLAGS;

		driver.beginEvent("FSR FG Prepare");
		fgPrepareResult = FSR.dispatchFrameGenPrepare(fgContext, cmd, d);
		driver.endEvent();
		driver.endExternalCommands();
		fgPreparedFrame = fgFrameId;

		driver.markUsed(depth);
		driver.markUsed(motionVectors);
	}

	function finishFrameGen() {
		if( fgContext != null && fgConfiguredFrame != fgFrameId ) {
			fgConfigureResult = configureFrameGen(false);
			fgConfiguredFrame = fgFrameId;
		}
		var prepared = fgPreparedFrame == fgFrameId;
		var status = 0;
		if( fgMode != Off ) {
			if( fgContext == null && fgContextFlags != -1 )
				status |= FG_STATUS_CONTEXT_FAILED;
			if( fgConfigureResult != FSRResult.Ok )
				status |= FG_STATUS_CONFIGURE_FAILED;
			if( prepared && fgPrepareResult != FSRResult.Ok )
				status |= FG_STATUS_PREPARE_FAILED;
			if( !prepared )
				status |= FG_STATUS_NOT_PREPARED;
		}
		var s = fgSettings;
		s.status = status;
		s.framesPresented = fgMode != Off && prepared && fgPrepareResult == FSRResult.Ok && fgConfigureResult == FSRResult.Ok ? 2 : 1;
		s.maxFramesToGenerate = 1;
		s.minWidthOrHeight = 0;
		s.dynamicSupported = false;
		s.vsyncSupported = true;
	}

	override function setLowLatencyMode( mode : LowLatencyMode, frameLimitUs : Int ) : Bool {
		if( !antiLag2Ready )
			return false;
		antiLag2Mode = mode;
		antiLag2MaxFps = frameLimitUs > 0 ? Math.round(1000000 / frameLimitUs) : 0;
		return true;
	}

	override function lowLatencySleep() {
		if( antiLag2Ready )
			antiLag2Result = FSR.antiLag2Update(antiLag2Mode != Off, antiLag2MaxFps);
	}

	function debugFsr() : String {
		var buf = new StringBuf();
		if( context == null )
			buf.add("status: FSR context creation failed\n");
		else if( lastResult != FSRResult.Ok )
			buf.add('status: FSR dispatch failed ($lastResult)\n');
		if( Upscaling.DEBUG )
			buf.add("FSR debug checker on, warnings go to the log\n");
		return buf.toString();
	}

	function debugFrameGen() : String {
		var buf = new StringBuf();
		var state = fgContext == null ? (fgPendingRelease ? "releasing" : "no context") : "context";
		buf.add('mode=$fgMode state=$state async=$FRAME_GEN_ASYNC debugFlags=$FRAME_GEN_DEBUG_FLAGS\n');
		buf.add('display=${driver.currentWidth}x${driver.currentHeight}');
		if( fgContext != null )
			buf.add(' context=${fgContextWidth}x${fgContextHeight} flags=$fgContextFlags');
		buf.add('\n');
		buf.add('frameID=$fgFrameId lastConfigured=$fgConfiguredFrame lastPrepared=$fgPreparedFrame\n');
		buf.add('framesPresentedPerFrame=${fgSettings.framesPresented}\n');
		var total = 0.;
		var aliasable = 0.;
		if( fgContext != null && FSR.queryFrameGenMemory(fgContext, total, aliasable) == FSRResult.Ok )
			buf.add('memory: frameGen=${Std.int(total / 1048576)}MB (aliasable ${Std.int(aliasable / 1048576)}MB)');
		if( FSR.querySwapChainMemory(total, aliasable) == FSRResult.Ok )
			buf.add(' swapchain=${Std.int(total / 1048576)}MB');
		buf.add('\n');
		var status = fgSettings.status;
		if( status == 0 ) {
			buf.add("status=Ok\n");
		} else {
			if( status & FG_STATUS_CONTEXT_FAILED != 0 ) buf.add('status: context creation failed ($fgContextResult)\n');
			if( status & FG_STATUS_CONFIGURE_FAILED != 0 ) buf.add('status: configure failed ($fgConfigureResult)\n');
			if( status & FG_STATUS_PREPARE_FAILED != 0 ) buf.add('status: prepare failed ($fgPrepareResult)\n');
			if( status & FG_STATUS_NOT_PREPARED != 0 ) buf.add("status: prepareFrameGen not called this frame\n");
		}
		return buf.toString();
	}

	function debugAntiLag2() : String {
		var buf = new StringBuf();
		buf.add('mode=$antiLag2Mode maxFps=$antiLag2MaxFps lastResult=$antiLag2Result');
		if( proxy != null )
			buf.add(' frameGen=$fgMode (frame type signaled through the swapchain)');
		buf.add('\n');
		return buf.toString();
	}
}

#end
