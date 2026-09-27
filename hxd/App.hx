package hxd;

/**
	Base class for a Heaps application.

	This class contains code to set up a typical Heaps app,
	including 3D and 2D scene, input, update and loops.

	It's designed to be a base class for an application entry point,
	and provides several methods for overriding, in which we can plug
	custom code. See API documentation for more information.
**/
class App implements h3d.IDrawable {

	/**
		Rendering engine.
	**/
	public var engine(default,null) : h3d.Engine;

	/**
		Default 3D scene.
	**/
	public var s3d(default,null) : h3d.scene.Scene;

	/**
		Default 2D scene.
	**/
	public var s2d(default,null) : h2d.Scene;

	/**
		Input event listener collection.
		Both 2D and 3D scenes are added to it by default.
	**/
	public var sevents(default,null) : hxd.SceneEvents;

	var isDisposed : Bool;

	public function new() {
		var engine = h3d.Engine.getCurrent();
		if( engine != null ) {
			this.engine = engine;
			engine.onReady = setup;
			haxe.Timer.delay(setup, 0);
		} else {
			HSystem.start(() -> {
				this.engine = engine = @:privateAccess new h3d.Engine();
				engine.onReady = setup;
				engine.init();
			});
		}
	}

	/**
		Screen resize callback.

		By default does nothing. Override this method to provide custom on-resize logic.
	**/
	@:dox(show)
	private function onResize() {
	}

	/**
		Switch either the 2d or 3d scene with another instance, both in terms of rendering and event handling.
		If you call disposePrevious, it will call dispose() on the previous scene.
	**/
	public function setScene( scene : hxd.SceneEvents.InteractiveScene, disposePrevious = true ) {
		var new2D = Std.downcast(scene, h2d.Scene);
		var new3D = Std.downcast(scene, h3d.scene.Scene);
		if( new2D != null ) {
			sevents.removeScene(s2d);
			sevents.addScene(scene, 0);
		} else if( new3D != null ) {
			sevents.removeScene(s3d);
			sevents.addScene(scene);
		}
		if( disposePrevious ) {
			if( new2D != null )
				s2d.dispose();
			else if( new3D != null )
				s3d.dispose();
			else
				throw "Can't dispose previous scene";
		}
		if( new2D != null )
			this.s2d = new2D;
		if( new3D != null )
			this.s3d = new3D;
	}

	/**
	 * When using multiple hxd.App, this will set the current App (the one on which update etc. will be called)
	**/
	public function setCurrent() {
		engine = h3d.Engine.getCurrent(); // if was changed
		isDisposed = false;
		engine.onReady = staticHandler; // in case we have another pending app
		engine.onContextLost = onContextLost;
		engine.onResized = function() {
			if( s2d == null ) return; // if disposed
			s2d.checkResize();
			onResize();
		};
		HSystem.setLoop(mainLoop);
	}

	private function onContextLost() {
		s3d?.onContextLost();
	}

	private function setScene2D( s2d : h2d.Scene, disposePrevious = true ) {
		sevents.removeScene(this.s2d);
		sevents.addScene(s2d,0);
		if( disposePrevious )
			this.s2d.dispose();
		this.s2d = s2d;
		s2d.mark = mark;
	}

	private function setScene3D( s3d : h3d.scene.Scene, disposePrevious = true ) {
		sevents.removeScene(this.s3d);
		sevents.addScene(s3d);
		if ( disposePrevious )
			this.s3d.dispose();
		this.s3d = s3d;
	}

	public function render(e:h3d.Engine) {
		var trace = NMBTrace.enabled();
		if( trace ) NMBTrace.begin("heaps", "Scene 3D");
		try {
			s3d.render(e);
		} catch(e:Dynamic) {
			if( trace ) NMBTrace.end("heaps");
			throw e;
		}
		if( trace ) NMBTrace.end("heaps");
		if( trace ) NMBTrace.begin("heaps", "Scene 2D");
		try {
			s2d.render(e);
		} catch(e:Dynamic) {
			if( trace ) NMBTrace.end("heaps");
			throw e;
		}
		if( trace ) NMBTrace.end("heaps");
	}

	private function mark(name : String) {
		s3d.mark(name);
	}

	private function setup() {
		var initDone = false;
		engine.onReady = staticHandler;
		engine.onContextLost = onContextLost;
		engine.onResized = function() {
			if( s2d == null ) return; // if disposed
			s2d.checkResize();
			if( initDone ) onResize();
		};
		s3d = new h3d.scene.Scene();
		s2d = new h2d.Scene();
		s2d.mark = mark;
		sevents = new hxd.SceneEvents();
		sevents.addScene(s2d);
		sevents.addScene(s3d);
		loadAssets(function() {
			initDone = true;
			init();
			hxd.Timer.skip();
			mainLoop();
			HSystem.setLoop(mainLoop);
			HSystem.presentFrame(engine);
			hxd.Key.initialize();
		});
	}

	private function dispose() {
		engine.onResized = staticHandler;
		engine.onContextLost = staticHandler;
		isDisposed = true;
		s2d?.dispose();
		s3d?.dispose();
		sevents?.dispose();
	}

	/**
		Load assets asynchronously.

		Called during application setup. By default immediately calls `onLoaded`.
		Override this method to provide asynchronous asset loading logic.

		@param onLoaded a callback that should be called by the overriden
				method when loading is complete
	**/
	@:dox(show)
	private function loadAssets( onLoaded : Void->Void ) {
		onLoaded();
	}

	/**
		Initialize application.

		Called during application setup after `loadAssets` completed.
		By default does nothing. Override this method to provide application initialization logic.
	**/
	@:dox(show)
	private function init() {
	}

	private function mainLoop() {
		var trace = NMBTrace.enabled();
		if( trace ) NMBTrace.begin("heaps", "Heaps Frame");
		try {
			if( trace ) NMBTrace.begin("heaps", "Timer");
			try {
				hxd.Timer.update();
			} catch(e:Dynamic) {
				if( trace ) NMBTrace.end("heaps");
				throw e;
			}
			if( trace ) NMBTrace.end("heaps");
			if( trace ) {
				NMBTrace.counter("heaps.frame", "Frame Time", hxd.Timer.elapsedTime * 1000);
				NMBTrace.counter("heaps.frame", "FPS", hxd.Timer.fps());
				NMBTrace.counter("heaps.frame", "Raw Frame Delta", hxd.Timer.elapsedTime * 1000);
			}
			if( trace ) NMBTrace.begin("heaps", "Events");
			try {
				sevents.checkEvents();
			} catch(e:Dynamic) {
				if( trace ) NMBTrace.end("heaps");
				throw e;
			}
			if( trace ) NMBTrace.end("heaps");
			if( isDisposed ) {
				if( trace ) NMBTrace.end("heaps");
				return;
			}
			if( trace ) NMBTrace.begin("heaps", "Game Update");
			try {
				update(hxd.Timer.dt);
			} catch(e:Dynamic) {
				if( trace ) NMBTrace.end("heaps");
				throw e;
			}
			if( trace ) NMBTrace.end("heaps");
			if( isDisposed ) {
				if( trace ) NMBTrace.end("heaps");
				return;
			}
			final dt = hxd.Timer.dt; // fetch again in case it's been modified in update()
			if( trace ) NMBTrace.counter("heaps.frame", "Game DT", dt * 1000);
			s2d?.setElapsedTime(dt);
			s3d?.setElapsedTime(dt);
			if( trace ) NMBTrace.begin("heaps", "Render");
			try {
				var rendered = engine.render(this);
				if( trace && rendered ) {
					NMBTrace.counter("heaps.render", "Draw Calls", engine.drawCalls);
					NMBTrace.counter("heaps.render", "Triangles", engine.drawTriangles);
					NMBTrace.counter("heaps.render", "Shader Switches", engine.shaderSwitches);
					NMBTrace.counter("heaps.render", "Dispatches", engine.dispatches);
					engine.mem.traceCounters();
				}
			} catch(e:Dynamic) {
				if( trace ) NMBTrace.end("heaps");
				throw e;
			}
			if( trace ) NMBTrace.end("heaps");
		} catch(e:Dynamic) {
			if( trace ) NMBTrace.end("heaps");
			throw e;
		}
		if( trace ) NMBTrace.end("heaps");
	}

	/**
		Update application.

		Called each frame right before rendering.
		First call is done after the application is set up (so `loadAssets` and `init` are called).

		@param dt Time elapsed since last frame, normalized.
	**/
	@:dox(show)
	private function update( dt : Float ) {
	}

	static function staticHandler() {}

}
