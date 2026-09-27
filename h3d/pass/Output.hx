package h3d.pass;

@:access(h3d.mat.Pass)
class Output {

	public var name(default, null) : String;
	var ctx : h3d.scene.RenderContext;
	var output : OutputShader;
	var globals(get, never) : hxsl.Globals;
	var defaultSort = new SortByMaterial().sort;

	inline function get_globals() return ctx.globals;

	public function new(name, ?output) {
		this.name = name;
		this.output = new OutputShader(output);
	}

	public function setContext( ctx ) {
		this.ctx = ctx;
	}

	public function dispose() {
	}

	function processShaders( p : h3d.pass.PassObject, shaders : hxsl.ShaderList ) {
		var p = ctx.extraShaders;
		while( p != null ) {
			shaders = ctx.allocShaderList(p.s, shaders);
			p = p.next;
		}
		return shaders;
	}

	@:access(h3d.scene)
	function setupShaders( passes : h3d.pass.PassList ) {
		var lightInit = false;
		for( p in passes ) {
			var shaders = p.pass.getShadersRec();
			shaders = processShaders(p, shaders);
			if( p.pass.enableLights && ctx.lightSystem != null ) {
				if( !lightInit ) {
					ctx.lightSystem.initGlobals(globals);
					lightInit = true;
				}
				shaders = ctx.lightSystem.computeLight(p.obj, shaders);
			}
			p.shader = output.compileShaders(ctx.globals, shaders, p.pass.batchMode ? Batch : Default);
			p.shaders = shaders;
			var t = p.shader.fragment.textures;
			if( t == null || t.type.match(TArray(_)) )
				p.texture = 0;
			else {
				var t : h3d.mat.Texture = ctx.getParamValue(t, shaders, true);
				p.texture = t == null ? 0 : t.id;
			}
		}
	}

	inline function log( str : String ) {
		ctx.engine.driver.log(str);
	}

	function drawObject( p : h3d.pass.PassObject ) {
		ctx.drawPass = p;
		if( ctx.useReverseDepth ) {
			p.pass.reverseDepthTest();
			ctx.engine.selectMaterial(p.pass);
			p.pass.reverseDepthTest();
		} else {
			ctx.engine.selectMaterial(p.pass);
		}
		p.obj.drawn = true;
		@:privateAccess p.obj.draw(ctx);
	}

	public static var onShaderError : Dynamic -> PassObject -> Void;

	@:access(h3d.scene)
	public function draw( passes : h3d.pass.PassList, ?sort : h3d.pass.PassList -> Void ) {
		if( passes.isEmpty() )
			return;
		var trace = hxd.NMBTrace.enabled();
		var passName = @:privateAccess passes.current.pass.name;
		var engine = ctx.engine;
		var drawCalls = 0, shaderSwitches = 0, dispatches = 0;
		var triangles = 0.;
		if( trace ) {
			drawCalls = engine.drawCalls;
			triangles = engine.drawTriangles;
			shaderSwitches = engine.shaderSwitches;
			dispatches = engine.dispatches;
		}
		ctx.engine.driver.beginEvent(passName);
		if( trace ) hxd.NMBTrace.begin("heaps.pass", passName);
		if( trace && engine.gpuTrace == null ) engine.gpuTrace = new h3d.impl.GpuTrace(engine.driver);
		var gpuQuery = trace ? engine.gpuTrace.begin(passName, ctx.frame) : null;
		try {
			#if sceneprof
			h3d.impl.SceneProf.begin('draw_${passName}', ctx.frame);
			#end
			ctx.setupTarget();
			setupShaders(passes);
			if( sort == null )
				defaultSort(passes);
			else
				sort(passes);
			var buf = ctx.shaderBuffers, prevShader = null;
			for( p in passes ) {
				#if sceneprof h3d.impl.SceneProf.mark(p.obj); #end
				ctx.globalPreviousModelView = p.obj.prevAbsPos ?? p.obj.absPos;
				ctx.globalModelView = p.obj.absPos;
				if( p.shader.hasGlobal(ctx.globalModelViewInverse_id.toInt()) )
					ctx.globalModelViewInverse = p.obj.getInvPos();
				if( prevShader != p.shader ) {
					prevShader = p.shader;
					if( onShaderError != null ) {
						try {
							ctx.engine.selectShader(p.shader);
						} catch(e) {
							onShaderError(e.message, p);
							continue;
						}
					} else {
						ctx.engine.selectShader(p.shader);
					}
					buf.grow(p.shader);
					ctx.fillGlobals(buf, p.shader);
					ctx.engine.uploadShaderBuffers(buf, Globals);
				}
				if( !p.pass.dynamicParameters ) {
					ctx.fillParams(buf, p.shader, p.shaders);
					ctx.engine.uploadInstanceShaderBuffers(buf);
				}
				drawObject(p);
			}
		} catch(e:Dynamic) {
			if( gpuQuery != null ) engine.gpuTrace.end(gpuQuery);
			ctx.engine.driver.endEvent();
			if( trace ) hxd.NMBTrace.end("heaps.pass");
			#if sceneprof h3d.impl.SceneProf.end(); #end
			throw e;
		}
		if( trace ) {
			hxd.NMBTrace.counter("heaps.pass", "Pass Draw Calls", engine.drawCalls - drawCalls);
			hxd.NMBTrace.counter("heaps.pass", "Pass Triangles", engine.drawTriangles - triangles);
			hxd.NMBTrace.counter("heaps.pass", "Pass Shader Switches", engine.shaderSwitches - shaderSwitches);
			hxd.NMBTrace.counter("heaps.pass", "Pass Dispatches", engine.dispatches - dispatches);
		}
		ctx.engine.driver.endEvent();
		if( gpuQuery != null ) engine.gpuTrace.end(gpuQuery);
		if( trace ) hxd.NMBTrace.end("heaps.pass");
		#if sceneprof h3d.impl.SceneProf.end(); #end
		ctx.nextPass();
	}
}
