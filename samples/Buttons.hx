package samples;

import h2d.Flow;
import h2d.Text;

/**
	Demonstrates the h2d.TextButton component.
	Click the first button to increment the counter.
	The second button toggles the first one enabled/disabled.
**/
class Buttons extends hxd.App {
	var root:Flow;
	var label:Text;
	var counter = 0;

	override function init() {
		root = new Flow(s2d);
		root.layout = Vertical;
		root.verticalSpacing = 10;
		root.horizontalAlign = Middle;

		label = new Text(hxd.res.DefaultFont.get(), root);
		label.text = "Clicked 0 times";
		label.setScale(2);

		var clickBtn = new h2d.TextButton(root);
		clickBtn.text = "Click me!";
		clickBtn.onClick = function() {
			counter++;

			label.text = 'Clicked $counter times';
		}

		var toggleBtn = new h2d.TextButton(root);
		toggleBtn.text = "Disable previous";
		toggleBtn.onClick = function() {
			clickBtn.enable = !clickBtn.enable;
			toggleBtn.text = clickBtn.enable ? "Disable previous" : "Enable previous";
		}

		var resetBtn = new h2d.TextButton(root);
		resetBtn.text = "Reset counter";
		resetBtn.bgColor = 0x1f3a5f;
		resetBtn.bgOverColor = 0x2d5a8a;
		resetBtn.bgPressColor = 0x14263c;
		resetBtn.textColor = 0xffcc00;
		resetBtn.onClick = function() {
			counter = 0;
			label.text = "Clicked 0 times";
		}

		var quitBtn = new h2d.TextButton(root);
		quitBtn.text = "Quit";
		quitBtn.bgColor = 0xc10a0a;
		quitBtn.bgOverColor = 0xdb3232;
		quitBtn.bgPressColor = 0xc10404;
		quitBtn.onClick = function() {
			hxd.System.exit();
		}

		onResize();
	}

	override function onResize() {
		super.onResize();

		root.x = Std.int(s2d.width * 0.5 - root.outerWidth * 0.5);
		root.y = Std.int(s2d.height * 0.5 - root.outerHeight * 0.5);
	}

	static function main() {
		hxd.Res.initEmbed();

		new Buttons();
	}
}