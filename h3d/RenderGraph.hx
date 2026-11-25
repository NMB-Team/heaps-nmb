package h3d;

import h3d.mat.Texture;
import h3d.mat.Data.TextureFormat;

enum abstract GraphAccess(Int) {
	var Read = 1;
	var Write = 2;
	var ReadWrite = 3;

	public inline function reads() return (this & 1) != 0;
	public inline function writes() return (this & 2) != 0;
}

@:allow(h3d.RenderGraph)
class GraphResource {
	final owner : RenderGraph;
	final id : Int;
	final spec : Null<{ width : Int, height : Int, format : TextureFormat }>;
	var texture : Texture;
	final buffer : Buffer;

	function new(owner, id, texture, buffer, ?spec) {
		this.owner = owner;
		this.id = id;
		this.texture = texture;
		this.buffer = buffer;
		this.spec = spec;
	}
}

private typedef Use = {
	var resource : GraphResource;
	var access : GraphAccess;
	var mip : Int;
	var layer : Int;
	var passId : Int;
}

@:allow(h3d.RenderGraph)
class GraphPass {
	public final name : String;

	final owner : RenderGraph;
	final id : Int;
	final record : (Engine, RenderGraph) -> Void;
	final target : GraphResource;
	final clear : Null<Int>;
	final mip : Int;
	final layer : Int;
	final sideEffect : Bool;
	final external : Bool;
	final uses : Array<Use> = [];
	final after : Array<GraphPass> = [];

	function new(owner, id, name, record, target, clear, mip, layer, sideEffect, external) {
		this.owner = owner;
		this.id = id;
		this.name = name;
		this.record = record;
		this.target = target;
		this.clear = clear;
		this.mip = mip;
		this.layer = layer;
		this.sideEffect = sideEffect;
		this.external = external;
	}
}

private typedef ImportRange = {
	var resource : GraphResource;
	var firstMip : Int;
	var lastMip : Int;
	var lastLayer : Int;
}

private typedef Step = {
	var pass : GraphPass;
	var barrier : Bool;
	var beginTarget : Bool;
	var endTarget : Bool;
}

private typedef Schedule = {
	var steps : Array<Step>;
	var imports : Array<ImportRange>;
	var slots : Array<GraphResource>;
	var physical : Array<Int>;
}

/**
	A reusable single-queue schedule for explicitly declared work. Execute from
	an active Engine render callback. Callbacks run on the render thread and
	must balance their target stack and use the normal Engine/driver APIs.
	Declared writes replace the specified subresources. Use ReadWrite for
	partial updates. Mark other observable work as a side effect, and use an
	external pass when its resource usage is unknown.
**/
class RenderGraph {
	final engine : Engine;
	final driver : h3d.impl.driver.Driver;
	final aliasTargets : Bool;
	final resources : Array<GraphResource> = [];
	final passes : Array<GraphPass> = [];
	final textures : Map<Texture, GraphResource> = [];
	final buffers : Map<Buffer, GraphResource> = [];
	var swapchain : GraphResource;
	var schedule : Schedule;
	final physicalTextures : Array<Texture> = [];
	var current : GraphPass;
	var executing = false;
	var disposed = false;

	public function new(engine : Engine, aliasTargets = false) {
		this.engine = engine;
		this.driver = engine.driver;
		this.aliasTargets = aliasTargets && driver.supportsRenderGraphAliasing();
	}

	function checkMutable() {
		if( disposed || executing ) throw "Cannot edit this render graph";
	}

	/** Use the same import for all reads and writes to a persistent or history resource. */
	public function importTexture(texture : Texture) : GraphResource {
		checkMutable();
		if( texture == null || @:privateAccess texture.mem != engine.mem )
			throw "Render graph texture belongs to a different engine";

		var resource = textures.get(texture);
		if( resource == null ) {
			resource = new GraphResource(this, resources.length, texture, null);
			textures.set(texture, resource);
			resources.push(resource);
			schedule = null;
		}
		return resource;
	}

	public function importBuffer(buffer : Buffer) : GraphResource {
		checkMutable();
		if( buffer == null || @:privateAccess buffer.engine != engine )
			throw "Render graph buffer belongs to a different engine";

		var resource = buffers.get(buffer);
		if( resource == null ) {
			resource = new GraphResource(this, resources.length, null, buffer);
			buffers.set(buffer, resource);
			resources.push(resource);
			schedule = null;
		}
		return resource;
	}

	/** Rebind an imported texture between executions without recompiling. */
	public function rebind(resource : GraphResource, texture : Texture) {
		checkMutable();
		if( !containsResource(resource) || resource.texture == null || texture == null
			|| @:privateAccess texture.mem != engine.mem )
			throw "Invalid render graph texture rebind";
		if( resource.texture == texture ) return;
		if( textures.exists(texture) ) throw "Texture already has a render graph import";

		textures.remove(resource.texture);
		textures.set(texture, resource);
		resource.texture = texture;
	}

	/** Exchange two texture imports, for example the current and previous history textures. */
	public function swapTextures(first : GraphResource, second : GraphResource) {
		checkMutable();
		if( !containsResource(first) || !containsResource(second) || first.texture == null || second.texture == null )
			throw "Invalid render graph texture swap";

		final previous = first.texture;
		first.texture = second.texture;
		second.texture = previous;
		textures.set(first.texture, first);
		textures.set(second.texture, second);
	}

	/** The current back buffer is resolved by the driver on each execution. */
	public function backBuffer() : GraphResource {
		checkMutable();
		if( swapchain == null ) {
			swapchain = new GraphResource(this, resources.length, null, null);
			resources.push(swapchain);
			schedule = null;
		}
		return swapchain;
	}

	/** A single-sample color target. Its first live use must be a graph-owned clear. */
	public function transientTarget(width : Int, height : Int, format : TextureFormat = RGBA) : GraphResource {
		checkMutable();
		if( width <= 0 || height <= 0 ) throw "Invalid transient render target size";
		switch( format ) {
		case Depth16, Depth24, Depth24Stencil8, Depth32, Depth32Stencil8:
			throw "Transient color target requires a color format";
		default:
		}

		final resource = new GraphResource(this, resources.length, null, null, { width : width, height : height, format : format });
		resources.push(resource);
		schedule = null;
		return resource;
	}

	/** A custom pass may record graphics, compute or transfer work through Heaps. */
	public function addPass(name : String, record : (Engine, RenderGraph) -> Void, sideEffect = false, external = false) : GraphPass {
		checkMutable();
		if( record == null ) throw "A custom render pass requires a callback";
		return append(new GraphPass(this, passes.length, name, record, null, null, 0, 0, sideEffect, external));
	}

	/** Compatible adjacent color passes share an Engine target scope. */
	public function addColorPass(name : String, target : GraphResource, ?clear : Int, ?record : (Engine, RenderGraph) -> Void,
			mip = 0, layer = 0, sideEffect = false) : GraphPass {
		checkMutable();
		if( !containsResource(target) || target.buffer != null || mip < 0 || layer < 0 )
			throw "Invalid render graph color attachment";
		if( record == null && clear == null ) throw "A color pass requires a clear or a callback";
		if( target == swapchain && (mip != 0 || layer != 0) ) throw "Invalid back buffer subresource";

		final pass = new GraphPass(this, passes.length, name, record, target, clear, mip, layer, sideEffect, false);
		pass.uses.push({ resource : target, access : clear == null ? ReadWrite : Write, mip : mip, layer : layer, passId : pass.id });
		return append(pass);
	}

	function append(pass : GraphPass) {
		passes.push(pass);
		schedule = null;
		return pass;
	}

	/** -1 covers all mips or layers. Buffers are tracked as whole resources. */
	public function use(pass : GraphPass, resource : GraphResource, access : GraphAccess, mip = -1, layer = -1) {
		checkMutable();
		if( !containsPass(pass) || !containsResource(resource) || mip < -1 || layer < -1 )
			throw "Invalid render graph resource declaration";
		if( resource == swapchain || (resource.buffer != null && (mip != -1 || layer != -1)) )
			throw "Invalid resource range for a render graph declaration";
		if( access != Read && access != Write && access != ReadWrite ) throw "Invalid render graph access";
		if( pass.target != null && (access.writes() || (pass.target == resource && !driver.supportsDisjointRenderGraphViews())) )
			throw "Use a custom pass for attachment feedback or non-attachment writes";

		final use : Use = { resource : resource, access : access, mip : mip, layer : layer, passId : pass.id };
		for( other in pass.uses )
			if( overlaps(use, other) )
				throw "Overlapping uses in one pass must be declared together";
		pass.uses.push(use);
		schedule = null;
	}

	public function dependsOn(pass : GraphPass, predecessor : GraphPass) {
		checkMutable();
		if( !containsPass(pass) || !containsPass(predecessor) || pass == predecessor )
			throw "Invalid render graph dependency";

		if( pass.after.indexOf(predecessor) < 0 ) pass.after.push(predecessor);
		schedule = null;
	}

	/** Drop all declarations while keeping the graph bound to the same engine. */
	public function reset() {
		checkMutable();
		releaseTargets();
		resources.resize(0);
		passes.resize(0);
		textures.clear();
		buffers.clear();
		swapchain = null;
		schedule = null;
	}

	inline function containsResource(resource : GraphResource) {
		return resource != null && resource.owner == this && resources[resource.id] == resource;
	}

	inline function containsPass(pass : GraphPass) {
		return pass != null && pass.owner == this && passes[pass.id] == pass;
	}

	static inline function overlaps(a : Use, b : Use) {
		return a.resource == b.resource && (a.mip < 0 || b.mip < 0 || a.mip == b.mip)
			&& (a.layer < 0 || b.layer < 0 || a.layer == b.layer);
	}

	static inline function covers(a : Use, b : Use) {
		return (a.mip < 0 || a.mip == b.mip) && (a.layer < 0 || a.layer == b.layer);
	}

	static function addEdge(from : Int, to : Int, outgoing : Array<Array<Int>>, indegree : Array<Int>) {
		outgoing[from].push(to);
		indegree[to]++;
	}

	/** Force a cold schedule rebuild. Execute compiles lazily after declaration changes. */
	public function compile() {
		checkMutable();
		final outgoing = [for( _ in passes ) new Array<Int>()];
		final required = [for( _ in passes ) new Array<Int>()];
		final indegree = [for( _ in passes ) 0];
		final history = [for( _ in resources ) new Array<Use>()];
		final live = [for( _ in passes ) false];
		final roots = [];
		var lastExternal = -1;
		var lastObservable = -1;

		for( pass in passes ) {
			for( dependency in pass.after ) {
				addEdge(dependency.id, pass.id, outgoing, indegree);
				required[pass.id].push(dependency.id);
			}
			if( pass.external ) {
				for( i in lastExternal + 1...pass.id ) {
					addEdge(i, pass.id, outgoing, indegree);
					required[pass.id].push(i);
				}
			}
			if( lastExternal >= 0 ) addEdge(lastExternal, pass.id, outgoing, indegree);
			if( pass.external ) lastExternal = pass.id;

			var observable = pass.external || pass.sideEffect;
			for( use in pass.uses ) {
				if( use.access.writes() && use.resource.spec == null ) observable = true;

				final prior = history[use.resource.id];
				final needsProducer = use.access.reads();
				var i = prior.length;
				while( i > 0 ) {
					final prev = prior[--i];
					if( prev.passId == pass.id || !overlaps(prev, use) ) continue;
					if( use.access.writes() || prev.access.writes() )
						addEdge(prev.passId, pass.id, outgoing, indegree);
					if( prev.access.writes() ) {
						if( needsProducer ) required[pass.id].push(prev.passId);
						if( covers(prev, use) ) break;
					}
				}
				prior.push(use);
			}
			if( observable ) {
				if( !pass.external && lastObservable >= 0 && lastObservable != lastExternal )
					addEdge(lastObservable, pass.id, outgoing, indegree);
				lastObservable = pass.id;
				roots.push(pass.id);
			}
		}

		while( roots.length > 0 ) {
			final id = roots.pop();
			if( live[id] ) continue;
			live[id] = true;
			for( pred in required[id] ) roots.push(pred);
		}

		final ordered = [];
		var visited = 0;
		var next = 0;
		while( next < passes.length ) {
			if( indegree[next] != 0 ) {
				next++;
				continue;
			}
			final id = next;
			indegree[id] = -1;
			visited++;
			if( live[id] ) ordered.push(passes[id]);
			next++;
			for( successor in outgoing[id] )
				if( --indegree[successor] == 0 && successor < next ) next = successor;
		}
		if( visited != passes.length ) throw "Render graph contains a dependency cycle";

		final compiled = plan(ordered, lastExternal < 0);
		var keep = 0;
		while( keep < physicalTextures.length && keep < compiled.slots.length ) {
			final current = physicalTextures[keep];
			final next = compiled.slots[keep].spec;
			if( current.width != next.width || current.height != next.height || !Type.enumEq(current.format, next.format) )
				break;
			keep++;
		}

		releaseTargets(keep);
		schedule = compiled;
	}

	function plan(ordered : Array<GraphPass>, aliasSafe : Bool) : Schedule {
		final slots : Array<GraphResource> = [];
		final physical = [for( _ in resources ) -1];
		final lastUse = [for( _ in resources ) -1];
		final slotEnd = [];
		final imports : Array<ImportRange> = [];
		final importById : Array<ImportRange> = [];
		importById.resize(resources.length);
		final steps : Array<Step> = [];
		final customUse = [for( _ in resources ) false];
		final slotReusable = [];
		var previousCustom = false;
		var previous : Step = null;

		for( i => pass in ordered )
			for( use in pass.uses ) {
				lastUse[use.resource.id] = i;
				if( pass.target == null ) customUse[use.resource.id] = true;
			}

		for( i => pass in ordered ) {
			final custom = pass.target == null;
			final barrier = custom || previousCustom;
			previousCustom = custom;
			for( use in pass.uses ) {
				final resource = use.resource;
				if( resource.spec == null ) {
					if( resource == swapchain ) continue;
					final range = importById[resource.id];
					if( range == null ) {
						final span = { resource : resource, firstMip : use.mip, lastMip : use.mip, lastLayer : use.layer };
						importById[resource.id] = span;
						imports.push(span);
					} else {
						if( use.mip >= 0 && (range.firstMip < 0 || use.mip < range.firstMip) ) range.firstMip = use.mip;
						if( use.mip > range.lastMip ) range.lastMip = use.mip;
						if( use.layer > range.lastLayer ) range.lastLayer = use.layer;
					}
				} else if( physical[resource.id] < 0 ) {
					if( pass.target != resource || pass.clear == null || pass.mip != 0 || pass.layer != 0 )
						throw 'Transient target first use must be a full clear in pass ${pass.name}';

					var slot = -1;
					if( aliasTargets && aliasSafe && !customUse[resource.id] )
						for( candidate => other in slots )
							if( slotReusable[candidate] && slotEnd[candidate] < i && other.spec.width == resource.spec.width
								&& other.spec.height == resource.spec.height && Type.enumEq(other.spec.format, resource.spec.format) ) {
								slot = candidate;
								break;
							}

					if( slot < 0 ) {
						slot = slots.length;
						slots.push(resource);
						slotReusable.push(!customUse[resource.id]);
					}
					// reusing the same texture preserves its native resource state
					physical[resource.id] = slot;
					slotEnd[slot] = lastUse[resource.id];
				}
				if( resource.spec != null && (use.mip > 0 || use.layer > 0) )
					throw "Transient target only has one mip and layer";

			}

			final merge = pass.target != null && !barrier && previous != null
				&& previous.pass.target == pass.target && previous.pass.mip == pass.mip && previous.pass.layer == pass.layer;
			if( merge ) previous.endTarget = false;
			final step = { pass : pass, barrier : barrier, beginTarget : pass.target != null && !merge, endTarget : pass.target != null };
			steps.push(step);
			previous = step;
		}

		return { steps : steps, imports : imports, slots : slots, physical : physical };
	}

	public var passCount(get, never) : Int;
	function get_passCount() return schedule == null ? 0 : schedule.steps.length;

	public var transientAllocationCount(get, never) : Int;
	function get_transientAllocationCount() return physicalTextures.length;

	/** Resolve a declared texture for this pass. Transient textures are borrowed and must keep their creation settings. */
	public function texture(resource : GraphResource) : Texture {
		if( current != null )
			for( use in current.uses )
				if( use.resource == resource && resource != swapchain && resource.buffer == null )
					return resolveTexture(resource);
		throw "Texture was not declared by the active render graph pass";
	}

	/** Resolve a declared buffer for this pass. */
	public function buffer(resource : GraphResource) : Buffer {
		if( current != null )
			for( use in current.uses )
				if( use.resource == resource && resource.buffer != null )
					return resource.buffer;
		throw "Buffer was not declared by the active render graph pass";
	}

	inline function resolveTexture(resource : GraphResource) : Texture {
		return resource.spec == null ? resource.texture : physicalTextures[schedule.physical[resource.id]];
	}

	#if render_graph_profile
	public var validationSeconds(default, null) = 0.;
	public var barrierSeconds(default, null) = 0.;
	public var recordingSeconds(default, null) = 0.;
	#end

	public function execute() {
		if( disposed || executing || engine.driver != driver || Engine.getCurrent() != engine
			|| !@:privateAccess engine.inRender || driver.isDisposed() )
			throw "Render graph requires its original engine and an active render";

		if( schedule == null ) compile();
		#if render_graph_profile
		final validationStart = haxe.Timer.stamp();
		barrierSeconds = 0.;
		recordingSeconds = 0.;
		#end
		for( range in schedule.imports ) {
			final resource = range.resource;
			final texture = resource.texture;
			if( texture != null ) {
				if( texture.isDisposed() || range.lastMip >= texture.mipLevels || range.lastLayer >= texture.layerCount
					|| (range.firstMip >= 0 && range.firstMip < texture.residentMip) )
					throw "Render graph texture is disposed or its subresource is unavailable";
			} else if( resource.buffer.isDisposed() ) {
				throw "Render graph buffer is disposed";
			}
		}

		#if render_graph_profile
		validationSeconds = haxe.Timer.stamp() - validationStart;
		#end

		final entryTarget = @:privateAccess engine.targetStack;
		executing = true;
		try {
			while( physicalTextures.length < schedule.slots.length ) {
				final spec = schedule.slots[physicalTextures.length].spec;
				final target = new Texture(spec.width, spec.height, [Target], spec.format);
				target.preventAutoDispose();
				physicalTextures.push(target);
			}

			for( step in schedule.steps ) {
				final pass = step.pass;
				if( step.barrier ) {
					#if render_graph_profile
					final barrierStart = haxe.Timer.stamp();
					#end
					driver.renderGraphBarrier();
					#if render_graph_profile
					barrierSeconds += haxe.Timer.stamp() - barrierStart;
					#end
				}
				#if render_graph_profile
				final recordStart = haxe.Timer.stamp();
				#end
				if( step.beginTarget )
					engine.pushTarget(resolveTexture(pass.target), pass.layer, pass.mip, NotBound);
				if( pass.clear != null ) engine.clear(pass.clear);
				current = pass;
				if( pass.record != null ) pass.record(engine, this);
				current = null;
				if( step.endTarget ) engine.popTarget();
				#if render_graph_profile
				recordingSeconds += haxe.Timer.stamp() - recordStart;
				#end
			}
			if( schedule.steps.length != 0 && schedule.steps[schedule.steps.length - 1].pass.target == null )
				driver.renderGraphBarrier();
		} catch( error : Dynamic ) {
			current = null;
			executing = false;
			@:privateAccess while( engine.targetStack != null && engine.targetStack != entryTarget )
				engine.popTarget();
			throw error;
		}
		executing = false;
	}

	function releaseTargets(keep = 0) {
		if( !driver.isDisposed() )
			for( i in keep...physicalTextures.length ) physicalTextures[i].dispose();
		physicalTextures.resize(keep);
	}

	public function dispose() {
		if( disposed ) return;
		reset();
		disposed = true;
	}
}
