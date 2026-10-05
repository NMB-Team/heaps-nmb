package h3d.impl.driver;

import h3d.Buffer;
import h3d.impl.driver.upscaling.*;

class Driver {

	static var SHADER_CACHE : h3d.impl.ShaderCache;
	var shaderCache = SHADER_CACHE;

	public static function setShaderCache( cache : h3d.impl.ShaderCache ) {
		SHADER_CACHE = cache;
	}

	public var logEnable : Bool;


	public function hasFeature( f : Feature ) {
		return false;
	}

	public function setRenderFlag( r : RenderFlag, value : Int ) {
	}

	public function isSupportedFormat( fmt : h3d.mat.Data.TextureFormat ) {
		return false;
	}

	public function isDisposed() {
		return true;
	}

	public function isFrameReady() {
		return true;
	}

	public function dispose() {
	}

	public function begin( frame : Int ) {
	}

	public inline function log( str : String ) {
		#if debug
		if( logEnable ) logImpl(str);
		#end
	}

	public function generateMipMaps( texture : h3d.mat.Texture ) {
		throw "Mipmaps auto generation is not supported on this platform";
	}

	public function getNativeShaderCode( shader : hxsl.RuntimeShader ) : String {
		return null;
	}

	public function warmupShader( shader : hxsl.RuntimeShader ) {
	}

	function logImpl( str : String ) {
	}

	public function clear( ?color : h3d.Vector4, ?depth : Float, ?stencil : Int ) {
	}

	public function getMemoryUsage() : Null<{ total : Float, allocated : Float, free : Float }>  {
		return null;
	}

	public function captureRenderBuffer( pixels : hxd.Pixels ) {
	}

	public function capturePixels( tex : h3d.mat.Texture, layer : Int, mipLevel : Int, ?region : h2d.col.IBounds ) : hxd.Pixels {
		throw "Can't capture pixels on this platform";
		return null;
	}

	public function getDriverName( details : Bool ) {
		return "Not available";
	}

	public function getRendererName() {
		return "Not available";
	}

	public function init( onCreate : Bool -> Void, forceSoftware = false ) {
	}

	public function resize( width : Int, height : Int ) {
	}

	public function selectShader( shader : hxsl.RuntimeShader ) {
		return false;
	}

	public function selectMaterial( pass : h3d.mat.Pass ) {
	}

	public function selectTextureHandles( handles : Array<h3d.mat.TextureHandle> ) {
	}

	public function selectBufferHandles( handles : Array<h3d.BufferHandle> ) {
	}


	public function uploadShaderBuffers( buffers : h3d.shader.Buffers, which : h3d.shader.Buffers.BufferKind ) {
	}

	public function flushShaderBuffers() {
	}

	public function selectBuffer( buffer : Buffer ) {
	}

	public function selectMultiBuffers( format : hxd.BufferFormat.MultiFormat, buffers : Array<h3d.Buffer> ) {
	}

	public function draw( ibuf : Buffer, startIndex : Int, ntriangles : Int ) {
	}

	public function drawInstanced( ibuf : Buffer, commands : h3d.impl.InstanceBuffer ) {
	}

	public function setRenderZone( x : Int, y : Int, width : Int, height : Int ) {
	}

	public function setRenderTarget( tex : Null<h3d.mat.Texture>, layer = 0, mipLevel = 0, depthBinding : h3d.Engine.DepthBinding = ReadWrite ) {
	}

	public function setRenderTargets( textures : Array<h3d.mat.Texture>, depthBinding : h3d.Engine.DepthBinding = ReadWrite ) {
	}

	public function setDepth( tex : Null<h3d.mat.Texture>, layer = 0 ) {
		if( layer != 0 )
			throw "Not implemented";
	}

	public function setDepthClamp( enabled : Bool ) {
	}

	public function setDepthBias( depthBias : Float,  slopeScaledBias : Float ) {
	}

	public function allocDepthBuffer( b : h3d.mat.Texture ) : Texture {
		return null;
	}

	public function disposeDepthBuffer( b : h3d.mat.Texture ) {
	}

	public function getDefaultDepthBuffer() : h3d.mat.Texture {
		return null;
	}

	public function present() {
	}

	public function end() {
	}

	public function setDebug( b : Bool ) {
	}

	public function allocTexture( t : h3d.mat.Texture ) : Texture {
		return null;
	}

	public function allocBuffer( b : h3d.Buffer ) : GPUBuffer {
		return null;
	}

	public function allocInstanceBuffer( b : h3d.impl.InstanceBuffer, bytes : haxe.io.Bytes ) {
	}

	public function uploadInstanceBufferBytes(b : h3d.impl.InstanceBuffer, startVertex : Int, vertexCount : Int, buf : haxe.io.Bytes, bufPos : Int ) {
	}

	public function disposeTexture( t : h3d.mat.Texture ) {
	}

	public function disposeBuffer( b : Buffer ) {
	}

	public function disposeInstanceBuffer( b : h3d.impl.InstanceBuffer ) {
	}

	public function uploadIndexData( i : Buffer, startIndice : Int, indiceCount : Int, buf : hxd.IndexBuffer, bufPos : Int ) {
	}

	public function uploadBufferData( b : Buffer, startVertex : Int, vertexCount : Int, buf : hxd.FloatBuffer, bufPos : Int ) {
	}

	public function uploadBufferBytes( b : Buffer, startVertex : Int, vertexCount : Int, buf : haxe.io.Bytes, bufPos : Int ) {
	}

	public function uploadTextureBitmap( t : h3d.mat.Texture, bmp : hxd.BitmapData, mipLevel : Int, side : Int ) {
	}

	public function uploadTexturePixels( t : h3d.mat.Texture, pixels : hxd.Pixels, mipLevel : Int, side : Int ) {
	}

	public function readBufferBytes( b : Buffer, startVertex : Int, vertexCount : Int, buf : haxe.io.Bytes, bufPos : Int ) {
	}

	public function readBufferBytesAsync( b : Buffer, startVertex : Int, vertexCount : Int, buf : haxe.io.Bytes, bufPos : Int, callback : Void -> Void ) {
	}

	/**
		Returns true if we could copy the texture, false otherwise (not supported by driver or mismatch in size/format)
	**/
	public function copyTexture( from : h3d.mat.Texture, to : h3d.mat.Texture ) {
		return false;
	}

	// --- MARKING API

	public function beginEvent( name : String ) {
	}

	public function endEvent() {
	}

	// --- QUERY API

	public function allocQuery( queryKind : QueryKind ) : Query {
		return null;
	}

	public function deleteQuery( q : Query ) {
	}

	public function beginQuery( q : Query ) {
	}

	public function endQuery( q : Query ) {
	}

	public function queryResultAvailable( q : Query ) {
		return true;
	}

	public function queryResult( q : Query ) {
		return 0.;
	}

	// --- COMPUTE

	public function computeDispatch( x : Int = 1, y : Int = 1, z : Int = 1, barrier: Bool = true ) {
		throw "Compute shaders are not implemented on this platform";
	}

	public function memoryBarrier(){
		throw "Compute shaders are not implemented on this platform";
	}

	// --- Bindless

	public function getTextureHandle( t : h3d.mat.Texture ) : h3d.mat.TextureHandle {
		throw "Bindless is not implemented on this platform";
	}

	public function getBufferHandle( b : h3d.Buffer ) : h3d.BufferHandle {
		throw "Bindless is not implemented on this platform";
	}

	public function isUpscalingSupported() : Bool {
		return false;
	}

	public function isFrameGenSupported() : Bool {
		return false;
	}

	public function getUpscalerName() : String {
		return null;
	}

	public function getUpscalingSettings( mode : UpscalingMode, targetWidth : Int, targetHeight : Int ) : UpscalingSettings {
		return null;
	}

	public function applyUpscaling( resources : Map<UpscalingTag, h3d.mat.Texture>, params : UpscalingParams, mode : UpscalingMode ) {
	}

	public function setFrameGenResources( resources : Map<UpscalingTag, h3d.mat.Texture> ) {
	}

	public function clearFrameGenResources() {
	}

	public function setFrameGenParams( params : UpscalingParams ) {
	}

	public function setFrameGenMode( mode : FrameGenMode, numFramesToGenerate : Int = 1, releaseResources = false ) : Bool {
		return false;
	}

	public function getFrameGenMode() : FrameGenMode {
		return Off;
	}

	public function getFrameGenSettings() : FrameGenSettings {
		return null;
	}

	public function latencyMarkerSimulationStart() {
	}

	public function latencyMarkerSimulationEnd() {
	}

	public function latencyMarkerTriggerFlash() {
	}

	public function lowLatencySleep() {
	}

	public function setLowLatencyOptions( mode : LowLatencyMode, frameLimitUs : Int = 0 ) {
		return false;
	}

	public function lowLatencyAvailable() {
		return false;
	}

	public function lowLatencyFlashIndicatorDriverControlled() {
		return false;
	}

	public function debugUpscaling() : String {
		return "";
	}

	public function debugLowLatency() : String {
		return "";
	}

	public function debugFrameGen() : String {
		return "";
	}

	public function shutdownUpscaling() {
	}
}
