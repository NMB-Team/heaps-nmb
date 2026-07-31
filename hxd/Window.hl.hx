package hxd;

import hxd.Key.KeyCode;
import hxd.Key.KeyCode.*;
import hxd.impl.MouseMode;

#if limen
import limen.platform.event.EventType;
import limen.platform.event.Event as LEvent;
import limen.platform.Platform as LPlatform;
import limen.platform.Surface as LSurface;
import limen.platform.Window as LWindow;

typedef DisplayMode = limen.platform.Window.WindowMode;
#else
enum DisplayMode {
	Windowed; // 0
	Fullscreen; // 1
	BorderlessFixed; // 2
	Borderless; // 3
}
#end

typedef Monitor = {
	name : String,
	width : Int,
	height : Int
}

typedef DisplaySetting = {
	width : Int,
	height : Int,
	framerate : Int
}

private class NativeDroppedFile extends hxd.DropFileEvent.DroppedFile {
	public function getBytes( callback : ( data : haxe.io.Bytes ) -> Void ) {
		haxe.Timer.delay(() -> callback(sys.io.File.getBytes(file)), 1);
	}
}

//@:coreApi
class Window {

	static var WINDOWS : Array<Window> = [];

	var resizeEvents : List<Void -> Void>;
	var eventTargets : List<Event -> Void>;
	var dropTargets : List<DropFileEvent -> Void>;
	var dropFiles : Array<hxd.DropFileEvent.DroppedFile>;
	var closeRequested = false;

	public var id : Int;
	public var width(get, never) : Int;
	public var height(get, never) : Int;
	public var mouseX(get, never) : Int;
	public var mouseY(get, never) : Int;
	@:deprecated("Use mouseMode = AbsoluteUnbound(true)")
	public var mouseLock(get, set) : Bool;
	/**
		If set, will restrain the mouse cursor within the window boundaries.
	**/
	public var mouseClip(get, set) : Bool;
	/**
		Set the mouse movement input handling mode.

		@see `hxd.impl.MouseMode` for more details on each mode.
	**/
	public var mouseMode(default, set): MouseMode = Absolute;
	public var monitor : Null<Int> = null;
	public var framerate : Null<Int> = null;
	public var vsync(get, set) : Bool;
	public var isFocused(get, never) : Bool;
	public var visible(default, set) : Bool = true;
	public static var useRelativeMousePolling = true;

	/**
		Get the preferred scaling ratio for high dpi displays for this window
	**/
	public var displayScale(get, never) : Float;

	public var title(get, set) : String;
	public var displayMode(get, set) : DisplayMode;
	#if (hl_ver >= version("1.12.0"))
	public var currentMonitorIndex(get,never) : Int;
	#end

	#if limen
	var window : LWindow;

	public var platformWindow(get, never) : LWindow;

	@:noCompletion
	inline function get_platformWindow() : LWindow {
		return window;
	}
	#end

	var windowWidth = 800;
	var windowHeight = 600;
	var curMouseX = 0;
	var curMouseY = 0;
	var startMouseX = 0;
	var startMouseY = 0;
	var savedSize : { x : Int, y : Int, width : Int, height : Int };
	var flags : { fixed: Bool, hidden: Bool };
	var _vsync = true;

	static var CODEMAP : Array<KeyCode> = [for( i in 0...2048 ) i];
	static var MIN_HEIGHT = 720;
	static var MIN_FRAMERATE = 60; // 30 and 60 are always allowed
	#if limen
	static inline var TOUCH_SCALE = #if (hl_ver >= version("1.12.0")) 10000 #else 100 #end;
	#end

	public function new(title:String, width:Int, height:Int, ?flags: { ?fixed:Bool, ?hidden:Bool }) {
		this.windowWidth = width;
		this.windowHeight = height;
		eventTargets = new List();
		resizeEvents = new List();
		dropTargets = new List();
		this.flags = flags;
		var fixed = flags != null && flags.fixed != null ? flags.fixed : false;
		var hidden = flags != null && flags.hidden != null ? flags.hidden : false;
		#if limen
		var sdlFlags = 0;
		if (!fixed) sdlFlags |= LWindow.SDL_WINDOW_RESIZABLE;
		if (hidden) sdlFlags |= LWindow.SDL_WINDOW_HIDDEN;
		else sdlFlags |= LWindow.SDL_WINDOW_SHOWN;
		#if gfx_vulkan
		if( hxd.GraphicsDriverConfig.usesVulkan() )
			sdlFlags |= LWindow.SDL_WINDOW_VULKAN;
		else
		#end
		if( !hxd.GraphicsDriverConfig.usesDirectX() )
			sdlFlags |= LWindow.SDL_WINDOW_OPENGL;
		window = new LWindow(title, width, height, LWindow.SDL_WINDOWPOS_CENTERED, LWindow.SDL_WINDOWPOS_CENTERED, sdlFlags);
		this.windowWidth = window.width;
		this.windowHeight = window.height;
		if( hidden )
			window.visible = false;
		#end
		WINDOWS.push(this);
		#if multidriver
		id = window.id;
		#end
		visible = !hidden;
	}

	public dynamic function onClose() : Bool {
		return true;
	}

	public dynamic function onMove() : Void {
	}

	public dynamic function onMouseModeChange( from : MouseMode, to : MouseMode ) : Null<MouseMode> {
		return null;
	}

	public function close() {
		if( !WINDOWS.remove(this) )
			return;
		#if (multidriver && limen)
		window.destroy();
		#end
	}

	public function event( e : hxd.Event ) : Void {
		for( et in eventTargets )
			et(e);
	}

	public function addEventTarget(et : Event -> Void) : Void {
		eventTargets.add(et);
	}

	public function removeEventTarget(et : Event -> Void) : Void {
		for( e in eventTargets )
			if( Reflect.compareMethods(e,et) ) {
				eventTargets.remove(e);
				break;
			}
	}

	public function addResizeEvent( f : Void -> Void ) : Void {
		resizeEvents.push(f);
	}

	public function removeResizeEvent( f : Void -> Void ) : Void {
		for( e in resizeEvents )
			if( Reflect.compareMethods(e,f) ) {
				resizeEvents.remove(f);
				break;
			}
	}

	function onResize(e:Dynamic) : Void {
		for( r in resizeEvents )
			r();
	}

	public function resize( width : Int, height : Int ) : Void {
		#if limen
		if( window.displayMode == Fullscreen ) {
			#if (limen && hl_ver >= version("1.12.0") )
			var mode = getBestDisplayMode(width, height, framerate);
			if(mode != null) {
				window.setDisplayMode(mode.mode.width, mode.mode.height, mode.mode.framerate);
				width = mode.mode.width;
				height = mode.mode.height;
			}
			#end
		}
		window.resize(width, height);
		#end
		windowWidth = width;
		windowHeight = height;
		for( f in resizeEvents ) f();
	}

	public function addDragAndDropTarget( f : ( event : DropFileEvent ) -> Void ) : Void {
		#if limen
		if (dropTargets.length == 0) {
			LPlatform.setDragAndDropEnabled(true);
		}
		#end
		dropTargets.push(f);
	}

	public function removeDragAndDropTarget( f : ( event : DropFileEvent ) -> Void ) : Void {
		for( e in dropTargets )
			if( Reflect.compareMethods(e, f) ) {
				dropTargets.remove(f);
				break;
			}
		if ( dropTargets.length == 0 ) {
			#if limen
			LPlatform.setDragAndDropEnabled(false);
			#end
		}
	}

	public function setCursorPos( x : Int, y : Int, emitEvent : Bool = false ) : Void {
		#if limen
		if (mouseMode == Absolute) window.warpMouse(x, y);
		#else
		throw "Not implemented";
		#end
		curMouseX = x;
		curMouseY = y;
		if (emitEvent) event(new hxd.Event(EMove, x, y));
	}

	public function captureMouseEvents(enable: Bool) : Void {
		#if limen
		window.captureMouseEvents(enable);
		#end
	}

	@:deprecated("Use the displayMode property instead")
	public function setFullScreen( v : Bool ) : Void {
		#if limen
		window.displayMode = v ? BorderlessFixed : Windowed;
		#end
	}

	function get_mouseX() : Int {
		return curMouseX;
	}

	function get_mouseY() : Int {
		return curMouseY;
	}

	function get_width() : Int {
		return windowWidth;
	}

	function get_height() : Int {
		return windowHeight;
	}

	function get_mouseLock() : Bool {
		return switch (mouseMode) { case AbsoluteUnbound(_): true; default: false; };
	}

	function set_mouseLock(v:Bool) : Bool {
		return set_mouseMode(v ? AbsoluteUnbound(true) : Absolute).equals(AbsoluteUnbound(true));
	}

	function get_mouseClip() : Bool {
		#if limen
		return window.grab;
		#else
		return false;
		#end
	}

	function set_mouseClip( v : Bool ) : Bool {
		#if limen
		return window.grab = v;
		#else
		if( v ) throw "Not implemented";
		return false;
		#end
	}

	function set_mouseMode( v : MouseMode ) : MouseMode {
		if ( v.equals(mouseMode) ) return v;

		var forced = onMouseModeChange(mouseMode, v);
		if (forced != null) v = forced;

		#if limen
		var relative = v != Absolute;
		LPlatform.setRelativeMouseMode(relative);
		if( useRelativeMousePolling ) {
			LPlatform.setMouseMotionEvents(!relative);
			if( relative ) {
				var dx = 0;
				var dy = 0;
				LPlatform.getRelativeMouseState(dx, dy);
			}
		}
		#else
		if ( v != Absolute ) throw "Not implemented";
		#end

		if ( v == Absolute ) {
			switch ( mouseMode ) {
				case Relative(_, restorePos) | AbsoluteUnbound(restorePos):
					if ( restorePos ) {
						curMouseX = startMouseX;
						curMouseY = startMouseY;
					} else {
						curMouseX = hxd.Math.iclamp(curMouseX, 0, width);
						curMouseY = hxd.Math.iclamp(curMouseY, 0, height);
					}
					#if limen
					window.warpMouse(curMouseX, curMouseY);
					#end
				default:
			}
		}

		startMouseX = curMouseX;
		startMouseY = curMouseY;

		return mouseMode = v;
	}

	#if usesys

	function get_vsync() : Bool return haxe.System.vsync;

	function set_vsync( b : Bool ) : Bool {
		return haxe.System.vsync = b;
	}

	function get_isFocused() : Bool return true;

	function onEvent( e : Event ) : Bool {
		event(e);
		return true;
	}

	#elseif limen

	function get_vsync() : Bool return _vsync;

	function set_vsync( b : Bool ) : Bool {
		return _vsync = b;
	}

	function get_isFocused() : Bool return !wasBlurred;

	var wasBlurred : Bool;

	function onEvent( e : LEvent ) : Bool {
		var eh = null;
		switch( e.type ) {
		default:
			switch( e.state ) {
			case Show, Expose:
				HSystem.notifyWindowShown();
			default:
				windowWidth = window.width;
				windowHeight = window.height;
				onResize(null);
			case Focus:
				wasBlurred = false;
				event(new Event(EFocus));
			case Blur:
				wasBlurred = true;
				event(new Event(EFocusLost));
			case Enter:
				event(new Event(EOver));
			case Leave:
				event(new Event(EOut));
			case Close:
				return onCloseEvent();
			case Move:
				if( onMove != null )
					onMove();
			// default:
			}
		case MouseDown if (!HSystem.getValue(IsTouch)):
			if (mouseMode == Absolute) {
				curMouseX = e.mouseX;
				curMouseY = e.mouseY;
			}
			eh = new Event(EPush, curMouseX, curMouseY);
			// middle button -> 2 / right button -> 1
			eh.button = switch( e.button - 1 ) {
			case 0: 0;
			case 1: 2;
			case 2: 1;
			case x: x;
			}
		case MouseUp if (!HSystem.getValue(IsTouch)):
			if (mouseMode == Absolute) {
				curMouseX = e.mouseX;
				curMouseY = e.mouseY;
			}
			eh = new Event(ERelease, curMouseX, curMouseY);
			eh.button = switch( e.button - 1 ) {
			case 0: 0;
			case 1: 2;
			case 2: 1;
			case x: x;
			};
		case MouseMove if (!HSystem.getValue(IsTouch)):
			switch (mouseMode) {
				case Absolute:
					curMouseX = e.mouseX;
					curMouseY = e.mouseY;
					eh = new Event(EMove, e.mouseX, e.mouseY);
				case Relative(callback, _):
					#if limen
					var ev = new Event(EMove, e.mouseXRel, e.mouseYRel);
					#else
					var ev = new Event(EMove, e.mouseX - curMouseX, e.mouseY - curMouseY);
					#end
					callback(ev);
					if (!ev.cancel && ev.propagate) {
						ev.cancel = false;
						ev.propagate = false;
						ev.relX = curMouseX;
						ev.relY = curMouseY;
						eh = ev;
					}
				case AbsoluteUnbound(_):
					#if limen
					curMouseX += e.mouseXRel;
					curMouseY += e.mouseYRel;
					#else
					curMouseX += e.mouseX - curMouseX;
					curMouseY += e.mouseY - curMouseY;
					#end
					eh = new Event(EMove, curMouseX, curMouseY);
			}
		case MouseWheel:
			eh = new Event(EWheel, mouseX, mouseY);
			eh.wheelDelta = -e.wheelDelta;
		#if limen
		case GamepadAdded, GamepadRemoved, GamepadButtonUp, GamepadButtonDown, GamepadAxis:
			@:privateAccess hxd.Pad.onEvent( e );
		case KeyDown:
			eh = new Event(EKeyDown, curMouseX, curMouseY);
			eh.isRepeat = e.keyRepeat;
			if( e.keyCode & (1 << 30) != 0 ) e.keyCode = (e.keyCode & ((1 << 30) - 1)) + 1000;
			eh.keyCode = CODEMAP[e.keyCode];
			if( eh.keyCode & (KeyCode.LOC_LEFT | KeyCode.LOC_RIGHT) != 0 ) {
				e.keyCode = eh.keyCode & 0xFF;
				onEvent(e);
			}
		case KeyUp:
			eh = new Event(EKeyUp, curMouseX, curMouseY);
			if( e.keyCode & (1 << 30) != 0 ) e.keyCode = (e.keyCode & ((1 << 30) - 1)) + 1000;
			eh.keyCode = CODEMAP[e.keyCode];
			if( eh.keyCode & (KeyCode.LOC_LEFT | KeyCode.LOC_RIGHT) != 0 ) {
				e.keyCode = eh.keyCode & 0xFF;
				onEvent(e);
			}
		case TextInput:
			eh = new Event(ETextInput, mouseX, mouseY);
			var c = e.keyCode & 0xFF;
			eh.charCode = if( c < 0x7F )
				c;
			else if( c < 0xE0 )
				((c & 0x3F) << 6) | ((e.keyCode >> 8) & 0x7F);
			else if( c < 0xF0 )
				((c & 0x1F) << 12) | (((e.keyCode >> 8) & 0x7F) << 6) | ((e.keyCode >> 16) & 0x7F);
			else
				((c & 0x0F) << 18) | (((e.keyCode >> 8) & 0x7F) << 12) | (((e.keyCode >> 16) & 0x7F) << 6) | ((e.keyCode >> 24) & 0x7F);
		case TouchDown if (HSystem.getValue(IsTouch)):
			e.mouseX = Std.int(windowWidth * e.mouseX / TOUCH_SCALE);
			e.mouseY = Std.int(windowHeight * e.mouseY / TOUCH_SCALE);
			eh = new Event(EPush, e.mouseX, e.mouseY);
			eh.touchId = e.fingerId;
		case TouchMove if (HSystem.getValue(IsTouch)):
			e.mouseX = Std.int(windowWidth * e.mouseX / TOUCH_SCALE);
			e.mouseY = Std.int(windowHeight * e.mouseY / TOUCH_SCALE);
			eh = new Event(EMove, e.mouseX, e.mouseY);
			eh.touchId = e.fingerId;
		case TouchUp if (HSystem.getValue(IsTouch)):
			e.mouseX = Std.int(windowWidth * e.mouseX / TOUCH_SCALE);
			e.mouseY = Std.int(windowHeight * e.mouseY / TOUCH_SCALE);
			eh = new Event(ERelease, e.mouseX, e.mouseY);
			eh.touchId = e.fingerId;
		case DropStart:
			dropFiles = [];
		#end
		case DropFile:
			#if limen
			dropFiles.push(new NativeDroppedFile(@:privateAccess String.fromUTF8(e.dropFile)));
			#else
			dropFiles.push(new NativeDroppedFile(@:privateAccess String.fromUCS2(e.dropFile)));
			#end
		#if limen
		case DropEnd:
			var event = new DropFileEvent(
				dropFiles,
				mouseX, mouseY
			);
			for ( dt in dropTargets ) dt(event);
			dropFiles = null;
		case KeyMapChanged:
			HSystem.onKeyboardLayoutChange();
		#else // limen post both Close+Quit
		case Quit:
			return onCloseEvent();
		#end
		// default:
		}
		if( eh != null ) {
			#if limen
			eh.timestamp = e.timestamp;
			#end
			event(eh);
		}
		return true;
	}

	function onCloseEvent() {
		if( closeRequested )
			return true;
		closeRequested = true;
		var ret = onClose();
		if( ret )
			close();
		else
			closeRequested = false;
		return ret;
	}

	#if limen
	function processRelativeMouseDelta(dx:Int, dy:Int) {
		switch (mouseMode) {
			case Relative(callback, _):
				var ev = new Event(EMove, dx, dy);
				callback(ev);
				if (!ev.cancel && ev.propagate) {
					ev.cancel = false;
					ev.propagate = false;
					ev.relX = curMouseX;
					ev.relY = curMouseY;
					event(ev);
				}
			case AbsoluteUnbound(_):
				curMouseX += dx;
				curMouseY += dy;
				event(new Event(EMove, curMouseX, curMouseY));
			case Absolute:
		}
	}
	#end

	static function initChars() : Void {

		inline function addKey(sdl, keyCode : KeyCode) {
			CODEMAP[sdl] = keyCode;
		}

		// ASCII
		for( i in 0...26 )
			addKey(97 + i, A + i);
		for( i in 0...12 )
			addKey(1058 + i, F1 + i);
		for( i in 0...12 )
			addKey(1104 + i, F13 + i);

		// NUMPAD
		addKey(1084, NUMPAD_DIV);
		addKey(1085, NUMPAD_MULT);
		addKey(1086, NUMPAD_SUB);
		addKey(1087, NUMPAD_ADD);
		addKey(1088, NUMPAD_ENTER);
		for( i in 0...9 )
			addKey(1089 + i, NUMPAD_1 + i);
		addKey(1098, NUMPAD_0);
		addKey(1099, NUMPAD_DOT);

		// EXTRA
		var keys = [
			//BACKSPACE
			//TAB
			//ENTER
			1225 => LSHIFT,
			1229 => RSHIFT,
			1224 => LCTRL,
			1228 => RCTRL,
			1226 => LALT,
			1230 => RALT,
			1227 => LEFT_WINDOW_KEY,
			1231 => RIGHT_WINDOW_KEY,
			// ESCAPE
			// SPACE
			1075 => PGUP,
			1078 => PGDOWN,
			1077 => END,
			1074 => HOME,
			1080 => LEFT,
			1082 => UP,
			1079 => RIGHT,
			1081 => DOWN,
			1073 => INSERT,
			127 => DELETE,
			//NUMPAD_0-9
			//A-Z
			//F1-F12
			1085 => NUMPAD_MULT,
			1087 => NUMPAD_ADD,
			1088 => NUMPAD_ENTER,
			1086 => NUMPAD_SUB,
			1099 => NUMPAD_DOT,
			1084 => NUMPAD_DIV,

			39 => QWERTY_QUOTE,
			44 => QWERTY_COMMA,
			45 => QWERTY_MINUS,
			46 => QWERTY_PERIOD,
			47 => QWERTY_SLASH,
			59 => QWERTY_SEMICOLON,
			61 => QWERTY_EQUALS,
			91 => QWERTY_BRACKET_LEFT,
			92 => QWERTY_BACKSLASH,
			93 => QWERTY_BRACKET_RIGHT,
			96 => QWERTY_TILDE,
			167 => QWERTY_BACKSLASH,

			// AZERTY
			41 => QWERTY_BRACKET_LEFT, // degree
			94 => QWERTY_BRACKET_RIGHT, // caret
			249 => QWERTY_TILDE, // percent
			58 => QWERTY_SLASH, // slash
			33 => AZERTY_EXCLAM,
			36 => QWERTY_SEMICOLON, // dollar

			1101 => CONTEXT_MENU,
			1057 => CAPS_LOCK,
			1071 => SCROLL_LOCK,
			1072 => PAUSE_BREAK,
			1083 => NUM_LOCK,
			// LowerThan on AZERTY, none on QWERTY because limen uses sym code, instead of scancode - INTL_BACKSLASH always reports 0x5C, e.g. regular slash.
			60 => INTL_BACKSLASH,

			//1070 => PRINT_SCREEN
		];
		for( sdl in keys.keys() )
			addKey(sdl, keys.get(sdl));
	}

	#else

	function get_vsync() : Bool return true;

	function set_vsync( b : Bool ) : Bool {
		return true;
	}

	function get_isFocused() : Bool return false;

	function onEvent( e : Event ) : Bool {
		event(e);
		return true;
	}

	#end

	function set_visible( v : Bool ) : Bool {
		if( visible == v )
			return v;
		#if limen
		window.visible = v;
		#end
		if( flags != null )
			flags.hidden = !v;
		return visible = v;
	}

	function get_displayMode() : DisplayMode {
		#if limen
		return window.displayMode;
		#end
		return Windowed;
	}

	function set_displayMode( m : DisplayMode ) : DisplayMode {
		#if limen
		var oldMode = window.displayMode;
		#if (hl_ver >= version("1.12.0"))
		if( window.displayMode != m ) {
			if(window.displayMode == Windowed) {
				if( savedSize == null ) {
					savedSize = { x: window.x, y: window.y, width: window.width, height: window.height };
				}
			}
		}

		if(flags != null && flags.hidden)
			return displayMode;

		// No way to choose the screen in SDL, need to fit the window in the right screen before.
		if(m != Windowed && monitor != null) {
			window.displayMode = Windowed;
			var mon = selectedMonitor();
			if(mon != null) {
				window.setPosition(mon.left, mon.top);
				window.resize(mon.right-mon.left, mon.bottom-mon.top);
			}
		}
		if( m == Fullscreen ) {
			var dm = getBestDisplayMode(windowWidth, windowHeight, framerate);
			if(dm != null)
				window.displaySetting = dm.mode;
			window.displayMode = m;
		}
		else {
			window.displayMode = m;
			if( oldMode != m && m == Windowed && savedSize != null) {
				window.setPosition(savedSize.x, savedSize.y);
				window.resize(savedSize.width, savedSize.height);
				savedSize = null;
			}
		}
		#else
		window.displayMode = m;
		#end
		#end
		return displayMode;
	}

	public function applyDisplay() {
		displayMode = displayMode;
	}

	public function setIcon(icon: hxd.BitmapData) : Void {
		#if limen
		var pixels = icon.getPixels();
		pixels.convert(BGRA);
		var surf = LSurface.fromBGRA(pixels.bytes, pixels.width, pixels.height);
		window.setIcon(surf);
		surf.free();
		pixels.dispose();
		#end
	}

	#if (hl_ver >= version("1.12.0"))
	public static function getMonitors() : Array<Monitor> {
		#if limen
		return [for(m in LPlatform.getDisplays()) { name: m.name, width: m.width, height: m.height}];
		#else
		return [];
		#end
	}

	// If registry is set, return the default DisplaySetting when it's currently modified by the application.
	public function getCurrentDisplaySetting(?monitorId : Int, registry : Bool = false) : DisplaySetting {
		#if limen
		var mon = LPlatform.getDisplays()[monitorId == null ? 0 : monitorId];
		return LPlatform.getCurrentDisplayMode(mon.id, true);
		#else
		return null;
		#end
	}

	public function getDisplaySettings(?monitorId : Int) : Array<DisplaySetting> {
		var map = new Map<String,DisplaySetting>();
		var f = [];
		if(monitorId == null)
			monitorId = monitor;
		#if limen
		var m = LPlatform.getDisplays()[monitorId == null ? currentMonitorIndex : monitorId];
		var l = LPlatform.getDisplayModes(m.id);
		#else
		var l = [];
		#end
		for(d in l) {
			if(d.height >= MIN_HEIGHT && (d.framerate >= MIN_FRAMERATE || d.framerate == 30 || d.framerate == 60)) {
				f.push(d);
			}
		}
		if(f.length > 0)
			return f;
		else
			return l;
	}

	function selectedMonitor() : Dynamic {
		var m = if(monitor == null) currentMonitorIndex else monitor;
		#if limen
		return LPlatform.getDisplays()[m];
		#else
		return null;
		#end
	}

	function getBestDisplayMode(width:Int, height:Int, framerate:Null<Int>) {
		var m : {idx: Int, mode: DisplaySetting } = {
			idx: -1,
			mode: null
		}
		var settings = getDisplaySettings(currentMonitorIndex);
		for( i => s in settings ) {
			if(s.width == width && s.height == height) {
				if(s.framerate == framerate)
					return { idx: i, mode: s };
				else if(framerate == null || s.framerate == framerate)
					m = {idx : i, mode : s };
				else if(m.idx == -1)
					m = {idx: i, mode : s };
			}
		}
		if(m.idx != -1)
			return m;
		for( i => s in settings ) {
			if(s.width >= width && s.height >= height) {
				if(framerate == null || s.framerate == framerate)
					return { idx: i, mode: s };
				else if(m.idx == -1)
					m = {idx: i, mode : s };
			}
		}
		if(m.idx != -1)
			return m;
		return null;
	}

	function get_currentMonitorIndex() : Int {
		#if limen
		var current = window.currentMonitor;
		for(i => m in LPlatform.getDisplays()) {
			if(m.id == current)
				return i;
		}
		return 0;
		#else
		return 0;
		#end
	}

	#end
	function get_title() : String {
		#if limen
		return window.title;
		#end
		return "";
	}
	function set_title( t : String ) : String {
		#if limen
		return window.title = t;
		#end
		return "";
	}

	public function setCurrent() {
		inst = this;
	}

	static var inst : Window = null;
	public static function getInstance() : Window {
		return inst;
	}

	public static function hasWindow() {
		return WINDOWS.length > 0;
	}

	static function dispatchEvent( e ) {
		#if multidriver
		if( false ) @:privateAccess WINDOWS[0].onEvent(e); // typing
		for( w in WINDOWS )
			if( e.windowId == w.id )
				return w.onEvent(e);
		if( inst != null && (e.windowId == 0 || WINDOWS.length == 1) )
			return inst.onEvent(e);
		return true;
		#else
		return inst.onEvent(e);
		#end
	}

	#if limen
	static function processRelativeMouseEvents() {
		if( !useRelativeMousePolling )
			return;
		var dx = 0;
		var dy = 0;
		LPlatform.getRelativeMouseState(dx, dy);
		if( dx == 0 && dy == 0 )
			return;
		if( inst != null )
			inst.processRelativeMouseDelta(dx, dy);
	}
	#end

	function get_displayScale() {
		#if limen
		return window.displayScale;
		#else
		return 1.0;
		#end
	}

}
