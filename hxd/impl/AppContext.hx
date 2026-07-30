package hxd.impl;

import hxd.System as HSystem;
import hxd.Window as HWindow;

#if hl
/**
	Create an app context to allow multiple apps to run in parallel.
	Requires compilation with -D multidriver
**/
class AppContext {

	static var contexts : Array<AppContext> = [];

	public var win : HWindow;
	public var engine : h3d.Engine;
	public var app : hxd.App;

	public function new(app) {
		#if !multidriver
		throw "Needs -D multidriver";
		#end
		this.app = app;
		win = HWindow.getInstance();
		win.onClose = function() {
			@:privateAccess app.dispose();
			return true;
		};
		engine = h3d.Engine.getCurrent();
		var curReady = engine.onReady;
		engine.onReady = function() {
			curReady();
			reset();
			HSystem.setLoop(run);
		};
		contexts.push(this);
		reset();
	}

	public function update() {
		if( app.sevents == null )
			return;
		engine.setCurrent();
		@:privateAccess {
			HSystem.loopFunc = app.mainLoop;
			HSystem.mainLoop();
			HSystem.loopFunc = run;
		}
		reset();
	}

	static function run() {
		for( c in contexts )
			c.update();
	}

	public static function reset() @:privateAccess {
		h3d.Engine.CURRENT = null;
		HWindow.inst = null;
	}

	public static function set( app : hxd.App ) {
		for( c in contexts )
			if( c.app == app )
				c.engine.setCurrent();
	}

}
#end
