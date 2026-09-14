package h2d;

/**
	A simple text push button with a label.
	Useful for fast construction of development UI, but lacks on configurability side.
**/
class TextButton extends h2d.Flow {
	/**
		Background color of the button in its default and disabled states.
	**/
	public var bgColor(default, set):Int = 0x404040;

	/**
		Background color of the button when hovered by the user.
	**/
	public var bgOverColor(default, set):Int = 0x606060;

	/**
		Background color of the button while being pressed by the user.
	**/
	public var bgPressColor(default, set):Int = 0x303030;

	/**
		Button label text color.
	**/
	public var textColor(default, set):Int = 0xffffff;

	/**
		When disabled, user interaction is ignored and the button is dimmed.
		It is still possible to trigger `onClick` manually from the code even if the button is disabled.
	**/
	public var enable(default, set):Bool = true;

	/**
		Button label text.
	**/
	public var text(default, set):String = "";

	var tf:h2d.Text;
	var over:Bool;
	var pressed:Bool;

	/**
		Create a new TextButton instance.
		@param parent An optional parent `h2d.Object` instance to which TextButton adds itself if set.
	**/
	public function new(?parent) {
		super(parent);

		padding = 5;
		verticalAlign = Middle;

		tf = new h2d.Text(hxd.res.DefaultFont.get(), this);

		backgroundTile = h2d.Tile.fromColor(bgColor);

		enableInteractive = true;

		interactive.cursor = Button;

		interactive.onOver = function(_) {
			if (!enable)
				return;

			over = true;

			updateBackground();
		}

		interactive.onOut = function(_) {
			over = false;
			pressed = false;

			updateBackground();
		}

		interactive.onPush = function(e) {
			if (!enable)
				return;

			if (e.kind == EPush) {
				pressed = true;

				updateBackground();
			} else if (e.kind == ERelease) {
				pressed = false;

				updateBackground();
			}
		}

		interactive.onReleaseOutside = function(_) {
			over = false;
			pressed = false;

			updateBackground();
		}

		interactive.onClick = function(_) {
			if (enable)
				onClick();
		}

		enable = true;
		text = "";
	}

	function updateBackground() {
		backgroundTile = h2d.Tile.fromColor(!enable || !over ? bgColor : pressed ? bgPressColor : bgOverColor);
	}

	function set_enable(b:Bool) {
		alpha = b ? 1 : 0.6;

		if (tf != null)
			updateBackground();

		return enable = b;
	}

	function set_text(str:String) {
		if (tf != null)
			tf.text = str;

		needReflow = true;

		return text = str;
	}

	function set_textColor(c) {
		if (tf != null)
			tf.textColor = c;

		return textColor = c;
	}

	function set_bgColor(c:Int) {
		bgColor = c;

		if (tf != null)
			updateBackground();

		return c;
	}

	function set_bgOverColor(c:Int) {
		bgOverColor = c;

		if (tf != null)
			updateBackground();

		return c;
	}

	function set_bgPressColor(c:Int) {
		bgPressColor = c;

		if (tf != null)
			updateBackground();

		return c;
	}

	/**
		Sent when the button is clicked by the user while enabled.
	**/
	public dynamic function onClick() {}
}