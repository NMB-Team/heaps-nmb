class Fullscreen extends SampleApp {

	override function init() {
		super.init();
		addButton("Toggle FullScreen", function() {
			engine.fullScreen = !engine.fullScreen;
		});
		addButton("Borderless FullScreen", function() {
			engine.fullScreenMode = Borderless;
			engine.fullScreen = true;
		});
		addButton("Exclusive FullScreen", function() {
			engine.fullScreenMode = Fullscreen;
			engine.fullScreen = true;
		});
		addButton("Error Message Test", function() throw "Error!");

		if( hxd.System.allowTimeout )
			addButton("Infinite loop test", function() while(true) {});
	}

	static function main() {
		new Fullscreen();
	}
}
