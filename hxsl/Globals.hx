package hxsl;
import h3d.mat.Texture;

abstract GlobalSlot<T>(Int) {
	public inline function new(name:String) {
		this = Globals.allocID(name);
	}
	public inline function toInt() {
		return this;
	}
	public inline function set( globals : Globals, v : T ) {
		globals.fastSet(toInt(), v);
	}
	public inline function get( globals : Globals ) : T {
		return globals.fastGet(toInt());
	}
}

class Globals {

	var map : Map<Int,Dynamic>;
	var channels : Array<Texture> = [];
	var maxChannels : Int;
	#if hl
	var scalarSlots : Map<Int,Int>;
	var scalarValues : Array<Float>;
	var scalarKinds : Array<Int>;
	#end

	public function new() {
		map = new Map<Int,Dynamic>();
	}

	public function set( path : String, v : Dynamic ) {
		fastSet(allocID(path), v);
	}

	public function get( path : String) : Dynamic {
		return fastGet(allocID(path));
	}

	public inline function fastSet( id : Int, v : Dynamic ) {
		map.set(id, v);
		#if hl
		if( scalarSlots != null ) {
			var slot = scalarSlots.get(id);
			if( slot != null ) scalarKinds[slot] = 0;
		}
		#end
	}

	public inline function fastGet( id : Int ) : Dynamic {
		var value = map.get(id);
		#if hl
		if( value == null && scalarSlots != null ) {
			var slot = scalarSlots.get(id);
			if( slot != null )
				switch( scalarKinds[slot] ) {
				case 1: value = scalarValues[slot];
				case 2: value = Std.int(scalarValues[slot]);
				default:
				}
		}
		#end
		return value;
	}

	#if hl
	function setScalar(id : Int, value : Float, kind : Int) {
		if( scalarSlots == null ) {
			scalarSlots = new Map();
			scalarValues = [];
			scalarKinds = [];
		}
		var slot = scalarSlots.get(id);
		if( slot == null ) {
			slot = scalarValues.length;
			scalarSlots.set(id, slot);
			scalarValues.push(value);
			scalarKinds.push(0);
		}

		if( scalarKinds[slot] == 0 ) map.remove(id);
		scalarValues[slot] = value;
		scalarKinds[slot] = kind;
	}

	public inline function fastSetFloat(id : Int, value : Float) {
		setScalar(id, value, 1);
	}

	public inline function fastSetInt(id : Int, value : Int) {
		setScalar(id, value, 2);
	}

	public inline function hasScalar(id : Int) : Bool {
		var slot = scalarSlots == null ? null : scalarSlots.get(id);
		return slot != null && scalarKinds[slot] != 0;
	}

	public inline function fastGetFloat(id : Int) : Float {
		var slot = scalarSlots == null ? null : scalarSlots.get(id);
		return slot != null && scalarKinds[slot] != 0 ? scalarValues[slot] : map.get(id);
	}

	public inline function fastGetInt(id : Int) : Int {
		var slot = scalarSlots == null ? null : scalarSlots.get(id);
		return slot != null && scalarKinds[slot] == 2 ? Std.int(scalarValues[slot]) : fastGet(id);
	}
	#end

	public inline function resetChannels() {
		maxChannels = 0;
	}

	public function allocChannelID( t : Texture ) {
		for( i in 0...maxChannels )
			if( channels[i] == t )
				return i;
		if( maxChannels == 1 << Ast.Tools.MAX_CHANNELS_BITS )
			throw "Too many unique channels";
		var i = maxChannels++;
		channels[i] = t;
		return i;
	}

	static var ALL : Array<String>;
	static var MAP : Map<String,Int>;
	#if heaps_mt_hxsl_cache
	static var idMutex = new sys.thread.Mutex();
	#end
	public static function allocID( path : String ) : Int {
		#if heaps_mt_hxsl_cache
		idMutex.acquire();
		#end
		if( MAP == null ) {
			MAP = new Map();
			ALL = [];
		}
		var id = MAP.get(path);
		if( id == null ) {
			id = ALL.length;
			ALL.push(path);
			MAP.set(path, id);
		}
		#if heaps_mt_hxsl_cache
		idMutex.release();
		#end
		return id;
	}
	public static function getIDName( id : Int ) : String {
		return ALL[id];
	}

}
