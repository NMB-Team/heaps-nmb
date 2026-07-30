package hxd;

enum abstract KeyCode(Int) from Int to Int {
	// SDL note: Because SDL uses different mapping, it should be set accordingly in the Window.hl.hx in `initChars` function.

	final BACKSPACE	= 8;
	final TAB			= 9;
	final ENTER		= 13;
	final SHIFT		= 16;
	final CTRL			= 17;
	final ALT			= 18;
	final ESCAPE		= 27;
	final SPACE		= 32;
	final PGUP			= 33;
	final PGDOWN		= 34;
	final END			= 35;
	final HOME			= 36;
	final LEFT			= 37;
	final UP			= 38;
	final RIGHT		= 39;
	final DOWN			= 40;
	final INSERT		= 45;
	final DELETE		= 46;

	final QWERTY_EQUALS = 187;
	final QWERTY_MINUS = 189;
	final QWERTY_TILDE = 192;
	final QWERTY_BRACKET_LEFT = 219;
	final QWERTY_BRACKET_RIGHT = 221;
	final QWERTY_SEMICOLON = 186;
	final QWERTY_QUOTE = 222;
	final QWERTY_BACKSLASH = 220;
	final QWERTY_COMMA = 188;
	final QWERTY_PERIOD = 190;
	final QWERTY_SLASH = 191;
	final INTL_BACKSLASH = 226; // Backslash located next to left shift on some keyboards. Warning: Not available on Limen.
	final LEFT_WINDOW_KEY = 91;
	final RIGHT_WINDOW_KEY = 92;
	final CONTEXT_MENU = 93;

	final AZERTY_DOLLAR = 186;
	final AZERTY_EQUALS = 187;
	final AZERTY_COMMA = 188;
	final AZERTY_SEMICOLON = 190;
	final AZERTY_COLON = 191;
	final AZERTY_MODULO = 192;
	final AZERTY_PARENT_CLOSE = 219;
	final AZERTY_MULTIPLY = 220;
	final AZERTY_POWER = 221;
	final AZERTY_SQUARED = 222;
	final AZERTY_EXCLAM = 223;
	// final PRINT_SCREEN = // Only available on SDL

	final PAUSE_BREAK = 19;
	final CAPS_LOCK = 20;
	final NUM_LOCK = 144;
	final SCROLL_LOCK = 145;

	final NUMBER_0	= 48;
	final NUMBER_1	= 49;
	final NUMBER_2	= 50;
	final NUMBER_3	= 51;
	final NUMBER_4	= 52;
	final NUMBER_5	= 53;
	final NUMBER_6	= 54;
	final NUMBER_7	= 55;
	final NUMBER_8	= 56;
	final NUMBER_9	= 57;

	final NUMPAD_0	= 96;
	final NUMPAD_1	= 97;
	final NUMPAD_2	= 98;
	final NUMPAD_3	= 99;
	final NUMPAD_4	= 100;
	final NUMPAD_5	= 101;
	final NUMPAD_6	= 102;
	final NUMPAD_7	= 103;
	final NUMPAD_8	= 104;
	final NUMPAD_9	= 105;

	final A		= 65;
	final B		= 66;
	final C		= 67;
	final D		= 68;
	final E		= 69;
	final F		= 70;
	final G		= 71;
	final H		= 72;
	final I		= 73;
	final J		= 74;
	final K		= 75;
	final L		= 76;
	final M		= 77;
	final N		= 78;
	final O		= 79;
	final P		= 80;
	final Q		= 81;
	final R		= 82;
	final S		= 83;
	final T		= 84;
	final U		= 85;
	final V		= 86;
	final W		= 87;
	final X		= 88;
	final Y		= 89;
	final Z		= 90;

	final F1		= 112;
	final F2		= 113;
	final F3		= 114;
	final F4		= 115;
	final F5		= 116;
	final F6		= 117;
	final F7		= 118;
	final F8		= 119;
	final F9		= 120;
	final F10		= 121;
	final F11		= 122;
	final F12		= 123;
	// Extended F keys
	final F13		= 124;
	final F14		= 125;
	final F15		= 126;
	final F16		= 127;
	final F17		= 128;
	final F18		= 129;
	final F19		= 130;
	final F20		= 131;
	final F21		= 132;
	final F22		= 133;
	final F23		= 134;
	final F24		= 135;

	final NUMPAD_MULT 	= 106;
	final NUMPAD_ADD	= 107;
	final NUMPAD_ENTER = 108;
	final NUMPAD_SUB 	= 109;
	final NUMPAD_DOT 	= 110;
	final NUMPAD_DIV 	= 111;

	final MOUSE_LEFT 		= 0;
	final MOUSE_RIGHT 		= 1;
	final MOUSE_MIDDLE 	= 2;
	final MOUSE_BACK 		= 3;
	final MOUSE_FORWARD 	= 4;
	/**
	 * Mouse wheel does not have an off signal, and should be checked only through `isPressed` method.
	 * Note that there may be multiple wheel scrolls between 2 frames, and to receive more accurate
	 * results, it is recommended to directly listen to wheel events which also provide OS-generated wheel delta value.
	 * See `Interactive.onWheel` for per-interactive events. For scene-based see `Scene.addEventListener`
	 * when event is `EWheel`. For global hook use `Window.addEventTarget` method.
	 */
	final MOUSE_WHEEL_UP = 5;
	/**
	 * Mouse wheel does not have an off signal, and should be checked only through `isPressed` method.
	 * Note that there may be multiple wheel scrolls between 2 frames, and to receive more accurate
	 * results, it is recommended to directly listen to wheel events which also provide OS-generated wheel delta value.
	 * See `Interactive.onWheel` for per-interactive events. For scene-based see `Scene.addEventListener`
	 * when event is `EWheel`. For global hook use `Window.addEventTarget` method.
	 */
	final MOUSE_WHEEL_DOWN = 6;

	/** a bit that is set for left keys **/
	public static inline final LOC_LEFT = 256;
	/** a bit that is set for right keys **/
	public static inline final LOC_RIGHT = 512;

	final LSHIFT = 272;
	final RSHIFT = 528;
	final LCTRL = 273;
	final RCTRL = 529;
	final LALT = 274;
	final RALT = 530;
}

class Key {

	@:deprecated("Use KeyCode.BACKSPACE instead") public static inline final BACKSPACE = KeyCode.BACKSPACE;
	@:deprecated("Use KeyCode.TAB instead") public static inline final TAB = KeyCode.TAB;
	@:deprecated("Use KeyCode.ENTER instead") public static inline final ENTER = KeyCode.ENTER;
	@:deprecated("Use KeyCode.SHIFT instead") public static inline final SHIFT = KeyCode.SHIFT;
	@:deprecated("Use KeyCode.CTRL instead") public static inline final CTRL = KeyCode.CTRL;
	@:deprecated("Use KeyCode.ALT instead") public static inline final ALT = KeyCode.ALT;
	@:deprecated("Use KeyCode.ESCAPE instead") public static inline final ESCAPE = KeyCode.ESCAPE;
	@:deprecated("Use KeyCode.SPACE instead") public static inline final SPACE = KeyCode.SPACE;
	@:deprecated("Use KeyCode.PGUP instead") public static inline final PGUP = KeyCode.PGUP;
	@:deprecated("Use KeyCode.PGDOWN instead") public static inline final PGDOWN = KeyCode.PGDOWN;
	@:deprecated("Use KeyCode.END instead") public static inline final END = KeyCode.END;
	@:deprecated("Use KeyCode.HOME instead") public static inline final HOME = KeyCode.HOME;
	@:deprecated("Use KeyCode.LEFT instead") public static inline final LEFT = KeyCode.LEFT;
	@:deprecated("Use KeyCode.UP instead") public static inline final UP = KeyCode.UP;
	@:deprecated("Use KeyCode.RIGHT instead") public static inline final RIGHT = KeyCode.RIGHT;
	@:deprecated("Use KeyCode.DOWN instead") public static inline final DOWN = KeyCode.DOWN;
	@:deprecated("Use KeyCode.INSERT instead") public static inline final INSERT = KeyCode.INSERT;
	@:deprecated("Use KeyCode.DELETE instead") public static inline final DELETE = KeyCode.DELETE;

	@:deprecated("Use KeyCode.QWERTY_EQUALS instead") public static inline final QWERTY_EQUALS = KeyCode.QWERTY_EQUALS;
	@:deprecated("Use KeyCode.QWERTY_MINUS instead") public static inline final QWERTY_MINUS = KeyCode.QWERTY_MINUS;
	@:deprecated("Use KeyCode.QWERTY_TILDE instead") public static inline final QWERTY_TILDE = KeyCode.QWERTY_TILDE;
	@:deprecated("Use KeyCode.QWERTY_BRACKET_LEFT instead") public static inline final QWERTY_BRACKET_LEFT = KeyCode.QWERTY_BRACKET_LEFT;
	@:deprecated("Use KeyCode.QWERTY_BRACKET_RIGHT instead") public static inline final QWERTY_BRACKET_RIGHT = KeyCode.QWERTY_BRACKET_RIGHT;
	@:deprecated("Use KeyCode.QWERTY_SEMICOLON instead") public static inline final QWERTY_SEMICOLON = KeyCode.QWERTY_SEMICOLON;
	@:deprecated("Use KeyCode.QWERTY_QUOTE instead") public static inline final QWERTY_QUOTE = KeyCode.QWERTY_QUOTE;
	@:deprecated("Use KeyCode.QWERTY_BACKSLASH instead") public static inline final QWERTY_BACKSLASH = KeyCode.QWERTY_BACKSLASH;
	@:deprecated("Use KeyCode.QWERTY_COMMA instead") public static inline final QWERTY_COMMA = KeyCode.QWERTY_COMMA;
	@:deprecated("Use KeyCode.QWERTY_PERIOD instead") public static inline final QWERTY_PERIOD = KeyCode.QWERTY_PERIOD;
	@:deprecated("Use KeyCode.QWERTY_SLASH instead") public static inline final QWERTY_SLASH = KeyCode.QWERTY_SLASH;
	@:deprecated("Use KeyCode.INTL_BACKSLASH instead") public static inline final INTL_BACKSLASH = KeyCode.INTL_BACKSLASH;
	@:deprecated("Use KeyCode.LEFT_WINDOW_KEY instead") public static inline final LEFT_WINDOW_KEY = KeyCode.LEFT_WINDOW_KEY;
	@:deprecated("Use KeyCode.RIGHT_WINDOW_KEY instead") public static inline final RIGHT_WINDOW_KEY = KeyCode.RIGHT_WINDOW_KEY;
	@:deprecated("Use KeyCode.CONTEXT_MENU instead") public static inline final CONTEXT_MENU = KeyCode.CONTEXT_MENU;

	@:deprecated("Use KeyCode.AZERTY_DOLLAR instead") public static inline final AZERTY_DOLLAR = KeyCode.AZERTY_DOLLAR;
	@:deprecated("Use KeyCode.AZERTY_EQUALS instead") public static inline final AZERTY_EQUALS = KeyCode.AZERTY_EQUALS;
	@:deprecated("Use KeyCode.AZERTY_COMMA instead") public static inline final AZERTY_COMMA = KeyCode.AZERTY_COMMA;
	@:deprecated("Use KeyCode.AZERTY_SEMICOLON instead") public static inline final AZERTY_SEMICOLON = KeyCode.AZERTY_SEMICOLON;
	@:deprecated("Use KeyCode.AZERTY_COLON instead") public static inline final AZERTY_COLON = KeyCode.AZERTY_COLON;
	@:deprecated("Use KeyCode.AZERTY_MODULO instead") public static inline final AZERTY_MODULO = KeyCode.AZERTY_MODULO;
	@:deprecated("Use KeyCode.AZERTY_PARENT_CLOSE instead") public static inline final AZERTY_PARENT_CLOSE = KeyCode.AZERTY_PARENT_CLOSE;
	@:deprecated("Use KeyCode.AZERTY_MULTIPLY instead") public static inline final AZERTY_MULTIPLY = KeyCode.AZERTY_MULTIPLY;
	@:deprecated("Use KeyCode.AZERTY_POWER instead") public static inline final AZERTY_POWER = KeyCode.AZERTY_POWER;
	@:deprecated("Use KeyCode.AZERTY_SQUARED instead") public static inline final AZERTY_SQUARED = KeyCode.AZERTY_SQUARED;
	@:deprecated("Use KeyCode.AZERTY_EXCLAM instead") public static inline final AZERTY_EXCLAM = KeyCode.AZERTY_EXCLAM;

	@:deprecated("Use KeyCode.PAUSE_BREAK instead") public static inline final PAUSE_BREAK = KeyCode.PAUSE_BREAK;
	@:deprecated("Use KeyCode.CAPS_LOCK instead") public static inline final CAPS_LOCK = KeyCode.CAPS_LOCK;
	@:deprecated("Use KeyCode.NUM_LOCK instead") public static inline final NUM_LOCK = KeyCode.NUM_LOCK;
	@:deprecated("Use KeyCode.SCROLL_LOCK instead") public static inline final SCROLL_LOCK = KeyCode.SCROLL_LOCK;

	@:deprecated("Use KeyCode.NUMBER_0 instead") public static inline final NUMBER_0 = KeyCode.NUMBER_0;
	@:deprecated("Use KeyCode.NUMBER_1 instead") public static inline final NUMBER_1 = KeyCode.NUMBER_1;
	@:deprecated("Use KeyCode.NUMBER_2 instead") public static inline final NUMBER_2 = KeyCode.NUMBER_2;
	@:deprecated("Use KeyCode.NUMBER_3 instead") public static inline final NUMBER_3 = KeyCode.NUMBER_3;
	@:deprecated("Use KeyCode.NUMBER_4 instead") public static inline final NUMBER_4 = KeyCode.NUMBER_4;
	@:deprecated("Use KeyCode.NUMBER_5 instead") public static inline final NUMBER_5 = KeyCode.NUMBER_5;
	@:deprecated("Use KeyCode.NUMBER_6 instead") public static inline final NUMBER_6 = KeyCode.NUMBER_6;
	@:deprecated("Use KeyCode.NUMBER_7 instead") public static inline final NUMBER_7 = KeyCode.NUMBER_7;
	@:deprecated("Use KeyCode.NUMBER_8 instead") public static inline final NUMBER_8 = KeyCode.NUMBER_8;
	@:deprecated("Use KeyCode.NUMBER_9 instead") public static inline final NUMBER_9 = KeyCode.NUMBER_9;

	@:deprecated("Use KeyCode.NUMPAD_0 instead") public static inline final NUMPAD_0 = KeyCode.NUMPAD_0;
	@:deprecated("Use KeyCode.NUMPAD_1 instead") public static inline final NUMPAD_1 = KeyCode.NUMPAD_1;
	@:deprecated("Use KeyCode.NUMPAD_2 instead") public static inline final NUMPAD_2 = KeyCode.NUMPAD_2;
	@:deprecated("Use KeyCode.NUMPAD_3 instead") public static inline final NUMPAD_3 = KeyCode.NUMPAD_3;
	@:deprecated("Use KeyCode.NUMPAD_4 instead") public static inline final NUMPAD_4 = KeyCode.NUMPAD_4;
	@:deprecated("Use KeyCode.NUMPAD_5 instead") public static inline final NUMPAD_5 = KeyCode.NUMPAD_5;
	@:deprecated("Use KeyCode.NUMPAD_6 instead") public static inline final NUMPAD_6 = KeyCode.NUMPAD_6;
	@:deprecated("Use KeyCode.NUMPAD_7 instead") public static inline final NUMPAD_7 = KeyCode.NUMPAD_7;
	@:deprecated("Use KeyCode.NUMPAD_8 instead") public static inline final NUMPAD_8 = KeyCode.NUMPAD_8;
	@:deprecated("Use KeyCode.NUMPAD_9 instead") public static inline final NUMPAD_9 = KeyCode.NUMPAD_9;

	@:deprecated("Use KeyCode.A instead") public static inline final A = KeyCode.A;
	@:deprecated("Use KeyCode.B instead") public static inline final B = KeyCode.B;
	@:deprecated("Use KeyCode.C instead") public static inline final C = KeyCode.C;
	@:deprecated("Use KeyCode.D instead") public static inline final D = KeyCode.D;
	@:deprecated("Use KeyCode.E instead") public static inline final E = KeyCode.E;
	@:deprecated("Use KeyCode.F instead") public static inline final F = KeyCode.F;
	@:deprecated("Use KeyCode.G instead") public static inline final G = KeyCode.G;
	@:deprecated("Use KeyCode.H instead") public static inline final H = KeyCode.H;
	@:deprecated("Use KeyCode.I instead") public static inline final I = KeyCode.I;
	@:deprecated("Use KeyCode.J instead") public static inline final J = KeyCode.J;
	@:deprecated("Use KeyCode.K instead") public static inline final K = KeyCode.K;
	@:deprecated("Use KeyCode.L instead") public static inline final L = KeyCode.L;
	@:deprecated("Use KeyCode.M instead") public static inline final M = KeyCode.M;
	@:deprecated("Use KeyCode.N instead") public static inline final N = KeyCode.N;
	@:deprecated("Use KeyCode.O instead") public static inline final O = KeyCode.O;
	@:deprecated("Use KeyCode.P instead") public static inline final P = KeyCode.P;
	@:deprecated("Use KeyCode.Q instead") public static inline final Q = KeyCode.Q;
	@:deprecated("Use KeyCode.R instead") public static inline final R = KeyCode.R;
	@:deprecated("Use KeyCode.S instead") public static inline final S = KeyCode.S;
	@:deprecated("Use KeyCode.T instead") public static inline final T = KeyCode.T;
	@:deprecated("Use KeyCode.U instead") public static inline final U = KeyCode.U;
	@:deprecated("Use KeyCode.V instead") public static inline final V = KeyCode.V;
	@:deprecated("Use KeyCode.W instead") public static inline final W = KeyCode.W;
	@:deprecated("Use KeyCode.X instead") public static inline final X = KeyCode.X;
	@:deprecated("Use KeyCode.Y instead") public static inline final Y = KeyCode.Y;
	@:deprecated("Use KeyCode.Z instead") public static inline final Z = KeyCode.Z;

	@:deprecated("Use KeyCode.F1 instead") public static inline final F1 = KeyCode.F1;
	@:deprecated("Use KeyCode.F2 instead") public static inline final F2 = KeyCode.F2;
	@:deprecated("Use KeyCode.F3 instead") public static inline final F3 = KeyCode.F3;
	@:deprecated("Use KeyCode.F4 instead") public static inline final F4 = KeyCode.F4;
	@:deprecated("Use KeyCode.F5 instead") public static inline final F5 = KeyCode.F5;
	@:deprecated("Use KeyCode.F6 instead") public static inline final F6 = KeyCode.F6;
	@:deprecated("Use KeyCode.F7 instead") public static inline final F7 = KeyCode.F7;
	@:deprecated("Use KeyCode.F8 instead") public static inline final F8 = KeyCode.F8;
	@:deprecated("Use KeyCode.F9 instead") public static inline final F9 = KeyCode.F9;
	@:deprecated("Use KeyCode.F10 instead") public static inline final F10 = KeyCode.F10;
	@:deprecated("Use KeyCode.F11 instead") public static inline final F11 = KeyCode.F11;
	@:deprecated("Use KeyCode.F12 instead") public static inline final F12 = KeyCode.F12;
	@:deprecated("Use KeyCode.F13 instead") public static inline final F13 = KeyCode.F13;
	@:deprecated("Use KeyCode.F14 instead") public static inline final F14 = KeyCode.F14;
	@:deprecated("Use KeyCode.F15 instead") public static inline final F15 = KeyCode.F15;
	@:deprecated("Use KeyCode.F16 instead") public static inline final F16 = KeyCode.F16;
	@:deprecated("Use KeyCode.F17 instead") public static inline final F17 = KeyCode.F17;
	@:deprecated("Use KeyCode.F18 instead") public static inline final F18 = KeyCode.F18;
	@:deprecated("Use KeyCode.F19 instead") public static inline final F19 = KeyCode.F19;
	@:deprecated("Use KeyCode.F20 instead") public static inline final F20 = KeyCode.F20;
	@:deprecated("Use KeyCode.F21 instead") public static inline final F21 = KeyCode.F21;
	@:deprecated("Use KeyCode.F22 instead") public static inline final F22 = KeyCode.F22;
	@:deprecated("Use KeyCode.F23 instead") public static inline final F23 = KeyCode.F23;
	@:deprecated("Use KeyCode.F24 instead") public static inline final F24 = KeyCode.F24;

	@:deprecated("Use KeyCode.NUMPAD_MULT instead") public static inline final NUMPAD_MULT = KeyCode.NUMPAD_MULT;
	@:deprecated("Use KeyCode.NUMPAD_ADD instead") public static inline final NUMPAD_ADD = KeyCode.NUMPAD_ADD;
	@:deprecated("Use KeyCode.NUMPAD_ENTER instead") public static inline final NUMPAD_ENTER = KeyCode.NUMPAD_ENTER;
	@:deprecated("Use KeyCode.NUMPAD_SUB instead") public static inline final NUMPAD_SUB = KeyCode.NUMPAD_SUB;
	@:deprecated("Use KeyCode.NUMPAD_DOT instead") public static inline final NUMPAD_DOT = KeyCode.NUMPAD_DOT;
	@:deprecated("Use KeyCode.NUMPAD_DIV instead") public static inline final NUMPAD_DIV = KeyCode.NUMPAD_DIV;

	@:deprecated("Use KeyCode.MOUSE_LEFT instead") public static inline final MOUSE_LEFT = KeyCode.MOUSE_LEFT;
	@:deprecated("Use KeyCode.MOUSE_RIGHT instead") public static inline final MOUSE_RIGHT = KeyCode.MOUSE_RIGHT;
	@:deprecated("Use KeyCode.MOUSE_MIDDLE instead") public static inline final MOUSE_MIDDLE = KeyCode.MOUSE_MIDDLE;
	@:deprecated("Use KeyCode.MOUSE_BACK instead") public static inline final MOUSE_BACK = KeyCode.MOUSE_BACK;
	@:deprecated("Use KeyCode.MOUSE_FORWARD instead") public static inline final MOUSE_FORWARD = KeyCode.MOUSE_FORWARD;
	@:deprecated("Use KeyCode.MOUSE_WHEEL_UP instead") public static inline final MOUSE_WHEEL_UP = KeyCode.MOUSE_WHEEL_UP;
	@:deprecated("Use KeyCode.MOUSE_WHEEL_DOWN instead") public static inline final MOUSE_WHEEL_DOWN = KeyCode.MOUSE_WHEEL_DOWN;

	@:deprecated("Use KeyCode.KeyCode.LOC_LEFT instead") public static inline final LOC_LEFT = KeyCode.LOC_LEFT;
	@:deprecated("Use KeyCode.KeyCode.LOC_RIGHT instead") public static inline final LOC_RIGHT = KeyCode.LOC_RIGHT;
	@:deprecated("Use KeyCode.LSHIFT instead") public static inline final LSHIFT = KeyCode.LSHIFT;
	@:deprecated("Use KeyCode.RSHIFT instead") public static inline final RSHIFT = KeyCode.RSHIFT;
	@:deprecated("Use KeyCode.LCTRL instead") public static inline final LCTRL = KeyCode.LCTRL;
	@:deprecated("Use KeyCode.RCTRL instead") public static inline final RCTRL = KeyCode.RCTRL;
	@:deprecated("Use KeyCode.LALT instead") public static inline final LALT = KeyCode.LALT;
	@:deprecated("Use KeyCode.RALT instead") public static inline final RALT = KeyCode.RALT;

	static var initDone = false;
	static var keyPressed : Array<Int> = [];

	/**
		This enable the native key repeat behavior, and will
		report several times isPressed() in case a key is kept
		pressed for a long time if this is allowed by the target
		platform.
	**/
	public static var ALLOW_KEY_REPEAT = false;

	public static function isDown( code : KeyCode ) {
		return keyPressed[code] > 0;
	}

	public static inline function getFrame() {
		return hxd.Timer.frameCount + 2;
	}

	public static function isPressed( code : KeyCode ) {
		return keyPressed[code] == getFrame() - 1;
	}

	public static function isReleased( code : KeyCode ) {
		return keyPressed[code] == -getFrame() + 1;
	}

	public static function initialize() {
		if( initDone )
			dispose();
		initDone = true;
		keyPressed = [];
		Window.getInstance().addEventTarget(onEvent);
	}

	public static function dispose() {
		if( initDone ) {
			Window.getInstance().removeEventTarget(onEvent);
			initDone = false;
			keyPressed = [];
		}
	}

	static function onEvent( e : Event ) {
		switch( e.kind ) {
		case EKeyDown:
			if( !ALLOW_KEY_REPEAT && keyPressed[e.keyCode] > 0 ) return;
			keyPressed[e.keyCode] = getFrame();
		case EKeyUp:
			keyPressed[e.keyCode] = -getFrame();
		case EPush:
			if( e.button < 5 ) keyPressed[e.button] = getFrame();
		case ERelease:
			if( e.button < 5 ) keyPressed[e.button] = -getFrame();
		case EReleaseOutside:
			keyPressed = [];
		case EWheel:
			keyPressed[e.wheelDelta > 0 ? KeyCode.MOUSE_WHEEL_DOWN : KeyCode.MOUSE_WHEEL_UP] = getFrame();
		default:
		}
	}

	public static function getKeyName( keyCode : KeyCode ) {
		final c : Int = keyCode;
		final number0 : Int = KeyCode.NUMBER_0;
		final number9 : Int = KeyCode.NUMBER_9;
		final numpad0 : Int = KeyCode.NUMPAD_0;
		final numpad9 : Int = KeyCode.NUMPAD_9;
		final a : Int = KeyCode.A;
		final z : Int = KeyCode.Z;
		final f1 : Int = KeyCode.F1;
		final f24 : Int = KeyCode.F24;

		return switch( c ) {
			case KeyCode.BACKSPACE: "Backspace";
			case KeyCode.TAB: "Tab";
			case KeyCode.ENTER: "Enter";
			case KeyCode.SHIFT: "Shift";
			case KeyCode.CTRL: "Ctrl";
			case KeyCode.ALT: "Alt";
			case KeyCode.ESCAPE: "Escape";
			case KeyCode.SPACE: "Space";
			case KeyCode.PGUP: "PageUp";
			case KeyCode.PGDOWN: "PageDown";
			case KeyCode.END: "End";
			case KeyCode.HOME: "Home";
			case KeyCode.LEFT: "Left";
			case KeyCode.UP: "Up";
			case KeyCode.RIGHT: "Right";
			case KeyCode.DOWN: "Down";
			case KeyCode.INSERT: "Insert";
			case KeyCode.DELETE: "Delete";
			case KeyCode.NUMPAD_MULT: "NumPad*";
			case KeyCode.NUMPAD_ADD: "NumPad+";
			case KeyCode.NUMPAD_ENTER: "NumPadEnter";
			case KeyCode.NUMPAD_SUB: "NumPad-";
			case KeyCode.NUMPAD_DOT: "NumPad.";
			case KeyCode.NUMPAD_DIV: "NumPad/";
			case KeyCode.LSHIFT: "LShift";
			case KeyCode.RSHIFT: "RShift";
			case KeyCode.LCTRL: "LCtrl";
			case KeyCode.RCTRL: "RCtrl";
			case KeyCode.LALT: "LAlt";
			case KeyCode.RALT: "RAlt";
			case KeyCode.QWERTY_TILDE: "Tilde";
			case KeyCode.QWERTY_MINUS: "Minus";
			case KeyCode.QWERTY_EQUALS: "Equals";
			case KeyCode.QWERTY_BRACKET_LEFT: "BracketLeft";
			case KeyCode.QWERTY_BRACKET_RIGHT: "BracketRight";
			case KeyCode.QWERTY_SEMICOLON: "Semicolon";
			case KeyCode.QWERTY_QUOTE: "Quote";
			case KeyCode.QWERTY_BACKSLASH: "Backslash";
			case KeyCode.QWERTY_COMMA: "Comma";
			case KeyCode.QWERTY_PERIOD: "Period";
			case KeyCode.QWERTY_SLASH: "Slash";
			case KeyCode.INTL_BACKSLASH: "IntlBackslash";
			case KeyCode.LEFT_WINDOW_KEY: "LeftWindowKey";
			case KeyCode.RIGHT_WINDOW_KEY: "RightWindowKey";
			case KeyCode.CONTEXT_MENU: "ContextMenu";
			case KeyCode.PAUSE_BREAK: "PauseBreak";
			case KeyCode.CAPS_LOCK: "CapsLock";
			case KeyCode.SCROLL_LOCK: "ScrollLock";
			case KeyCode.NUM_LOCK: "NumLock";
			case KeyCode.MOUSE_LEFT: "MouseLeft";
			case KeyCode.MOUSE_MIDDLE: "MouseMiddle";
			case KeyCode.MOUSE_RIGHT: "MouseRight";
			case KeyCode.MOUSE_BACK: "Mouse3";
			case KeyCode.MOUSE_FORWARD: "Mouse4";
			default:
				if (c >= number0 && c <= number9)
					"" + (c - number0);
				else if (c >= numpad0 && c <= numpad9)
					"NumPad" + (c - numpad0);
				else if (c >= a && c <= z)
					String.fromCharCode("A".code + c - a);
				else if (c >= f1 && c <= f24)
					"F" + (c - f1 + 1);
				else
					null;
		}
	}

}
