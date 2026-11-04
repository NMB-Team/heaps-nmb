package h3d.impl;

enum abstract ResourceClass(String) to String {
	var Persistent = "persistent";
	var FrameTransient = "frame-transient";
	var External = "external";
	var Swapchain = "swapchain";
	var History = "history";
	var Unknown = "unknown";
}

enum abstract ResourceAccess(String) to String {
	var RenderTargetWrite = "render-target-write";
	var ShaderRead = "shader-read";
	var ShaderWrite = "shader-write";
	var TransferRead = "transfer-read";
	var TransferWrite = "transfer-write";
	var Clear = "clear";
}

private typedef Usage = {
	var pass : Int;
	var access : ResourceAccess;
	var queue : String;
	var mip : Int;
	var layer : Int;
}

private typedef Resource = {
	var id : Int;
	var name : String;
	var classification : ResourceClass;
	var createdAt : Null<Int>;
	var complete : Bool;
	var observable : Bool;
	var usages : Array<Usage>;
}

class RenderGraphAnalysis {
	var resources : Array<Resource> = [];
	var gaps : Array<String> = [];
	var synchronization : Array<{ from : Int, to : Int, fromQueue : String, toQueue : String }> = [];

	public function new() {}

	public function register(name : String, classification : ResourceClass = Unknown, ?createdAt : Int) : Int {
		var id = resources.length;
		resources.push({ id : id, name : name, classification : classification, createdAt : createdAt,
			complete : false, observable : true, usages : [] });
		return id;
	}

	/** Completeness is an explicit caller contract, never inferred from recorded events. */
	public function declare(id : Int, classification : ResourceClass, complete = false, observable = true) {
		var r = resources[id];
		r.classification = classification;
		r.complete = complete;
		r.observable = observable;
	}

	public function created(id : Int, pass : Int) {
		if( resources[id].createdAt != null )
			missingUsage("Resource allocation identity changed during capture");
		resources[id].createdAt = pass;
	}

	/** -1 denotes all/unknown mips or layers and overlaps every subresource. */
	public function use(id : Int, pass : Int, access : ResourceAccess, queue = "unknown", mip = -1, layer = -1) {
		if( id < 0 || id >= resources.length || pass < 0 || mip < -1 || layer < -1 || queue == null )
			throw "Invalid RenderGraph resource usage";
		resources[id].usages.push({ pass : pass, access : access, queue : queue, mip : mip, layer : layer });
	}

	public function missingUsage(reason : String) {
		if( gaps.indexOf(reason) < 0 ) gaps.push(reason);
	}

	public function synchronize(from : Int, to : Int, fromQueue : String, toQueue : String) {
		synchronization.push({ from : from, to : to, fromQueue : fromQueue, toQueue : toQueue });
	}

	static function writes(access : ResourceAccess) {
		return access != ShaderRead && access != TransferRead;
	}

	public function dump() {
		var dependencies = [];
		var result = [];
		for( r in resources ) {
			var uses = r.usages.copy();
			// preserve insertion order for accesses within the same pass
			var ordered = [for( i in 0...uses.length ) { index : i, usage : uses[i] }];
			ordered.sort((a, b) -> a.usage.pass == b.usage.pass ? a.index - b.index : a.usage.pass - b.usage.pass);
			uses = [for( u in ordered ) u.usage];
			var reasons = gaps.copy();
			if( r.classification != FrameTransient ) reasons.push("Resource is not explicitly frame-transient");
			if( !r.complete ) reasons.push("Usage coverage is incomplete");
			if( r.observable ) reasons.push("Resource remains externally observable");
			if( r.createdAt == null ) reasons.push("Creation in this frame is unproven");
			if( uses.length == 0 ) reasons.push("No recorded uses");
			if( uses.length > 0 && !writes(uses[0].access) )
				reasons.push("Initial contents are required");
			var queues = [];
			for( u in uses ) if( queues.indexOf(u.queue) < 0 ) queues.push(u.queue);
			if( queues.indexOf("unknown") >= 0 || queues.length > 1 )
				reasons.push("Queue completion order is unproven");
			if( uses.length > 0 && r.createdAt != null && r.createdAt > uses[0].pass )
				reasons.push("Use precedes creation");

			for( i in 0...uses.length ) {
				var a = uses[i];
				for( j in i + 1...uses.length ) {
					var b = uses[j];
					if( a.mip != -1 && b.mip != -1 && a.mip != b.mip ) continue;
					if( a.layer != -1 && b.layer != -1 && a.layer != b.layer ) continue;
					var aw = writes(a.access), bw = writes(b.access);
					if( !aw && !bw ) continue;
					dependencies.push({ resource : r.id, from : a.pass, to : b.pass,
						fromQueue : a.queue, toQueue : b.queue,
						hazard : aw ? (bw ? "WAW" : "RAW") : "WAR" });
				}
			}
			result.push({ id : r.id, name : r.name, classification : (r.classification : String),
				createdAt : r.createdAt, firstUse : uses.length == 0 ? null : uses[0].pass,
				lastUse : uses.length == 0 ? null : uses[uses.length - 1].pass,
				accesses : uses, aliasingEligible : reasons.length == 0, ineligibilityReasons : reasons });
		}
		return { resources : result, dependencies : dependencies, synchronization : synchronization.copy() };
	}
}
