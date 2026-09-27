package hxd;

class NMBTrace {
	static var shaderHits = 0;
	static var shaderMisses = 0;
	static var shaderCompiles = 0;

	public static function shaderCacheHit() {
		if( !enabled() ) return;
		instant("heaps.shader", "Shader Cache Hit");
		counter("heaps.shader", "Shader Cache Hits", ++shaderHits);
	}

	public static function shaderCacheMiss() {
		if( !enabled() ) return;
		instant("heaps.shader", "Shader Cache Miss");
		counter("heaps.shader", "Shader Cache Misses", ++shaderMisses);
	}

	public static function shaderCompile() {
		if( !enabled() ) return;
		counter("heaps.shader", "Shader Compiles", ++shaderCompiles);
	}
	#if hl
	static var available = hl.Api.isPrimLoaded(nativeEnabled);
	static var durationsAvailable = hl.Api.isPrimLoaded(nativeNow) && hl.Api.isPrimLoaded(nativeDuration);

	public static inline function enabled() : Bool return available && nativeEnabled();
	public static inline function durationAvailable() : Bool return durationsAvailable && enabled();

	public static inline function begin(category : String, name : String) : Void {
		if( enabled() ) nativeBegin(@:privateAccess category.bytes, @:privateAccess name.bytes);
	}

	public static inline function end(category : String) : Void {
		if( enabled() ) nativeEnd(@:privateAccess category.bytes);
	}

	public static inline function instant(category : String, name : String) : Void {
		if( enabled() ) nativeInstant(@:privateAccess category.bytes, @:privateAccess name.bytes);
	}

	public static inline function counter(category : String, name : String, value : Float) : Void {
		if( enabled() ) nativeCounter(@:privateAccess category.bytes, @:privateAccess name.bytes, value);
	}

	public static inline function now() : Float return durationAvailable() ? nativeNow() : 0.;

	public static inline function duration(category : String, name : String, timestampUs : Float, durationUs : Float) : Void {
		if( durationAvailable() ) nativeDuration(@:privateAccess category.bytes, @:privateAccess name.bytes, timestampUs, durationUs);
	}

	@:hlNative("?std", "nmb_trace_enabled") static function nativeEnabled() : Bool return false;
	@:hlNative("?std", "nmb_trace_begin") static function nativeBegin(category : hl.Bytes, name : hl.Bytes) : Void {}
	@:hlNative("?std", "nmb_trace_end") static function nativeEnd(category : hl.Bytes) : Void {}
	@:hlNative("?std", "nmb_trace_instant") static function nativeInstant(category : hl.Bytes, name : hl.Bytes) : Void {}
	@:hlNative("?std", "nmb_trace_counter") static function nativeCounter(category : hl.Bytes, name : hl.Bytes, value : Float) : Void {}
	@:hlNative("?std", "nmb_trace_now") static function nativeNow() : Float return 0.;
	@:hlNative("?std", "nmb_trace_duration") static function nativeDuration(category : hl.Bytes, name : hl.Bytes, timestampUs : Float, durationUs : Float) : Void {}
	#else
	public static inline function enabled() : Bool return false;
	public static inline function durationAvailable() : Bool return false;
	public static inline function begin(category : String, name : String) : Void {}
	public static inline function end(category : String) : Void {}
	public static inline function instant(category : String, name : String) : Void {}
	public static inline function counter(category : String, name : String, value : Float) : Void {}
	public static inline function now() : Float return 0.;
	public static inline function duration(category : String, name : String, timestampUs : Float, durationUs : Float) : Void {}
	#end
}
