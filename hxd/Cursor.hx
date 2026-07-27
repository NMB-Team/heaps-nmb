package hxd;

enum Cursor {
	Default;
	Button;
	Move;
	TextInput;
	Hide;
	ResizeNS;
	ResizeWE;
	ResizeNWSE;
	ResizeNESW;
	Custom( custom : CustomCursor );
	/**
		When this cursor is selected, call the function itself, which can handle complex logic and is responsible to call hxd.System.setCursor
	**/
	Callback( f : Void -> Void );
}

@:allow(hxd.System)
class CustomCursor {

	var frames : Array<hxd.BitmapData>;
	var speed : Float;
	var offsetX : Int;
	var offsetY : Int;
	#if macro
	var alloc : Array<Dynamic>;
	#elseif limen
	var alloc : Array<limen.platform.cursor.Cursor>;
	#elseif js
	var alloc : Array<String>;
	#else
	var alloc : Dynamic;
	#end
	#if (limen && !macro)
	var allocSurfaces : Array<limen.platform.Surface>;
	var allocPixels : Array<hxd.Pixels>;
	#end

	// Heaps-side cursor animation for target that do not support native animated cursors.
	#if (limen || js)
	var frameDelay : Float;
	var frameTime : Float;
	var frameIndex : Int;
	#end

	public function new( frames, speed, offsetX, offsetY ) {
		this.frames = frames;
		this.speed = speed;
		this.offsetX = offsetX;
		this.offsetY = offsetY;
		#if (limen || js)
		frameDelay = 1 / speed;
		frameTime = 0;
		frameIndex = 0;
		#end
	}

	#if (limen || js)
	public function reset() : Void {
		frameTime = 0;
		frameIndex = 0;
	}

	public function update( dt : Float ) : Int {
		var newTime : Float = frameTime + dt;
		var delay : Float = frameDelay;
		var index : Int = frameIndex;
		while( newTime >= delay ) {
			newTime -= delay;
			index++;
		}
		frameTime = newTime;

		if ( index >= frames.length ) index %= frames.length;
		if ( index != frameIndex ) {
			frameIndex = index;
			return index;
		}
		return -1;
	}
	#end

	public function dispose() {
		for( f in frames )
			f.dispose();
		frames = [];
		if( alloc != null ) {
			#if (limen && !macro)
			for (cur in alloc) {
				cur.free();
			}
			for (surf in allocSurfaces) {
				surf.free();
			}
			for (pixels in allocPixels) {
				pixels.dispose();
			}
			allocSurfaces = null;
			allocPixels = null;
			#elseif js
			// alloc set to null below.
			#else
			throw "TODO";
			#end
			alloc = null;
		}
	}

	#if js
	public static function getNativeCursor( name : String ) {
		var c = new CustomCursor([],0,0,0);
		c.alloc = [name];
		return Custom(c);
	}
	#end

}
