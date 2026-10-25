package h3d.impl.driver.dx12.upscaling;

#if (limen && gfx_dx12 && dlss_allowed && !macro)

import h3d.impl.Upscaling;
import h3d.impl.driver.dx12.DX12Driver;
import limen.graphics.renderer.d3d12.internal.D3D12Bindings;
import limen.graphics.renderer.d3d12.internal.D3D12Bindings.SwapChain;
import limen.graphics.renderer.d3d12.resource.Resources;
import limen.graphics.renderer.d3d12.command.Commands.CommandList;
import limen.graphics.postprocess.dlss.resource.DLSSBufferType;
import limen.graphics.postprocess.dlss.frame.DLSSConstants;
import limen.graphics.postprocess.dlss.frame.DLSSFrameToken;
import limen.graphics.postprocess.dlss.DLSSFeature;
import limen.graphics.postprocess.dlss.DLSSResult;
import limen.graphics.postprocess.dlss.frame.DLSSMatrix;
import limen.graphics.postprocess.dlss.upscaling.DLSSMode;
import limen.graphics.postprocess.dlss.upscaling.DLSSOptimalSettings;
import limen.graphics.postprocess.dlss.upscaling.DLSSOptions;
import limen.graphics.postprocess.dlss.upscaling.DLSSPreset;
import limen.graphics.postprocess.dlss.resource.DLSSResource;
import limen.graphics.postprocess.dlss.resource.DLSSResourceLifecycle;
import limen.graphics.postprocess.dlss.frame.DLSSVector;
import limen.graphics.postprocess.dlss.framegen.DLSSGFlag;
import limen.graphics.postprocess.dlss.framegen.DLSSGModeNative;
import limen.graphics.postprocess.dlss.framegen.DLSSGOptions;
import limen.graphics.postprocess.dlss.framegen.DLSSGStateInfo;
import limen.graphics.postprocess.dlss.pcl.PCLHotKey;
import limen.graphics.postprocess.dlss.pcl.PCLMarker;
import limen.graphics.postprocess.dlss.reflex.ReflexFrameReport;
import limen.graphics.postprocess.dlss.reflex.ReflexModeNative;
import limen.graphics.postprocess.dlss.reflex.ReflexStateInfo;
import limen.graphics.postprocess.dlss.DLSS;
import limen.graphics.postprocess.PostProcessDevice;
import limen.graphics.postprocess.TextureResource;

@:access(h3d.impl.driver.dx12.DX12Driver)
class DX12DlssBackend extends UpscalingBackend {

	public static var CHECK_SIGNATURE = true;

	static var optimalSettings = new DLSSOptimalSettings();
	static var settings = new UpscalingSettings();
	static var options = new DLSSOptions();
	static var constants = new DLSSConstants();
	static var dlssgOptions = new DLSSGOptions();
	static var dlssgStateInfo = new DLSSGStateInfo();
	static var dlssgSettings = new FrameGenSettings();
	static var matCameraViewToClip = new DLSSMatrix();
	static var matClipToCameraView = new DLSSMatrix();
	static var matClipToLensClip = new DLSSMatrix();
	static var matClipToPrevClip = new DLSSMatrix();
	static var matPrevClipToClip = new DLSSMatrix();
	static var vecCameraPos = new DLSSVector();
	static var vecCameraUp = new DLSSVector();
	static var vecCameraRight = new DLSSVector();
	static var vecCameraFwd = new DLSSVector();

	var driver : DX12Driver;
	var slInitResult = -1;
	var slReady : Bool;
	var dlssSupportResult = -1;
	var dlssReady : Bool;
	var framegenReady : Bool;
	var pclReady : Bool;
	var reflexReady : Bool;
	var reflexState : ReflexStateInfo;
	var reflexMode : LowLatencyMode = Off;
	var frameToken : DLSSFrameToken;
	var pclFlashRequested : Bool;
	var dlssgMode : FrameGenMode = Off;
	var dlssgFrames = 1;
	var dlssgLastStatus = 0;
	var resizeDlssgMode : FrameGenMode = Off;
	var constantsFrame = -1;
	var lastResult = 0;
	var tagTypes : Array<DLSSBufferType> = [];
	var tagTextures : Array<h3d.mat.Texture> = [];

	public function new( driver : DX12Driver ) {
		super(UpscalingProvider.DLSS);
		this.driver = driver;
	}

	override function beforeCreateDevice() {
		slReady = false;
		dlssReady = false;
		framegenReady = false;
		pclReady = false;
		reflexReady = false;
		slInitResult = -1;
		dlssSupportResult = -1;
		frameToken = null;
		dlssgMode = Off;
		reflexMode = Off;
		if( wanted.toInt() == 0 || !DLSS.isAvailable() )
			return;
		var features = [];
		if( wanted.has(Upscaler) ) features.push(DLSSFeature.DLSS);
		if( wanted.has(FrameGen) ) features.push(DLSSFeature.FRAMEGEN);
		if( wanted.has(LowLatency) || wanted.has(FrameGen) ) features.push(DLSSFeature.REFLEX);
		var nativeFeatures = new hl.NativeArray<Int>(features.length);
		for( i => f in features )
			nativeFeatures[i] = f;
		slInitResult = DLSS.init(Upscaling.DEBUG, nativeFeatures, CHECK_SIGNATURE);
		slReady = slInitResult == 0;
	}

	override function afterCreateDevice() {
		supported = new haxe.EnumFlags();
		if( !slReady )
			return;
		var device = new PostProcessDevice(D3D12, driver.nativeDevice);
		var dlssOk = false;
		if( wanted.has(Upscaler) ) {
			dlssSupportResult = DLSS.isFeatureSupported(device, DLSSFeature.DLSS);
			dlssOk = dlssSupportResult == 0;
		}
		var dlssgOk = wanted.has(FrameGen) && DLSS.isFeatureSupported(device, DLSSFeature.FRAMEGEN) == 0;
		var reflexOk = (wanted.has(LowLatency) || dlssgOk) && DLSS.isFeatureSupported(device, DLSSFeature.REFLEX) == 0;
		if( !dlssOk && !dlssgOk && !reflexOk ) {
			DLSS.shutdown();
			slReady = false;
			return;
		}
		D3D12Bindings.setDevice(DLSS.upgradeDevice(driver.nativeDevice));
		slReady = DLSS.setDevice(new PostProcessDevice(D3D12, D3D12Bindings.getDevice())) == 0;
		if( !slReady )
			return;
		if( wanted.has(FrameGen) && !dlssgOk )
			DLSS.setFeatureLoaded(DLSSFeature.FRAMEGEN, false);
		dlssReady = dlssOk;
		framegenReady = dlssgOk;
		if( reflexOk ) {
			pclReady = DLSS.isFeatureSupported(device, DLSSFeature.PCL) == 0 && DLSS.pclInitStats() == 0;
			if( reflexState == null )
				reflexState = new ReflexStateInfo();
			reflexReady = DLSS.reflexSetOptions(ReflexModeNative.OFF, 0, false, PCLHotKey.USE_PING_MESSAGE, 0) == 0;
		}
		if( dlssReady ) supported.set(Upscaler);
		if( framegenReady ) supported.set(FrameGen);
		if( reflexReady ) supported.set(LowLatency);
	}

	override function release( unused : haxe.EnumFlags<UpscalingFeature> ) {
		if( unused.has(FrameGen) && framegenReady ) {
			DLSS.setFeatureLoaded(DLSSFeature.FRAMEGEN, false);
			framegenReady = false;
		}
		if( unused.has(LowLatency) )
			reflexReady = false;
	}

	override function afterCreateQueue() {
		if( !slReady )
			return;
				driver.nativeQueue = DLSS.getNativeQueue(driver.directQueue);

		D3D12Bindings.setFactory(DLSS.upgradeFactory(driver.nativeFactory));
	}

	override function afterCreateSwapChain() {
		if( slReady && driver.swapChain != null )
			driver.setSwapChain(DLSS.upgradeSwapChain(driver.swapChain));
	}

	override function beginFrame() {
		if( !slReady )
			return;
		frameToken = DLSS.getNewFrameToken(driver.frameCount);
		if( reflexReady )
			DLSS.reflexGetState(reflexState);
	}

	override function begin() {
		pclMarker(PCLMarker.RENDER_SUBMIT_START);
	}

	override function beforeQueuePresent() {
		pclMarker(PCLMarker.RENDER_SUBMIT_END);
		pclMarker(PCLMarker.PRESENT_START);
	}

	override function afterQueuePresent() {
		pclMarker(PCLMarker.PRESENT_END);
		if( dlssgMode == Off )
			dlssgSettings.framesPresented = 1;
		else if( refreshDLSSGState() && dlssgSettings.status != 0 )
			setDlssgMode(Off, 1, false);
	}

	override function beforeResize() {
		resizeDlssgMode = dlssgMode;
		if( framegenReady && dlssgMode != Off )
			setDlssgMode(Off, 1, false);
	}

	override function afterResize() {
		if( framegenReady && resizeDlssgMode != Off )
			setDlssgMode(resizeDlssgMode, dlssgFrames, false);
	}

	override function dispose() {
		if( !slReady )
			return;
		if( dlssgMode != Off ) {
			setDlssgMode(Off, 1, true);
			DLSS.setFeatureLoaded(DLSSFeature.FRAMEGEN, false);
		}
		driver.waitGpu();
		DLSS.shutdown();
		slReady = false;
		dlssReady = false;
		framegenReady = false;
		pclReady = false;
		reflexReady = false;
		frameToken = null;
		supported = new haxe.EnumFlags();
	}

	override function isAvailable( f : UpscalingFeature ) : Bool {
		return switch( f ) {
			case LowLatency: reflexReady && reflexState != null && reflexState.lowLatencyAvailable != 0;
			default: supported.has(f);
		}
	}

	override function getName( f : UpscalingFeature ) : String {
		return switch( f ) {
			case Upscaler: "DLSS";
			case FrameGen: "DLSS-G";
			case LowLatency: "Reflex";
		}
	}

	override function getStatus( f : UpscalingFeature ) : String {
		if( !wanted.has(f) )
			return "not selected";
		if( slInitResult != 0 )
			return 'Streamline init failed ($slInitResult)';
		return switch( f ) {
			case Upscaler: dlssSupportResult < 0 ? "Streamline device setup failed" : 'not supported on this adapter ($dlssSupportResult)';
			case FrameGen: "not supported on this adapter";
			case LowLatency: "not supported on this adapter";
		}
	}

	override function debug( f : UpscalingFeature ) : String {
		return switch( f ) {
			case Upscaler: debugDlss();
			case FrameGen: debugDlssg();
			case LowLatency: debugReflex();
		}
	}

	function getMode( mode : UpscalingMode ) : DLSSMode {
		return switch( mode ) {
			case Off: DLSSMode.OFF;
			case NativeAA: DLSSMode.DLAA;
			case Quality: DLSSMode.MAXQUALITY;
			case Balanced: DLSSMode.BALANCED;
			case Performance: DLSSMode.MAXPERFORMANCE;
			case UltraPerformance: DLSSMode.ULTRAPERFORMANCE;
		}
	}

	override function getRenderSize( mode : UpscalingMode, targetWidth : Int, targetHeight : Int ) : UpscalingSettings {
		options.mode = getMode(mode);
		options.outputWidth = targetWidth;
		options.outputHeight = targetHeight;
		DLSS.getOptimalSettings(options, optimalSettings);
		settings.renderWidth = optimalSettings.optimalRenderWidth;
		settings.renderHeight = optimalSettings.optimalRenderHeight;
		return settings;
	}

	override function upscale( inputs : UpscalingInputs, params : UpscalingParams, mode : UpscalingMode ) {
		var output = inputs.output;
		if( !dlssReady || frameToken == null || output == null )
			return;
		options.mode = getMode(mode);
		options.outputWidth = output.width;
		options.outputHeight = output.height;
		options.colorBufferHDR = params.colorBufferHDR;
		options.preset = mode == NativeAA ? DLSSPreset.PRESET_L : DLSSPreset.PRESET_K;
		DLSS.setOptions(options);

		var cmd = driver.beginExternalCommands();
		addTag(DLSSBufferType.COLORIN, inputs.color);
		addTag(DLSSBufferType.MOTIONVECTORS, inputs.motionVectors);
		addTag(DLSSBufferType.DEPTH, inputs.depth);
		addTag(DLSSBufferType.COLOROUT, output);
		flushTags(cmd);
		setConstants(params);
		lastResult = DLSS.evaluateFeature(frameToken, cmd, DLSSFeature.DLSS);
		driver.endExternalCommands();
	}

	override function releaseUpscaler() {
		if( !dlssReady )
			return;
		driver.waitGpu();
		DLSS.freeResources(DLSSFeature.DLSS);
	}

	override function setFrameGenMode( mode : FrameGenMode, numFramesToGenerate : Int, releaseResources : Bool ) : Bool {
		return setDlssgMode(mode, numFramesToGenerate, releaseResources);
	}

	override function getFrameGenMode() : FrameGenMode {
		return dlssgMode;
	}

	override function getFrameGenSettings() : FrameGenSettings {
		return slReady && framegenReady ? dlssgSettings : null;
	}

	override function prepareFrameGen( inputs : UpscalingInputs, params : UpscalingParams ) {
		if( !framegenReady )
			return;
		addTag(DLSSBufferType.MOTIONVECTORS, inputs.motionVectors);
		addTag(DLSSBufferType.DEPTH, inputs.depth);
		flushTags(driver.frame.commandList);
		setConstants(params);
	}

	override function setFrameGenUI( hudless : h3d.mat.Texture, ui : h3d.mat.Texture ) {
		if( hudless == null && ui == null )
			return;
		if( hudless != null )
			driver.transition(hudless.t, NON_PIXEL_SHADER_RESOURCE);
		if( ui != null )
			driver.transition(ui.t, ALL_SHADER_RESOURCE);
		driver.flushTransitions();
		if( !framegenReady || dlssgMode == Off )
			return;
		addTag(DLSSBufferType.HUDLESSCOLOR, hudless);
		addTag(DLSSBufferType.UICOLORANDALPHA, ui);
		flushTags(driver.frame.commandList);
	}

	override function setLowLatencyMode( mode : LowLatencyMode, frameLimitUs : Int ) : Bool {
		if( !reflexReady )
			return false;
		var native = switch( mode ) {
			case Off: ReflexModeNative.OFF;
			case On: ReflexModeNative.LOW_LATENCY;
			case OnWithBoost: ReflexModeNative.LOW_LATENCY_WITH_BOOST;
		}
		if( DLSS.reflexSetOptions(native, frameLimitUs, false, PCLHotKey.USE_PING_MESSAGE, 0) != 0 )
			return false;
		reflexMode = mode;
		return true;
	}

	override function lowLatencySleep() {
		if( reflexReady && frameToken != null )
			DLSS.reflexSleep(frameToken);
	}

	override function latencyMarker( m : LatencyMarker ) {
		switch( m ) {
		case SimulationStart:
			if( pclReady && frameToken != null ) {
				pclMarker(PCLMarker.SIMULATION_START);
				DLSS.pclPollPing(frameToken);
			}
		case SimulationEnd:
			pclMarker(PCLMarker.SIMULATION_END);
			if( pclFlashRequested ) {
				pclMarker(PCLMarker.TRIGGER_FLASH);
				pclFlashRequested = false;
			}
		case TriggerFlash:
			pclFlashRequested = true;
		}
	}

	override function isFlashIndicatorDriverControlled() : Bool {
		return reflexReady && reflexState != null && reflexState.flashIndicatorDriverControlled != 0;
	}

	inline function pclMarker( marker : PCLMarker ) {
		if( slReady && pclReady && frameToken != null )
			DLSS.pclSetMarker(frameToken, marker);
	}

	function addTag( type : DLSSBufferType, t : h3d.mat.Texture ) {
		if( t == null || t.t == null )
			return;
		tagTypes.push(type);
		tagTextures.push(t);
	}

	var taggedResources : Array<TextureResource> = [];

	function flushTags( cmd : CommandList ) {
		var count = tagTypes.length;
		if( count > 0 && frameToken != null ) {
			var resources = hl.CArray.alloc(DLSSResource, count);
			for( i in 0...count ) {
				var t = tagTextures[i];
				var r = resources[i];
				if( i == taggedResources.length ) taggedResources.push(new TextureResource(null, 0));
				var texture = taggedResources[i];
				texture.native = t.t.res;
				texture.state = cast t.t.state;
				r.res = texture;
				r.width = t.width;
				r.height = t.height;
				r.type = tagTypes[i];
				r.lifecycle = DLSSResourceLifecycle.VALID_UNTIL_PRESENT;
				driver.markUsed(t);
			}
			DLSS.setTagForFrame(frameToken, resources, count, cmd);
		}
		tagTypes.resize(0);
		tagTextures.resize(0);
	}

	inline static function loadVec( vec : DLSSVector, v : h3d.Vector ) {
		vec.x = cast(v.x, Single);
		vec.y = cast(v.y, Single);
		vec.z = cast(v.z, Single);
	}

	inline static function loadMat( mat : DLSSMatrix, m : h3d.Matrix ) {
		mat._11 = cast(m._11, Single); mat._12 = cast(m._12, Single); mat._13 = cast(m._13, Single); mat._14 = cast(m._14, Single);
		mat._21 = cast(m._21, Single); mat._22 = cast(m._22, Single); mat._23 = cast(m._23, Single); mat._24 = cast(m._24, Single);
		mat._31 = cast(m._31, Single); mat._32 = cast(m._32, Single); mat._33 = cast(m._33, Single); mat._34 = cast(m._34, Single);
		mat._41 = cast(m._41, Single); mat._42 = cast(m._42, Single); mat._43 = cast(m._43, Single); mat._44 = cast(m._44, Single);
	}

	function setConstants( params : UpscalingParams ) {
		if( !slReady || frameToken == null || constantsFrame == driver.frameCount )
			return;
		constantsFrame = driver.frameCount;

		loadMat(matCameraViewToClip, params.cameraViewToClip);
		loadMat(matClipToCameraView, params.clipToCameraView);
		loadMat(matClipToPrevClip, params.clipToPrevClip);
		loadMat(matPrevClipToClip, params.prevClipToClip);

		loadVec(vecCameraPos, params.cameraPos);
		loadVec(vecCameraUp, params.cameraUp);
		loadVec(vecCameraRight, params.cameraRight);
		loadVec(vecCameraFwd, params.cameraFwd);

		var c = constants;
		c.cameraViewToClip = matCameraViewToClip;
		c.clipToCameraView = matClipToCameraView;
		c.clipToLensClip = matClipToLensClip;
		c.clipToPrevClip = matClipToPrevClip;
		c.prevClipToClip = matPrevClipToClip;
		c.jitterOffsetX = params.jitterOffsetX;
		c.jitterOffsetY = params.jitterOffsetY;
		c.mvecScaleX = params.mvecScaleX;
		c.mvecScaleY = params.mvecScaleY;
		c.cameraPinholeOffsetX = 0.0;
		c.cameraPinholeOffsetY = 0.0;
		c.cameraPos = vecCameraPos;
		c.cameraUp = vecCameraUp;
		c.cameraRight = vecCameraRight;
		c.cameraFwd = vecCameraFwd;
		c.cameraNear = params.cameraNear;
		c.cameraFar = params.cameraFar;
		c.cameraFOV = params.cameraFOV;
		c.cameraAspectRatio = params.cameraAspectRatio;
		c.motionVectorsInvalidValue = params.motionVectorsInvalidValue;
		c.depthInverted = params.depthInverted;
		c.cameraMotionIncluded = params.cameraMotionIncluded;
		c.motionVectors3D = false;
		c.reset = params.reset;
		c.orthographicProjection = params.orthographicProjection;
		c.motionVectorsDilated = params.motionVectorsDilated;
		c.motionVectorsJittered = params.motionVectorsJittered;
		c.minRelativeLinearDepthObjectSeparation = 40.0;

		DLSS.setConstants(frameToken, c);
	}

	function setDlssgMode( mode : FrameGenMode, numFramesToGenerate : Int, releaseResources : Bool ) : Bool {
		if( !slReady || !framegenReady )
			return false;
		if( mode != Off && reflexMode == Off )
			return false;

		dlssgOptions.mode = switch( mode ) {
			case Off: DLSSGModeNative.OFF;
			case On: DLSSGModeNative.ON;
			case Auto: DLSSGModeNative.AUTO;
			case Dynamic: DLSSGModeNative.DYNAMIC;
		}
		dlssgOptions.numFramesToGenerate = numFramesToGenerate;
		if( mode != Off )
			dlssgFrames = numFramesToGenerate;

		dlssgOptions.flags = DLSSGFlag.RETAIN_RESOURCES_WHEN_OFF;
		if( DLSS.dlssgSetOptions(dlssgOptions) != 0 )
			return false;

		dlssgMode = mode;
		refreshDLSSGState();
		if( mode == Off && releaseResources )
			DLSS.freeResources(DLSSFeature.FRAMEGEN);
		return true;
	}

	function refreshDLSSGState() : Bool {
		if( !slReady || !framegenReady || DLSS.dlssgGetState(dlssgStateInfo) != 0 )
			return false;
		var s = dlssgSettings;
		s.status = dlssgStateInfo.status;
		s.minWidthOrHeight = dlssgStateInfo.minWidthOrHeight;
		s.framesPresented = dlssgStateInfo.numFramesActuallyPresented;
		s.maxFramesToGenerate = dlssgStateInfo.numFramesToGenerateMax;
		s.dynamicSupported = dlssgStateInfo.dynamicMFGSupported != 0;
		s.vsyncSupported = dlssgStateInfo.vsyncSupportAvailable != 0;
		if( s.status != 0 )
			dlssgLastStatus = s.status;
		return true;
	}

	function debugDlss() : String {
		var result : DLSSResult = cast lastResult;
		if( result == DLSSResult.WarnOutOfVRAM ) {
			var mem = driver.getMemoryUsage();
			return 'status: DLSS out of VRAM warning (${Std.int(mem.allocated / 1048576)} / ${Std.int(mem.total / 1048576)} MB)\n';
		}
		if( result != DLSSResult.Ok )
			return 'status: DLSS evaluate failed ($lastResult)\n';
		return "";
	}

	function debugDlssg() : String {
		var buf = new StringBuf();
		var state = dlssgSettings;
		buf.add('mode=$dlssgMode framesToGenerate=$dlssgFrames reflexMode=$reflexMode\n');
		buf.add('framesPresentedPerFrame=${state.framesPresented}\n');
		buf.add('minWidthOrHeight=${state.minWidthOrHeight} maxFramesToGenerate=${state.maxFramesToGenerate} ');
		buf.add('dynamicSupported=${state.dynamicSupported} vsyncSupported=${state.vsyncSupported}\n');
		var status = state.status == 0 ? dlssgLastStatus : state.status;
		if( status == 0 ) {
			buf.add("status=Ok\n");
		} else {
			if( status & 1 != 0 ) buf.add("status: output resolution too low\n");
			if( status & 2 != 0 ) buf.add("status: Reflex not active at runtime\n");
			if( status & 4 != 0 ) buf.add("status: HDR format not supported\n");
			if( status & 8 != 0 ) buf.add("status: common constants invalid\n");
			if( status & 16 != 0 ) buf.add("status: GetCurrentBackBufferIndex not called\n");
		}
		if( driver.currentWidth < state.minWidthOrHeight || driver.currentHeight < state.minWidthOrHeight )
			buf.add('backbuffer ${driver.currentWidth}x${driver.currentHeight} is below minWidthOrHeight\n');
		return buf.toString();
	}

	function debugReflex() : String {
		var buf = new StringBuf();
		if( reflexState == null )
			reflexState = new ReflexStateInfo();
		DLSS.reflexGetState(reflexState);
		buf.add('mode=$reflexMode ');
		buf.add('lowLatencyAvailable=${reflexState.lowLatencyAvailable} ');
		buf.add('latencyReportAvailable=${reflexState.latencyReportAvailable} ');
		buf.add('flashIndicatorDriverControlled=${reflexState.flashIndicatorDriverControlled} ');
		buf.add('statsWindowMessage=${reflexState.statsWindowMessage}\n');
		if( reflexState.lowLatencyAvailable == 0 ) buf.add("Low latency is not available.\n");
		if( reflexState.latencyReportAvailable == 0 ) buf.add("Latency report are not available.\n");
		var reports = [];
		for( i in 0...DLSS.REFLEX_FRAME_REPORT_COUNT ) {
			var r = new ReflexFrameReport();
			if( DLSS.reflexGetFrameReport(i, r) == 0 && r.frameID > 0 )
				reports.push(r);
		}
		if( reports.length == 0 ) {
			buf.add("Empty reports.\n");
			return buf.toString();
		}
		reports.sort((a, b) -> a.frameID < b.frameID ? -1 : (a.frameID > b.frameID ? 1 : 0));
		var totalPcLatency = 0.;
		var totalGpuFrameUs = 0.;
		buf.add('\nframeID   simMs   renderMs   driverMs   osQueueMs   gpuMs   pcLatencyMs   gpuFrameTimeUs\n');
		for( r in reports ) {
			inline function ms( a : Float, b : Float ) return (b - a) / 1000.0;
			var pcLatency = ms(r.simStartTime, r.presentEndTime);
			buf.add('${r.frameID}   ${ms(r.simStartTime, r.simEndTime)}   ${ms(r.renderSubmitStartTime, r.renderSubmitEndTime)}   ${ms(r.driverStartTime, r.driverEndTime)}   ${ms(r.osRenderQueueStartTime, r.osRenderQueueEndTime)}   ${ms(r.gpuRenderStartTime, r.gpuRenderEndTime)}   ${pcLatency}   ${r.gpuFrameTimeUs}\n');
			totalPcLatency += pcLatency;
			totalGpuFrameUs += r.gpuFrameTimeUs;
			if( r.driverStartTime <= 0 || r.gpuRenderStartTime <= 0 || r.osRenderQueueStartTime <= 0 )
				buf.add("One or more driver/OS/GPU timestamps are 0.\n");
		}
		var n = reports.length;
		buf.add('\nSampled ${n} frames. Avg PC latency: ${totalPcLatency / n} ms. Avg GPU frame time: ${totalGpuFrameUs / n} us.\n');
		return buf.toString();
	}
}

#end
