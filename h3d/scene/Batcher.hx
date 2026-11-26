package h3d.scene;

/** Batcher API **/

enum BatcherFlags {
	ManualEmitGPU;
}

enum BatchExecutionMode {
	Automatic;
	Cpu;
	Gpu;
}

@:allow(h3d.scene.Batcher)
class ObjectInstance {
	var owner : Batcher;
	var generation : Int;
	public var meshes : Array<MeshInstance>;
	public var materials : Array<MaterialInstance>;
	public var draws : Array<DrawInstance>;
	function new(owner : Batcher, meshes : Array<MeshInstance>, materials : Array<MaterialInstance>, draws : Array<DrawInstance>) {
		this.owner = owner;
		generation = @:privateAccess owner.generation;
		this.meshes = meshes;
		this.materials = materials;
		this.draws = draws;
	}
}

@:allow(h3d.scene.Batcher)
class BatchLibrary {
	static final BATCH_START_FMT = hxd.BufferFormat.make([{ name : "Batch_Start", type : DFloat }]);
	var primitives : Array<h3d.prim.BatchPrimitive> = [];
	var instancesOffset : h3d.Buffer;
	var maxUploadSize : Int;
	var isDynamic : Bool = true;

	public function new(isDynamic = true, maxUploadSize = -1) {
		this.maxUploadSize = maxUploadSize;
		this.isDynamic = isDynamic;
	}

	function getPrimitive( format : hxd.BufferFormat ) {
		for ( p in primitives )
			if ( p.vertexFormat == format )
				return p;
		var p = new h3d.prim.BatchPrimitive(format, isDynamic, maxUploadSize);
		primitives.push(p);
		return p;
	}

	public function addModel( m : h3d.prim.HMDModel ) {
		var prim = getPrimitive(@:privateAccess m.data.vertexFormat);
		prim.addModel(m);
	}

	public function addPolygon( m : h3d.prim.Polygon ) {
		var prim = getPrimitive(m.getBufferFormat());
		prim.addModel(m);
	}

	public function dispose() {
		for ( p in primitives )
			p.dispose();
		primitives.resize(0);
		instancesOffset?.dispose();
	}

	public function checkOffsetBuffer( instanceCount : Int ) {
		if ( instancesOffset == null || instancesOffset.vertices < instanceCount || instancesOffset.isDisposed() ) {
			if ( instancesOffset != null ) {
				instancesOffset.dispose();
				for ( p in primitives )
					p.removeBuffer(instancesOffset);
			}
			var tmp = haxe.io.Bytes.alloc(4 * instanceCount);
			for ( i in 0...instanceCount )
				tmp.setFloat(i<<2, i);
			instancesOffset = new h3d.Buffer(instanceCount, BATCH_START_FMT);
			instancesOffset.uploadBytes(tmp, 0, instanceCount);
			for ( p in primitives )
				p.addBuffer(instancesOffset);
		}
	}
}

@:allow(h3d.scene.Batcher)
class BatchGroup {
	var batcher : Batcher;
	var groupID : Int;
	var managed = false;

	public inline function new(b:Batcher, groupID : Int) {
		batcher = b;
		this.groupID = groupID;
	}

	public inline function emitInstance( obj : ObjectInstance, worldPosition : h3d.Matrix, syncID : Int = 0 ) {
		batcher.emitInstance( obj, worldPosition, syncID, groupID );
	}

	/**
		append an instance and retain a handle for incremental transform updates
		the handle expires when this group is removed
	**/
	public function emitTrackedInstance( obj : ObjectInstance, worldPosition : h3d.Matrix, syncID : Int = 0 ) : BatchInstanceHandle {
		if( batcher == null || !managed )
			throw "Batch group is inactive";
		return @:privateAccess batcher.emitTrackedInstance(this, obj, worldPosition, syncID);
	}

	public inline function reserveInstances( obj : ObjectInstance, count : Int ) {
		batcher.reserveInstances( obj, count, groupID );
	}

	public inline function remove() {
		if( batcher != null )
			batcher.removeGroup(this);
	}
}

private typedef TrackedDraw = {
	var data : EmitData;
	var index : Int;
	var relative : h3d.Matrix;
	var shaderData : ShaderData;
}

@:allow(h3d.scene.Batcher)
class BatchInstanceHandle {
	var group : BatchGroup;
	var records : Array<TrackedDraw> = [];

	function new(group : BatchGroup) {
		this.group = group;
	}

	/**
		replace the instance or keep the adaptive batch on its caller-owned CPU scene
		the caller must update that CPU scene before requesting the replacement
	**/
	public function replaceOrFallback(template : ObjectInstance, worldPosition : h3d.Matrix, ?previousPosition : h3d.Matrix) : Bool {
		var batcher = @:privateAccess group.batcher;
		if( batcher == null )
			throw "Batch instance has been removed";
		if( @:privateAccess batcher.cpuFallback == null )
			throw "replaceOrFallback requires a CPU fallback";

		var replaced = replace(template, worldPosition, previousPosition);
		if( !replaced )
			@:privateAccess batcher.requireReplacementFallback(this);
		return replaced;
	}

	/** replace the existing slots, returning false for a different batch or pass layout */
	public function replace(template : ObjectInstance, worldPosition : h3d.Matrix, ?previousPosition : h3d.Matrix) : Bool {
		var batcher = @:privateAccess group.batcher;
		if( batcher == null )
			throw "Batch instance has been removed";

		var replaced = @:privateAccess batcher.replaceTrackedInstance(this, template, worldPosition, previousPosition);
		if( replaced ) @:privateAccess batcher.incompatibleHandles?.remove(this);
		return replaced;
	}

	/**
		update a CPU-owned transform and optionally supply the previous transform for motion vectors
		without a previous transform, both samples use the current transform
	**/
	public function setTransform(worldPosition : h3d.Matrix, ?previousPosition : h3d.Matrix) {
		var batcher = @:privateAccess group.batcher;
		if( batcher == null )
			throw "Batch instance has been removed";

		for( record in records ) @:privateAccess {
			batcher.tmpMat.multiply3x4(record.relative, worldPosition);
			var previous = batcher.tmpMat;
			if( previousPosition != null ) {
				batcher.tmpPreviousMat.multiply3x4(record.relative, previousPosition);
				previous = batcher.tmpPreviousMat;
			}
			record.data.updateTransform(record.index, batcher.tmpMat, previous);
		}
	}
}

@:allow(h3d.scene.Batch, h3d.scene.BatchPass)
class Batcher extends h3d.scene.Object {
	public var shadowMaxDistance = -1.0;
	public var shadowCameraFrustumCulling = false; // Aggressive culling inside Shadow passes, using player camera frustum
	public var hzbCulling = false;
	public var reuseVisibility = true;
	public var executionMode : BatchExecutionMode = Automatic;
	public var minimumGpuInstances = 0;
	public var maximumGpuInstances = 0x1000000;
	public var fallbackReason(default, null) : String;
	var cpuFallback : RenderContext -> Void;
	var resourceFailure : String;
	var automaticGpu = false;
	var incompatibleHandles : Map<BatchInstanceHandle, Bool>;
	public var isRelative : Bool = false;
	public var batchFlags = new haxe.EnumFlags<BatcherFlags>();
	public var syncShader : SyncShaderInterface;
	var applyTransformShader : h3d.shader.ApplyTransformShader;

	var generation = 0;
	var highestGroupID = 1;
	var freeGroupIDs : Array<Int> = [];
	var groups : Array<BatchGroup> = [];

	var batches : Array<Batch> = [];
	var primToBatch : Map<h3d.prim.BatchPrimitive, Int> = [];
	var library : BatchLibrary;
	var shouldDisposeLibrary : Bool = false;

	var renderer : h3d.scene.Renderer;
	var globalShaders : Map<String, Array<hxsl.Shader>>;

	static inline var MAX_SHADOW_CASCADES = 4;
	var cascadeMap : h3d.pass.CascadeShadowMap;
	var cascadeFrame = -1;
	var cascadeCount = 0;
	var cascadeView = new h3d.Matrix();
	var cascadeMin = [for( i in 0...MAX_SHADOW_CASCADES ) new h3d.Vector4()];
	var cascadeMax = [for( i in 0...MAX_SHADOW_CASCADES ) new h3d.Vector4()];
	var cascadeBounds = new h3d.col.Bounds();

	function prepareCascades( ctx : h3d.scene.RenderContext ) : Int {
		if ( cascadeFrame == ctx.frame )
			return cascadeCount;
		cascadeFrame = ctx.frame;
		cascadeCount = 0;
		cascadeMap = null;
		var light = Std.downcast(ctx.lightSystem?.shadowLight, h3d.scene.pbr.Light);
		if ( light == null || !light.allocated )
			return 0;
		var csm = Std.downcast(light.shadows, h3d.pass.CascadeShadowMap);
		if ( csm == null || !csm.enabled || csm.mode == h3d.pass.Shadows.RenderMode.None || csm.cascade > MAX_SHADOW_CASCADES )
			return 0;
		csm.prepareCulling(ctx);
		cascadeMap = csm;
		cascadeCount = csm.cascade;
		cascadeView.load(csm.getCullingView());
		for ( i in 0...cascadeCount ) {
			var minSize = csm.getCasterBounds(i, cascadeBounds);
			cascadeMin[i].set(cascadeBounds.xMin, cascadeBounds.yMin, cascadeBounds.zMin, minSize);
			cascadeMax[i].set(cascadeBounds.xMax, cascadeBounds.yMax, cascadeBounds.zMax, 0.0);
		}
		return cascadeCount;
	}

	function getShadowSlot( ctx : h3d.scene.RenderContext, cascades : Int ) : Int {
		var view = ctx.currentView;
		if ( view.idx > cascades || cascadeMap == null || !cascadeMap.isCascadeView(view) )
			return 0;
		return view.idx;
	}

	public function hasSyncIDs() : Bool {
		return (syncShader != null && syncShader.hasSyncIDs());
	}

	public function addShader( s : hxsl.Shader, pass = "" ) {
		if( globalShaders == null )
			globalShaders = [];
		var shaders = globalShaders.get(pass);
		if( shaders == null ) {
			shaders = [];
			globalShaders.set(pass, shaders);
		}
		shaders.push(s);
		for( b in batches )
			for( p in @:privateAccess b.passes )
				if( pass == "" )
					p.pass.addShader(s);
				else if( p.pass.name == pass )
					@:privateAccess p.pass.addSelfShader(s);
	}

	public function removeShader( s : hxsl.Shader, pass = "" ) {
		if( globalShaders == null )
			return;
		var shaders = globalShaders.get(pass);
		if( shaders == null )
			return;
		if( shaders.remove(s) )
			for( b in batches )
				for( p in @:privateAccess b.passes )
					if( pass == "" || p.pass.name == pass)
						p.pass.removeShader(s);
	}

	/** whether the active Limen renderer can use GPU-generated batches */
	public static function supportsGpuDriven(driver : h3d.impl.driver.Driver) : Bool {
		if( !driver.hasFeature(Bindless) || !driver.hasFeature(ComputeShaders) )
			return false;

		#if (hl && limen && gfx_vulkan)
		var vulkan = Std.downcast(driver, h3d.impl.driver.vulkan.VulkanDriver);
		if( vulkan != null ) @:privateAccess {
			var caps = vulkan.capabilities;
			return caps != null && caps.drawIndirectCount && caps.multiDrawIndirect && caps.drawIndirectFirstInstance;
		}
		#end
		#if (hl && limen && gfx_dx12)
		if( Std.isOfType(driver, h3d.impl.driver.dx12.DX12Driver) )
			return true;
		#end
		return false;
	}

	/**
		use a caller-owned CPU renderer for the same objects when GPU preparation cannot proceed
		the callback emits ordinary scene passes and owns their ordering and materials
	**/
	public function new( parent : h3d.scene.Object, renderer : h3d.scene.Renderer, library : BatchLibrary = null, batchFlags = null,
		?cpuFallback : RenderContext -> Void ) {
		if ( cpuFallback == null && !h3d.Engine.getCurrent().driver.hasFeature(Bindless) )
			throw "h3d.scene.Batcher requires Bindless support.";
		super(parent);
		if ( batchFlags != null )
			this.batchFlags = batchFlags;
		shouldDisposeLibrary = library == null;
		this.library = shouldDisposeLibrary ? new BatchLibrary() : library;
		this.renderer = renderer;
		this.cpuFallback = cpuFallback;
		ignoreCollide = true;
	}

	function getBatchID( format : hxd.BufferFormat ) {
		var prim = library.getPrimitive(format);
		var batchID = primToBatch.get(prim);
		if ( batchID != null )
			return batchID;
		var batchID = batches.length;
		batches.push(new Batch(this, prim));
		primToBatch.set(prim, batchID);
		return batchID;
	}

	/**
		register a GPU template while a caller-owned CPU representation remains available
		returns null when resource registration must use the CPU path
	**/
	public function tryAddInstance(obj : Object, recChildren = true) : ObjectInstance {
		if( cpuFallback == null )
			throw "tryAddInstance requires a CPU fallback";
		if( resourceFailure != null || !supportsGpuDriven(h3d.Engine.getCurrent().driver) )
			return null;

		try {
			return addInstance(obj, recChildren);
		} catch( error : Dynamic ) {
			if( !recordResourceFailure(error) )
				throw error;
			return null;
		}
	}

	function requireReplacementFallback(handle : BatchInstanceHandle) {
		if( incompatibleHandles == null )
			incompatibleHandles = [];
		incompatibleHandles.set(handle, true);
	}

	public function retryGpuPreparation() {
		resourceFailure = null;
	}

	function recordResourceFailure(error : Dynamic) {
		var message = Std.string(error);
		var allocation = Std.downcast(error, h3d.impl.DescriptorAllocationError);
		if( allocation != null ) {
			if( !allocation.recoverable )
				return false;
			resourceFailure = allocation.message;
			return true;
		}
		if( message != "Failed to alloc GPU Memory (full)" &&
			message != "Vulkan frame descriptor arena exhausted" &&
			!StringTools.startsWith(message, "Descriptor heap exhausted (") &&
			!StringTools.startsWith(message, "Shader-visible sampler heap exhausted (") &&
			!~/^VMA allocation failed for .+: -[12](:|$)/.match(message) &&
			!(StringTools.startsWith(message, "Vulkan bindless ") && message.indexOf(" capacity exhausted:") >= 0) )
			return false;

		resourceFailure = message;
		return true;
	}

	public function addInstance( obj : h3d.scene.Object, recChildren : Bool = true ) : ObjectInstance {
		var meshes = [];
		var materials = [];
		var draws = [];
		var invPos = obj.getInvPos();
		inline function processMesh( m : h3d.scene.Mesh ) {
			var fmt : hxd.BufferFormat = null;
			var hmd = Std.downcast(m.primitive, h3d.prim.HMDModel);
			if ( hmd != null )
				fmt = @:privateAccess hmd.data.vertexFormat;
			else {
				var poly = Std.downcast(m.primitive, h3d.prim.Polygon);
				if (poly != null)
					fmt = poly.getBufferFormat();
			}
			if ( fmt != null ) {
				var batchID = getBatchID(fmt);
				var batch = batches[batchID];

				var subMeshID = batch.addModel(m);
				var materialStart = materials.length;
				var meshMaterials = m.getMeshMaterials();
				for ( mat in meshMaterials )
					materials.push(batch.addMaterial(mat, draws, renderer));

				var meshInstance = new MeshInstance(m.getAbsPos() * invPos, batchID, subMeshID, materialStart, meshMaterials.length);
				meshes.push(meshInstance);
			}
		}

		if ( recChildren )
			for ( m in obj.getMeshes() )
				processMesh(m);
		else {
			var m = Std.downcast(obj, h3d.scene.Mesh);
			if ( m != null )
				processMesh(m);
		}
		return new ObjectInstance(this, meshes, materials, draws);
	}

	public function createGroup() : BatchGroup {
		var groupID = freeGroupIDs.length > 0 ? freeGroupIDs.pop() : highestGroupID++;
		var group = new BatchGroup(this, groupID);
		group.managed = true;
		groups.push(group);
		return group;
	}

	public function removeGroup(group : BatchGroup) {
		var groupID = group.groupID;
		if( group.batcher != this || !groups.remove(group) )
			return;

		group.batcher = null;
		if( incompatibleHandles != null ) {
			for( handle in [for( handle in incompatibleHandles.keys() ) if( (@:privateAccess handle.group) == group ) handle] )
				incompatibleHandles.remove(handle);
		}
		freeGroupIDs.push(groupID);
		for (b in batches)
			b.disposeGroup(groupID);
	}

	public function reserveInstances( instance : ObjectInstance, count : Int, groupID : Int = 0 ) {
		for ( mesh in instance.meshes )
			batches[mesh.batchID].reserve(mesh, instance.materials, instance.draws, count, groupID);
	}

	var tmpMat = new h3d.Matrix();
	var tmpPreviousMat = new h3d.Matrix();

	function emitTrackedInstance(group : BatchGroup, instance : ObjectInstance, worldPosition : h3d.Matrix, syncID : Int) {
		if( instance.owner != this || instance.generation != generation )
			throw "Batch template belongs to a different or expired batcher";

		var handle = new BatchInstanceHandle(group);
		for( mesh in instance.meshes ) {
			tmpMat.multiply3x4(mesh.relPos, worldPosition);
			batches[mesh.batchID].emitMesh(mesh, instance.materials, instance.draws, tmpMat, syncID, group.groupID,
				handle.records, mesh.relPos);
		}
		return handle;
	}

	function replaceTrackedInstance(handle : BatchInstanceHandle, template : ObjectInstance, worldPosition : h3d.Matrix, previousPosition : h3d.Matrix) @:privateAccess {
		if( template == null || template.owner != this || template.generation != generation )
			return false;

		var updates = [];
		for( mesh in template.meshes ) {
			var batch = batches[mesh.batchID];
			var subMesh = batch.primitive.subMeshes[mesh.subMeshID];
			for( i in 0...mesh.materialCount ) {
				var material = template.materials[mesh.materialStart + i];
				var subPart = subMesh.subPartStart + i * subMesh.lodCount;
				if( subPart > 0xFFFF || mesh.subMeshID > 0xFFFF )
					return false;

				for( j in material.drawStart...material.drawStart + material.drawCount ) {
					var draw = template.draws[j];
					var record = handle.records[updates.length];
					if( record == null || record.data.batchPass != batch.passes[draw.passID] )
						return false;
					updates.push({ mesh : mesh, subPart : subPart, shaderData : draw.shaderData });
				}
			}
		}
		if( updates.length != handle.records.length )
			return false;

		for( i => update in updates ) {
			var record = handle.records[i];
			record.relative = update.mesh.relPos;
			tmpMat.multiply3x4(record.relative, worldPosition);
			var previous = tmpMat;
			if( previousPosition != null ) {
				tmpPreviousMat.multiply3x4(record.relative, previousPosition);
				previous = tmpPreviousMat;
			}

			record.data.replaceInstance(record.index, update.mesh.subMeshID, update.subPart,
				record.shaderData, update.shaderData, tmpMat, previous);
			record.shaderData = update.shaderData;
		}
		return true;
	}

	public function emitInstance( instance : ObjectInstance, worldPosition : h3d.Matrix, syncID : Int = 0, groupID : Int = 0 ) {
		for ( mesh in instance.meshes ) {
			var batch = batches[mesh.batchID];
			tmpMat.multiply3x4(mesh.relPos, worldPosition);
			batch.emitMesh( mesh, instance.materials, instance.draws, tmpMat, syncID, groupID );
		}
	}

	public function syncGPU(ctx : h3d.scene.RenderContext) {
		if ( !batchFlags.has(ManualEmitGPU) )
			throw "Can't call syncGPU without flag ManualEmitGPU";
		for ( b in batches )
			b.syncGPU(ctx);
		ctx.memoryBarrier();
	}

	public function emitGPU(ctx : h3d.scene.RenderContext) {
		if ( !batchFlags.has(ManualEmitGPU) )
			throw "Can't call emitGPU without flag ManualEmitGPU";
		var dispatches = ctx.engine.dispatches;
		for ( b in batches )
			b.emitGPU(ctx);
		if( ctx.engine.dispatches != dispatches )
			ctx.memoryBarrier();
	}

	override function emit( ctx : h3d.scene.RenderContext ) {
		if( cpuFallback == null ) {
			emitBatches(ctx);
			return;
		}

		fallbackReason = resourceFailure;
		if( fallbackReason == null && incompatibleHandles != null && incompatibleHandles.keys().hasNext() )
			fallbackReason = "GPU batch has an incompatible replacement";
		if( fallbackReason == null && !supportsGpuDriven(ctx.engine.driver) )
			fallbackReason = "GPU batch capability unavailable";
		if( fallbackReason == null && executionMode == Cpu )
			fallbackReason = "CPU override";

		if( fallbackReason == null ) {
			var largest = 0;
			for( b in batches )
				largest = hxd.Math.imax(largest, b.totalInstanceCount);

			var threshold = automaticGpu ? minimumGpuInstances - (minimumGpuInstances >> 2) : minimumGpuInstances;
			if( largest == 0 || (executionMode == Automatic && largest < threshold) )
				fallbackReason = "GPU batch below workload threshold";
			else if( largest > maximumGpuInstances )
				fallbackReason = "GPU batch exceeds instance budget";
			else if( batchFlags.has(ManualEmitGPU) )
				fallbackReason = "Manual GPU dispatch owns its fallback";
		}

		if( fallbackReason == null ) {
			var dispatches = ctx.engine.dispatches;
			try {
				emitBatches(ctx, true);
			} catch( error : Dynamic ) {
				if( !recordResourceFailure(error) )
					throw error;
				if( ctx.engine.dispatches != dispatches )
					ctx.memoryBarrier();
				for( b in batches )
					b.releaseGpuPasses();
				fallbackReason = resourceFailure;
			}
		}
		automaticGpu = fallbackReason == null && executionMode == Automatic;
		if( fallbackReason != null )
			cpuFallback(ctx);
	}

	function emitBatches(ctx : RenderContext, adaptive = false) {
		var maxInstanceCount = 0;
		for ( b in batches ) {
			if ( b.totalInstanceCount == 0 )
				continue;
			b.uploadPrimitive(ctx);
			maxInstanceCount = hxd.Math.imax(b.totalInstanceCount, maxInstanceCount);
		}

		if ( maxInstanceCount == 0 )
			return;

		if ( isRelative ) {
			if ( applyTransformShader == null ) {
				applyTransformShader = new h3d.shader.ApplyTransformShader();
				applyTransformShader.invTransform = new h3d.Matrix();
				applyTransformShader.transform = new h3d.Matrix();
				applyTransformShader.prevTransform = new h3d.Matrix();
				addShader(applyTransformShader);
			}
			var absPos = getAbsPos();
			applyTransformShader.invTransform.initInverse(absPos);
			applyTransformShader.transform.load(absPos);
			applyTransformShader.prevTransform.load(prevAbsPos ?? absPos);
		} else if ( applyTransformShader != null ) {
			removeShader(applyTransformShader);
			applyTransformShader = null;
		}

		var doDispatch = !batchFlags.has(ManualEmitGPU);
		var dispatches = ctx.engine.dispatches;
		if( adaptive ) {
			for( b in batches ) {
				fallbackReason = b.checkGpuPasses(ctx);
				if( fallbackReason != null )
					return;
			}
			ctx.engine.driver.preflightBatchDescriptors();
			for( b in batches ) {
				b.emitGPU(ctx);
				b.prepareOffsets();
			}
		}
		for ( batchID => b in batches )
			b.emit(ctx, batchID, doDispatch && !adaptive, adaptive);

		if( ctx.engine.dispatches != dispatches )
			ctx.memoryBarrier();
	}

	override function draw(ctx : h3d.scene.RenderContext ) {
		batches[ctx.drawPass.index & 0xFFFF].draw(ctx);
	}

	public function dump( path : String = "batcher_dump.txt" ) @:privateAccess {
		var sb = new StringBuf();
		var primLines : Array<{format : String, hmds : Array<String>, refCount : Int}> = [];
		var primitives = library.primitives;
		for ( i => p in primitives ) {
			var format = '\n\t$i) ${p.vertexFormat.toString()}';
			var hmds = [];
			for ( m in p.models) {
				var hmd = Std.downcast(m, h3d.prim.HMDModel);
				if ( hmd != null )
					hmds.push("\n\t\t" + hmd.lib.resource.entry.path + " - " + hmd.model.getObjectName());
				else
					hmds.push("\n\t\t polygon");
			}
			primLines.push({format:format, hmds:hmds, refCount:0});
		}

		var lines : Array<{ prim : Int, pass : String, shaders : String, count : Int, batchShader : hxsl.BatchShader }> = [];
		for ( b in batches ) {
			var primId = primitives.indexOf(b.primitive);
			primLines[primId].refCount += b.totalInstanceCount;
			for ( bp in b.passes ) {
				var shaderNames = [ for (s in bp.shaders) { Type.getClassName(Type.getClass(s)).split(".").pop() + ':${s.constBits}'; } ].join("+");
				lines.push({ prim: primId, pass: bp.pass.name, shaders: shaderNames, count: bp.totalInstanceCount, batchShader:bp.batchShader });
			}
		}
		lines.sort((a, b) -> b.count - a.count);

		sb.add("Primitives:");
		for (l in primLines) {
			sb.add('${l.format} (${l.refCount} refCount)');
			for ( hmd in l.hmds )
				sb.add(hmd);
		}

		sb.add("\n\nGlobal shaders:");
		if( globalShaders == null )
			sb.add("\n\tnone");
		else
			for( p => shaders in globalShaders )
				sb.add('\n\t${p==""?"all":p}: ${[ for( s in shaders ) { Type.getClassName(Type.getClass(s)).split(".").pop() + ':${s.constBits}'; } ].join("+")}');

		sb.add("\n\nCOUNT\tPASS\tPRIMITIVE\tSHADERS\tPARAMS SIZE");
		for ( l in lines ) {
			sb.add('\n${l.count}\t${l.pass}\t${l.prim}\t${l.shaders}\t${l.batchShader.paramsSize * 16}B');
			var p = l.batchShader.params;
			while ( p != null ) {
				sb.add('\n\t${p.name}');
				p = p.next;
			}
		}
		#if (sys || nodejs)
		sys.io.File.saveContent(path, sb.toString());
		#else
		trace(sb.toString());
		#end
	}

	override function onRemove() {
		super.onRemove();
		for ( b in batches)
			b.dispose();
		if ( shouldDisposeLibrary )
			library.dispose();
		for( group in groups )
			group.batcher = null;
		groups.resize(0);
		incompatibleHandles = null;
		generation++;
		batches.resize(0);
		freeGroupIDs.resize(0);
		primToBatch.clear();
		highestGroupID = 1;
	}
}

class BaseSync extends hxsl.Shader {
	static var SRC = {
		@param var instancesData : RWBuffer<Vec4>;
		@param var instanceStride : Int;
		@param var modelViewOffset : Int;
		@param var instanceCount : Int;
		@param var syncIDs : StorageBuffer<Int>;

		function getModelView( id : Int ) : Mat4 {
			var modelViewPos = id * instanceStride + modelViewOffset;
			return mat4(
				instancesData[modelViewPos + 0],
				instancesData[modelViewPos + 1],
				instancesData[modelViewPos + 2],
				instancesData[modelViewPos + 3],
			);
		}

		function fillModelView( id : Int, modelView : Mat4 ) {
			var modelViewPos = id * instanceStride + modelViewOffset;
			instancesData[modelViewPos + 0] = modelView[0];
			instancesData[modelViewPos + 1] = modelView[1];
			instancesData[modelViewPos + 2] = modelView[2];
			instancesData[modelViewPos + 3] = modelView[3];
		}
	}
}

interface SyncShaderInterface {
	var instancesData(get,set) : h3d.Buffer;
	var instanceStride(get,set) : Int;
	var modelViewOffset(get,set) : Int;
	var instanceCount(get,set) : Int;
	var syncIDs(get,set) : h3d.Buffer;
	public function hasSyncIDs() : Bool;
}

/** Batcher Implementation **/

@:allow(h3d.scene.Batcher)
private class MeshInstance {
	public var relPos : h3d.Matrix;
	public var batchID : Int;
	public var subMeshID : Int;
	public var materialStart : Int;
	public var materialCount : Int;
	function new(relPos: h3d.Matrix, batchID : Int, subMeshID : Int, materialStart : Int, materialCount : Int) {
		this.relPos = relPos;
		this.batchID = batchID;
		this.subMeshID = subMeshID;
		this.materialStart = materialStart;
		this.materialCount = materialCount;
	}
}

@:allow(h3d.scene.Batch)
private class MaterialInstance {
	public var drawStart : Int;
	public var drawCount : Int;

	function new( drawStart : Int, drawCount : Int ) {
		this.drawStart = drawStart;
		this.drawCount = drawCount;
	}
}

@:allow(h3d.scene.Batch)
private class DrawInstance {
	public var shaderData : ShaderData;
	public var passID : Int;

	function new(shaderData : ShaderData, passID : Int) {
		this.shaderData = shaderData;
		this.passID = passID;
	}
}

@:allow(h3d.scene.BatchPass)
private class ShaderData {
	public var data : hxd.FloatBuffer;
	public var bufferHandles : Array<h3d.BufferHandle>;
	public var textureHandles : Array<h3d.mat.TextureHandle>;
	function new() {}
}

@:allow(h3d.scene.GroupData, h3d.scene.BatchPass)
private class Batch {
	public var batcher : h3d.scene.Batcher;
	public var primitive : h3d.prim.BatchPrimitive;

	public var totalInstanceCount : Int;
	public var instancesDirty : Bool;

	public var needLogicNormal : Bool = false;
	var passes : Array<BatchPass> = [];
	var groups : Array<GroupData> = [];

	public function new( b : Batcher, prim : h3d.prim.BatchPrimitive ) {
		batcher = b;
		primitive = prim;
	}

	public function addModel( mesh : h3d.scene.Mesh ) : Int {
		return primitive.addModel(cast mesh.primitive);
	}

	function findPassID( globals : hxsl.Globals, shaders : hxsl.ShaderList, pass : h3d.mat.Pass ) : Int {
		for ( i => bp in passes ) @:privateAccess {
			if ( pass.bits == bp.pass.bits && pass.name == bp.pass.name && pass.layer == bp.pass.layer &&
				pass.colorMask == bp.pass.colorMask && pass.stencil == null && bp.pass.stencil == null ) {
				var sl = shaders;
				var sIdx = 0;
				var shaderCount = bp.shaders.length;
				while ( sl != null && sIdx < shaderCount ) {
					var s1 = sl.s;
					var s2 = bp.shaders[sIdx];
					s1.updateConstants(globals);
					s2.updateConstants(globals);
					if ( s1.instance.id != s2.instance.id )
						break;
					sIdx++;
					sl = sl.next;
				}
				if ( sIdx == bp.shaders.length && sl == null )
					return i;
			}
		}
		return -1;
	}

	public function addMaterial( m : h3d.mat.Material, draws : Array<DrawInstance>, renderer : h3d.scene.Renderer ) : MaterialInstance {
		var globals = @:privateAccess renderer.ctx.globals;
		var drawStart = draws.length;
		for ( p in m.getPasses() ) @:privateAccess {
			if ( p.culled )
				continue;
			var shaders = p.getShadersRec();
			var passID = findPassID(globals, shaders, p);
			if ( passID < 0 ) {
				passID = passes.length;
				passes.push( new BatchPass(renderer, this, p, primitive) );
			}
			var bp = passes[passID];
			var shaderData = bp.getShaderData(shaders);
			draws.push(new DrawInstance(shaderData, passID));
		}
		return new MaterialInstance(drawStart, draws.length - drawStart);
	}

	function getGroup( groupID : Int ) {
		var group = groups[groupID];
		if ( group == null ) {
			group = new GroupData(this);
			groups[groupID] = group;
		}
		return group;
	}

	public function reserve( mesh : MeshInstance, materials : Array<MaterialInstance>, draws : Array<DrawInstance>, count : Int, groupID : Int ) {
		getGroup(groupID).reserve(materials, draws, mesh.materialStart, mesh.materialCount, count);
	}

	public function emitMesh( mesh : MeshInstance, materials : Array<MaterialInstance>, draws : Array<DrawInstance>, worldPosition : h3d.Matrix, syncID : Int, groupID : Int, ?records : Array<TrackedDraw>, ?relative : h3d.Matrix ) {
		var group = getGroup(groupID);

		instancesDirty = true;
		totalInstanceCount++;

		group.emitMesh(primitive, mesh.subMeshID, materials, draws, mesh.materialStart, mesh.materialCount, worldPosition, syncID, records, relative);
	}

	public function uploadPrimitive(ctx : h3d.scene.RenderContext) {
		if ( primitive.gpuSubMeshInfos == null || primitive.gpuSubMeshInfos.isDisposed() ||
			primitive.gpuSubPartInfos == null || primitive.gpuSubPartInfos.isDisposed() ||
			primitive.gpuLodInfos == null || primitive.gpuLodInfos.isDisposed() ) {
			primitive.alloc(ctx.engine);
			if ( batcher.library.instancesOffset != null )
				primitive.addBuffer(batcher.library.instancesOffset);
		}
		if ( needLogicNormal )
			primitive.addLogicNormal();
	}

	public function disposeGroup(groupID : Int) {
		groups[groupID]?.dispose();
	}

	public function syncGPU(ctx : h3d.scene.RenderContext) {
		for ( i => p in passes ) {
			if ( p.totalInstanceCount == 0 )
				continue;
			p.syncGPU(ctx);
		}
	}

	public function emitGPU(ctx : h3d.scene.RenderContext) {
		for ( i => p in passes ) {
			if ( p.totalInstanceCount == 0 )
				continue;
			p.emitGPU(ctx);
		}
	}

	public function releaseGpuPasses() {
		for( p in passes )
			p.dispose();
	}

	public function prepareOffsets() {
		for( p in passes )
			if( p.totalInstanceCount != 0 )
				@:privateAccess batcher.library.checkOffsetBuffer(p.totalInstanceCount * (p.emittedCascades + 1));
	}

	public function checkGpuPasses(ctx : RenderContext) {
		for( p in passes ) {
			if( p.totalInstanceCount == 0 )
				continue;
			var pass = p.pass;
			if( !pass.depthWrite || (pass.depthTest != Less && pass.depthTest != LessEqual &&
				pass.depthTest != Greater && pass.depthTest != GreaterEqual) || pass.stencil != null ||
				pass.blendSrc != One || pass.blendDst != Zero ||
				pass.blendAlphaSrc != One || pass.blendAlphaDst != Zero || pass.blendOp != Add || pass.blendAlphaOp != Add )
				return "GPU batch requires ordered rendering";
			if( !p.fitsGpuLimits(ctx) )
				return "GPU batch exceeds device buffer or indirect draw limits";
		}
		return null;
	}

	public function emit( ctx : h3d.scene.RenderContext, batchID : Int, doEmitGPU : Bool, offsetsReady = false ) {
		if ( totalInstanceCount == 0 )
			return;

		for ( i => p in passes ) {
			if ( p.totalInstanceCount == 0 )
				continue;
			if ( doEmitGPU )
				p.emitGPU(ctx);
			ctx.emitPass(p.pass, batcher).index = i << 16 | batchID;
			if( !offsetsReady )
				@:privateAccess batcher.library.checkOffsetBuffer(p.totalInstanceCount * (p.emittedCascades + 1));
		}
	}

	public function draw( ctx : h3d.scene.RenderContext ) {
		passes[ctx.drawPass.index >> 16].draw(ctx);
	}

	public function dispose() {
		for (p in passes)
			p.dispose();
		passes.resize(0);
		for ( g in groups )
			g?.dispose();
		groups.resize(0);
		if ( totalInstanceCount != 0 )
			throw "Instance leak in batcher";
		totalInstanceCount = 0;
		instancesDirty = false;
		needLogicNormal = false;
	}
}

private class GroupData {
	var emitDatas : Array<EmitData> = [];
	var batch : Batch;

	public var instanceCount(default, null) = 0;

	public function new( b : Batch ) {
		batch = b;
	}

	inline function getEmitData( passID : Int ) {
		var emitData = emitDatas[passID];
		if ( emitData == null ) {
			emitData = new EmitData(batch.passes[passID]);
			emitDatas[passID] = emitData;
		}
		return emitData;
	}

	public function reserve( materials : Array<MaterialInstance>, draws : Array<DrawInstance>, materialStart : Int, materialCount : Int, count : Int ) {
		for ( i in materialStart...materialStart + materialCount ) {
			var m = materials[i];
			for ( j in m.drawStart...m.drawStart + m.drawCount )
				getEmitData(draws[j].passID).reserve(count);
		}
	}

	public function emitMesh( primitive : h3d.prim.BatchPrimitive, subMeshID : Int, materials : Array<MaterialInstance>, draws : Array<DrawInstance>, materialStart : Int, materialCount : Int, worldPosition : h3d.Matrix, syncID : Int, records : Array<TrackedDraw>, relative : h3d.Matrix ) {
		instanceCount++;

		var subMesh = primitive.subMeshes[subMeshID];
		var subPartStart = subMesh.subPartStart;
		for ( i in 0...materialCount ) {
			var m = materials[materialStart + i];
			var subPartID = subPartStart + i * subMesh.lodCount;
			for ( j in m.drawStart...m.drawStart + m.drawCount ) {
				var draw = draws[j];
				var data = getEmitData(draw.passID);
				var index = data.instanceCount;
				data.emitInstance(subMeshID, subPartID, draw.shaderData, worldPosition, syncID);
				if( records != null )
					records.push({ data : data, index : index, relative : relative, shaderData : draw.shaderData });
			}
		}
	}

	public function dispose() {
		for ( e in emitDatas ) {
			if ( e == null )
				continue;
			e.dispose();
			if ( instanceCount < e.instanceCount )
				throw "assert";
			instanceCount -= e.instanceCount;
		}
		emitDatas.resize(0);
		batch.instancesDirty = true;
		if ( batch.totalInstanceCount < instanceCount )
			throw "assert";
		batch.totalInstanceCount -= instanceCount;
		instanceCount = 0;
	}
}

private class BatchBucketClear extends hxsl.Shader {
	static var SRC = {
		@param var buckets : RWBuffer<Int>; // count, firstInstance
		@param var bucketCount : Int;
		@param var countBuffer : RWBuffer<Int>;
		@param var slotCount : Int;
		@const var singleBucket : Bool;
		@param var subPartInfos : StorageBuffer<Int>;
		@param var commandBuffer : RWBuffer<Int>;

		function main() {
			setLayout(64, 1, 1);
			var bucket = computeVar.globalInvocation.x;
			if ( bucket < slotCount ) {
				countBuffer[bucket * 2] = 0;
				countBuffer[bucket * 2 + 1] = 0;
			}
			if ( singleBucket ) {
				if ( bucket == 0 ) {
					commandBuffer[0] = subPartInfos[0];
					commandBuffer[1] = 0;
					commandBuffer[2] = subPartInfos[1];
					commandBuffer[3] = 0;
					commandBuffer[4] = 0;
				}
			} else if ( bucket < bucketCount ) {
				buckets[bucket * 2] = 0;
			}
		}
	};
}

private class BatchBucketCommands extends hxsl.Shader {
	static var SRC = {
		@param var buckets : RWBuffer<Int>;
		@param var bucketCount : Int;
		@param var slotCount : Int;
		@param var commandCapacity : Int;
		@param var instanceCount : Int;
		@param var subPartInfos : StorageBuffer<Int>;
		@param var countBuffer : RWBuffer<Int>; // command count, visible instance count per slot
		@param var commandBuffer : RWBuffer<Int>;

		function main() {
			setLayout(64, 1, 1);
			var bucket = computeVar.globalInvocation.x;
			if ( bucket >= bucketCount * slotCount )
				return;
			var slot = bucket / bucketCount;
			var subPart = bucket % bucketCount;
			var count = buckets[bucket * 2];
			if ( count == 0 )
				return;
			var firstInstance = slot * instanceCount + atomicAdd(countBuffer, slot * 2 + 1, count);
			buckets[bucket * 2 + 1] = firstInstance;
			var command = (slot * commandCapacity + atomicAdd(countBuffer, slot * 2, 1)) * 5;
			commandBuffer[command + 0] = subPartInfos[subPart * 2];
			commandBuffer[command + 1] = count;
			commandBuffer[command + 2] = subPartInfos[subPart * 2 + 1];
			commandBuffer[command + 3] = 0;
			commandBuffer[command + 4] = firstInstance;
		}
	};
}

private class BatchInstanceScatter extends hxsl.Shader {
	static var SRC = {
		@param var buckets : StorageBuffer<Int>;
		@param var instanceSlots : StorageBuffer<Int>; // selected bucket, local slot per instance and cascade
		@param var visibleInstanceIds : RWBuffer<Int>;
		@param var instanceCount : Int;
		@param var slotCount : Int;

		function main() {
			setLayout(64, 1, 1);
			var instanceID = computeVar.globalInvocation.x + computeVar.globalInvocation.y * (65535 * 64);
			if ( instanceID >= instanceCount * slotCount )
				return;
			var bucket = instanceSlots[instanceID * 2];
			if ( bucket < 0 )
				return;
			var slot = buckets[bucket * 2 + 1] + instanceSlots[instanceID * 2 + 1];
			visibleInstanceIds[slot] = instanceID % instanceCount;
		}
	};
}

private class BatchCommandBuilder extends hxsl.Shader {
	static var SRC = {
		@const var ENABLE_FRUSTUM_CULLING : Bool;
		@const var ENABLE_DISTANCE_CLIPPING : Bool;
		@const var ENABLE_HZB_CULLING : Bool;
		@const var singleBucket : Bool;
		@param var commandBuffer : RWBuffer<Int>;
		@param var countBuffer : RWBuffer<Int>;
		@param var visibleInstanceIds : RWBuffer<Int>;

		@global var camera : {
			var position : Vec3;
			var proj : Mat4;
			var view : Mat4;
			var zNear : Float;
			var zFar : Float;
		}

		@param var instancesData : StorageBuffer<Vec4>;
		@param var instanceStride : Int;
		@param var modelViewOffset : Int;
		@param var instancesInfos : StorageBuffer<Int>; // 1 elements => 0 : flags = subPartID(16 bits) + subMeshID(16 bits)
		@param var subMeshInfos : StorageBuffer<Vec4>; // 2 elements => 0 : xyz : bounds center, w : lodStart, 1 : xyz : bounds half extents (bounding sphere radius = length), w : lodCount
		@param var lodInfos : StorageBuffer<Float>; // x : screenRatio
		@param var buckets : RWBuffer<Int>;
		@param var instanceSlots : RWBuffer<Int>;
		@param var instanceCount : Int;

		@const var IS_RELATIVE : Bool;
		@param var worldMatrix : Mat4;

		@param var frustum : Buffer<Vec4, 6>;

		@param var maxDistance : Float = -1;
		@param var meshLodScale : Float = 1.0;

		final subMeshInfosStride : Int = 2;

		final MAX_CASCADES : Int = 4;
		@param var cascadeCount : Int;
		@param var cascadeView : Mat4;
		@param var cascadeMin : Array<Vec4, MAX_CASCADES>;
		@param var cascadeMax : Array<Vec4, MAX_CASCADES>;
		@param var bucketCount : Int;

		@param var hzb : Sampler2D;
		@param var hzbSize : Vec2;
		@param var hzbMipCount : Int;
		@param var reverseDepth : Bool;
		@param var frustumPlaneCount : Int;

		@const var ENABLE_STREAMING_FEEDBACK : Bool;
		@param var streamingFeedback : RWBuffer<Int>;
		@param var feedbackSize : Int;
		@param var textureHandlePos : StorageBuffer<Int>;
		@param var textureHandleCount : Int;

		function writeStreamingFeedback( instanceID : Int ) {
			var base = instanceID * instanceStride;
			for ( i in 0...textureHandleCount ) {
				var pos = textureHandlePos[i];
				var v = instancesData[base + (pos >> 2)];
				var c = pos & 3;
				var f = c == 0 ? v.x : (c == 1 ? v.y : (c == 2 ? v.z : v.w));
				var srv = floatBitsToInt(f);
				if ( srv < feedbackSize && streamingFeedback[srv] == 0 )
					streamingFeedback[srv] = 1;
			}
		}

		function insideOBB(pos : Vec3, extents : Vec3, min : Vec3, max : Vec3) : Bool {
			return (pos.x + extents.x) > min.x && (pos.x - extents.x) < max.x &&
					(pos.y + extents.y) > min.y && (pos.y - extents.y) < max.y &&
					(pos.z + extents.z) > min.z && (pos.z - extents.z) < max.z;
		}

		function computeScreenRatio( distToCam : Float, radius : Float ) : Float {
			var screenMultiple = max(0.5 * camera.proj[0][0], 0.5 * camera.proj[1][1]);
			var screenRadius = screenMultiple * radius / max(1.0, distToCam);
			return 2.0 * screenRadius * meshLodScale;
		}

		function selectHzbMip( uvMin : Vec2, uvMax : Vec2 ) : Float {
			var texelSize = (uvMax - uvMin) * hzbSize;
			var mip = max(0.0, ceil(log2(max(texelSize.x, texelSize.y))));
			var finerMip = max(mip - 1.0, 0.0);
			var finerMipSize = max(vec2(1.0), floor(hzbSize / pow(vec2(2.0), vec2(finerMip))));
			var finerTexelSpan = floor(uvMax * finerMipSize) - floor(uvMin * finerMipSize);
			var selectedMip = finerTexelSpan.x <= 1.0 && finerTexelSpan.y <= 1.0 ? finerMip : mip;
			return clamp(selectedMip, 0.0, log2(max(hzbSize.x, hzbSize.y)));
		}

		function main() {
			setLayout(64, 1, 1);
			var instanceID = computeVar.globalInvocation.x + computeVar.globalInvocation.y * (65535 * 64);
			if ( instanceID >= instanceCount )
				return;

			if ( !singleBucket ) @unroll for ( slot in 0...MAX_CASCADES + 1 )
				if ( slot <= cascadeCount )
					instanceSlots[(slot * instanceCount + instanceID) * 2] = -1;

			var modelViewPos = instanceID * instanceStride + modelViewOffset;
			var modelView = mat4(
				instancesData[modelViewPos + 0],
				instancesData[modelViewPos + 1],
				instancesData[modelViewPos + 2],
				instancesData[modelViewPos + 3],
			);
			var scale = vec3(
				length(vec3(modelView[0].x,modelView[1].x,modelView[2].x)),
				length(vec3(modelView[0].y,modelView[1].y,modelView[2].y)),
				length(vec3(modelView[0].z,modelView[1].z,modelView[2].z))
			);

			if ( dot(scale, scale) < 1e-12 )
				return;

			var flags : Int = instancesInfos[instanceID];
			var subMeshID : Int = (flags >> 16) & 0xFFFF;

			var subMeshPos = subMeshID * subMeshInfosStride;
			var bbCenter = subMeshInfos[subMeshPos + 0].xyz;
			var lodStart : Int = floatBitsToInt(subMeshInfos[subMeshPos + 0].w);
			var bbHalfExtents = subMeshInfos[subMeshPos + 1].xyz;
			var lodCount : Int = floatBitsToInt(subMeshInfos[subMeshPos + 1].w);

			var localCenter = vec4(bbCenter, 1.0);
			var position = vec3(dot(modelView[0], localCenter), dot(modelView[1], localCenter), dot(modelView[2], localCenter));

			if ( IS_RELATIVE ) {
				position = position * worldMatrix.mat3x4();
				var worldScale = vec3(
					length(vec3(worldMatrix[0].x,worldMatrix[1].x,worldMatrix[2].x)),
					length(vec3(worldMatrix[0].y,worldMatrix[1].y,worldMatrix[2].y)),
					length(vec3(worldMatrix[0].z,worldMatrix[1].z,worldMatrix[2].z))
				);
				scale *= worldScale;
			}

			var boundingSphere = length(bbHalfExtents) * max(scale.x,max(scale.y, scale.z));

			var boxAxes = [
				vec3(modelView[0].x, modelView[1].x, modelView[2].x) * bbHalfExtents.x,
				vec3(modelView[0].y, modelView[1].y, modelView[2].y) * bbHalfExtents.y,
				vec3(modelView[0].z, modelView[1].z, modelView[2].z) * bbHalfExtents.z
			];
			if ( IS_RELATIVE ) {
				@unroll for ( i in 0...3 )
					boxAxes[i] = boxAxes[i] * worldMatrix.mat3();
			}

			if ( ENABLE_FRUSTUM_CULLING ) {
				@unroll for ( i  in 0...6 ) {
					var plane = frustum[i];
					var extent = abs(dot(plane.xyz, boxAxes[0])) + abs(dot(plane.xyz, boxAxes[1])) + abs(dot(plane.xyz, boxAxes[2]));
					var errorMargin = (dot(abs(plane.xyz), abs(position)) + abs(plane.w) + extent + 1.0) * 1e-6;
					if ( i < frustumPlaneCount && dot(plane.xyz, position) - plane.w < -extent - errorMargin )
						return;
				}
			}

			if ( ENABLE_HZB_CULLING ) {
				var posView = vec4(position, 1.0) * camera.view;
				var viewAxes = [ boxAxes[0] * camera.view.mat3(), boxAxes[1] * camera.view.mat3(), boxAxes[2] * camera.view.mat3() ];
				var cornerSigns = [
					vec3(-1, -1, -1), vec3(1, -1, -1), vec3(-1, 1, -1), vec3(1, 1, -1),
					vec3(-1, -1, 1), vec3(1, -1, 1), vec3(-1, 1, 1), vec3(1, 1, 1)
				];
				var uvMin = vec2(1e30);
				var uvMax = vec2(-1e30);
				var closest = reverseDepth ? 0.0 : 1.0;
				var valid = true;
				@unroll for ( i in 0...8 ) {
					var sign = cornerSigns[i];
					var corner = posView.xyz + viewAxes[0] * sign.x + viewAxes[1] * sign.y + viewAxes[2] * sign.z;
					var clip = vec4(corner, 1.0) * camera.proj;
					if ( !(clip.w > 0.0 && clip.z > 0.0 && clip.z < clip.w) ) {
						valid = false;
					} else {
						var cornerUV = screenToUv(clip.xy / clip.w);
						uvMin = min(uvMin, cornerUV);
						uvMax = max(uvMax, cornerUV);
						var depth = clip.z / clip.w;
						closest = reverseDepth ? max(closest, depth) : min(closest, depth);
					}
				}
				if ( valid ) {
					var pixel = 1.0 / hzbSize;
					uvMin = saturate(uvMin - pixel);
					uvMax = saturate(uvMax + pixel);
					var mip = min(selectHzbMip(uvMin, uvMax), float(hzbMipCount - 1));
					var mipSize = max(vec2(1.0), floor(hzbSize / pow(vec2(2.0), vec2(mip))));
					var low = ivec2(clamp(uvMin * mipSize, vec2(0.0), mipSize - vec2(1.0)));
					var high = ivec2(clamp(uvMax * mipSize, vec2(0.0), mipSize - vec2(1.0)));

					if ( high.x - low.x <= 1 && high.y - low.y <= 1 ) {
						var a = hzb.fetchLod(low, int(mip)).x;
						var b = hzb.fetchLod(ivec2(high.x, low.y), int(mip)).x;
						var c = hzb.fetchLod(ivec2(low.x, high.y), int(mip)).x;
						var d = hzb.fetchLod(high, int(mip)).x;
						var depth = reverseDepth ? min(min(a, b), min(c, d)) : max(max(a, b), max(c, d));
						if ( reverseDepth ? closest + 1e-5 < depth : closest - 1e-5 > depth )
							return;
					}
				}
			}

			var toCam = camera.position - position.xyz;
			var distToCam = length(toCam);
			if ( ENABLE_DISTANCE_CLIPPING )
				if ( distToCam > maxDistance )
					return;

			var screenRatio = computeScreenRatio(distToCam, boundingSphere);
			var lodSelected : Int = 0;
			for ( i in 0...lodCount ) {
				var minScreenRatio = lodInfos[lodStart + i];
				if ( screenRatio > minScreenRatio )
					break;
				lodSelected++;
			}

			if ( lodSelected >= lodCount )
				return;

			if ( singleBucket ) {
				var index = atomicAdd(commandBuffer, 1, 1);
				visibleInstanceIds[index] = instanceID;
				if ( index == 0 )
					countBuffer[0] = 1;
				if ( ENABLE_STREAMING_FEEDBACK )
					writeStreamingFeedback(instanceID);
			} else {
				var subPartID : Int = flags & 0xFFFF;
				var bucket = subPartID + lodSelected;
				instanceSlots[instanceID * 2] = bucket;
				instanceSlots[instanceID * 2 + 1] = atomicAdd(buckets, bucket * 2, 1);

				if ( cascadeCount > 0 ) {
					var posLs = position * cascadeView.mat3x4();
					var lightRot = cascadeView.mat3();
					var extentsLs = abs(boxAxes[0] * lightRot) + abs(boxAxes[1] * lightRot) + abs(boxAxes[2] * lightRot);
					var dimension = 2.0 * max(extentsLs.x, max(extentsLs.y, extentsLs.z));
					var inCascade = false;
					@unroll for ( c in 0...MAX_CASCADES ) {
						var cMin = cascadeMin[c];
						var cMax = cascadeMax[c];
						if ( c < cascadeCount && dimension >= cMin.w && insideOBB(posLs, extentsLs, cMin.xyz, cMax.xyz) ) {
							var cascadeBucket = (c + 1) * bucketCount + bucket;
							var instanceSlot = ((c + 1) * instanceCount + instanceID) * 2;
							instanceSlots[instanceSlot] = cascadeBucket;
							instanceSlots[instanceSlot + 1] = atomicAdd(buckets, cascadeBucket * 2, 1);
							inCascade = true;
						}
					}
					if ( ENABLE_STREAMING_FEEDBACK && inCascade )
						writeStreamingFeedback(instanceID);
				} else if ( ENABLE_STREAMING_FEEDBACK )
					writeStreamingFeedback(instanceID);
			}
		}
	}
}

@:allow(h3d.scene.EmitData)
private class BatchPass {
	static var shaderPerInstCache : Map<Int, Array<String>> = [];

	static final INDIRECT_DRAW_ARGUMENTS_FMT = hxd.BufferFormat.make([{ name : "", type : DVec4 }, { name : "", type : DFloat }]);
	static final PASS_INSTANCES_INFOS_FMT = hxd.BufferFormat.make([{ name : "flags", type : DFloat }]); // flags = subPartID(16 bits) + subMeshID(16 bits)

	static final modelViewID = hxsl.Globals.allocID("global.modelView");
	static final modelViewInverseID = hxsl.Globals.allocID("global.modelViewInverse");
	static final previousModelViewID = hxsl.Globals.allocID("global.previousModelView");

	public var primitive : h3d.prim.BatchPrimitive;
	public var pass : h3d.mat.Pass;
	public var batchShader : hxsl.BatchShader;
	public var shaders : Array<hxsl.Shader>;
	var batcher : Batcher;
	var isShadowPass = false;
	var modelViewOffset : Int;
	var modelViewPos : Int = -1;
	var modelViewInversePos : Int = -1;
	var previousModelViewPos : Int = -1;

	var hasSyncIDs = false;

	public var totalInstanceCount(default, null) = 0;
	var toEmit : Array<EmitData> = [];
	var instancesDirty = false;
	var instancesData : h3d.Buffer;
	var instancesInfos : h3d.Buffer;
	var instancesFormat : hxd.BufferFormat;
	var syncIDs : h3d.Buffer;

	var command : h3d.impl.InstanceBuffer;
	var commandBuffer : h3d.Buffer;
	var commandCapacity = 0;
	var commandSlots = 0;
	var emittedCascades = 0;
	var visibilityGeometry : h3d.Buffer;
	var visibilityFrustum : h3d.col.Frustum;
	var visibilityCamera = new h3d.Vector();
	var visibilityProjection = 0.;
	var visibilityLodScale = 0.;
	var countBuffer : h3d.GPUCounter;
	var builderShader = new BatchCommandBuilder();
	var bucketClearShader = new BatchBucketClear();
	var bucketCommandsShader = new BatchBucketCommands();
	var instanceScatterShader = new BatchInstanceScatter();
	var buckets : h3d.Buffer;
	var instanceSlots : h3d.Buffer;
	var visibleInstanceIds : h3d.Buffer;

	var bufferHandles : Array<h3d.BufferHandle>;
	var textureHandles : Array<h3d.mat.TextureHandle>;
	var textureHandlePos : Array<Int> = [];
	var textureHandlePosBuffer : h3d.Buffer;

	public function new(renderer : h3d.scene.Renderer, batch : Batch, p : h3d.mat.Pass, prim : h3d.prim.BatchPrimitive) @:privateAccess {
		primitive = prim;
		hasSyncIDs = batch.batcher.hasSyncIDs();
		var output = renderer.getPassByName(p.name);
		if( output == null )
			throw "Unknown pass " + p.name;

		pass = p.clone();
		var sl = pass.getShadersRec();

		var shaderLinker = output.output;
		var rt = shaderLinker.compileShaders(renderer.ctx.globals, sl, Default);
		batch.needLogicNormal = batch.needLogicNormal || rt.getInputFormat().hasInput("logicNormal");
		batcher = batch.batcher;

		var shaderVisited : Map<String, Bool> = [];
		var forcedPerInstance = [];
		for ( s in sl ) {
			var si = s.instance;
			var name = si.shader.name;
			if ( shaderVisited.exists(name) )
				continue;
			shaderVisited.set(name, true);
			var params = shaderPerInstCache.get(si.id);
			if (params == null) {
				params = [];
				for ( v in si.shader.vars ) {
					if ( v.kind != Param || !v.type.match(TSampler(_)|TInt|TFloat|TVec(_)|TBuffer(TInt|TFloat, _, _)) )
						continue;
					params.push(v.name);
				}
				shaderPerInstCache.set(si.id, params);
			}
			if ( params.length == 0 )
				continue;
			forcedPerInstance.push({ shader: name, params : params });
		}
		// perInstance needs to be in reverse order ?
		forcedPerInstance.reverse();
		batchShader = shaderLinker.shaderCache.makeBatchShader(rt, sl, new hxsl.Cache.BatchInstanceParams(forcedPerInstance, true));
		batchShader.Batch_UseStorage = true;
		batchShader.Batch_HasOffset = true;
		batchShader.constBits = 1 << 1 | 1 << 0;
		batchShader.updateConstants(null);

		shaders = [];
		while( sl != null ) {
			shaders.push(sl.s);
			sl = sl.next;
		}

		pass.addSelfShader(batchShader);
		pass.batchMode = true;
		pass.dynamicParameters = false;
		if ( batcher.globalShaders != null ) {
			var shaders = batcher.globalShaders.get("");
			if ( shaders != null )
				for ( s in shaders )
					pass.addShader(s);
			shaders = batcher.globalShaders.get(pass.name);
			if ( shaders != null )
				for ( s in shaders )
					pass.addSelfShader(s);
		}
		isShadowPass = pass.name == "shadow";
		var p = batchShader.params;
		while ( p != null ) {
			var g = p.perObjectGlobal;
			if ( g != null ) {
				if ( g.gid == modelViewID ) {
					modelViewOffset = p.pos >> 2;
					modelViewPos = p.pos;
				} else if ( g.gid == modelViewInverseID )
					modelViewInversePos = p.pos;
				else if ( g.gid == previousModelViewID )
					previousModelViewPos = p.pos;
				else
					throw "Unsupported global param " + g.path;
			} else if ( p.type.match(TTextureHandle | TSampler(_)) ) {
				textureHandlePos.push(p.pos);
			}
			p = p.next;
		}
	}

	public function getShaderData( sl : hxsl.ShaderList ) : ShaderData {
		var sd = new ShaderData();
		var p = batchShader.params;
		var shaders = [null/*link shader*/];
		while( sl != null ) {
			shaders.push(sl.s);
			sl = sl.next;
		}
		var shaderData = new hxd.FloatBuffer(batchShader.paramsSize * 4);
		while ( p != null ) {
			if( p.perObjectGlobal != null ) {
				if ( p.perObjectGlobal.gid != modelViewID && p.perObjectGlobal.gid != modelViewInverseID && p.perObjectGlobal.gid != previousModelViewID )
					throw "Unsupported global param " + p.perObjectGlobal.path;
				p = p.next;
				continue;
			}
			var bufLoader = new hxd.FloatBufferLoader(shaderData, p.pos);
			var curShader = shaders[p.instance];
			switch( p.type ) {
			case TVec(size, _):
				switch( size ) {
				case 2:
					var v : h3d.Vector = curShader.getParamValue(p.index);
					bufLoader.loadVec2(v);
				case 3:
					var v : h3d.Vector = curShader.getParamValue(p.index);
					bufLoader.loadVec3(v);
				case 4:
					var v : h3d.Vector4 = curShader.getParamValue(p.index);
					bufLoader.loadVec4(v);
				}
			case TFloat:
				bufLoader.loadFloat(curShader.getParamFloatValue(p.index));
			case TInt:
				bufLoader.loadInt(Std.int(curShader.getParamFloatValue(p.index)));
			case TMat4:
				var m : h3d.Matrix = curShader.getParamValue(p.index);
				bufLoader.loadMatrix(m);
			case TBufferHandle:
				if ( sd.bufferHandles == null )
					sd.bufferHandles = [];
				var h : h3d.BufferHandle = curShader.getParamValue(p.index);
				if ( sd.bufferHandles.indexOf(h) < 0 )
					sd.bufferHandles.push(h);
				bufLoader.loadInt(h.handle);
			case TBuffer(_):
				if ( sd.bufferHandles == null )
					sd.bufferHandles = [];
				var b : h3d.Buffer = curShader.getParamValue(p.index);
				if (b != null) {
					var h = b.getHandle();
					if ( sd.bufferHandles.indexOf(h) < 0 )
						sd.bufferHandles.push(h);
					bufLoader.loadInt(h.handle);
				}
			case TTextureHandle:
				if ( sd.textureHandles == null )
					sd.textureHandles = [];
				var h : h3d.mat.TextureHandle = curShader.getParamValue(p.index);
				if ( sd.textureHandles.indexOf(h) < 0 )
					sd.textureHandles.push(h);
				bufLoader.loadInt(h.handle.low);
				bufLoader.loadInt(h.handle.high);
			case TSampler(_):
				if ( sd.textureHandles == null )
					sd.textureHandles = [];
				var t : h3d.mat.Texture = curShader.getParamValue(p.index);
				if(t != null) {
					var h = t.getHandle();
					if ( sd.textureHandles.indexOf(h) < 0 )
						sd.textureHandles.push(h);
					bufLoader.loadInt(h.handle.low);
					bufLoader.loadInt(h.handle.high);
				}
			default:
				throw "Unsupported per instance type "+p.type;
			}
			p = p.next;
		}
		sd.data = shaderData;
		return sd;
	}

	public function uploadInstances() {
		if ( !instancesDirty && instancesData != null && !instancesData.isDisposed() &&
			instancesInfos != null && !instancesInfos.isDisposed() && (!hasSyncIDs || (syncIDs != null && !syncIDs.isDisposed())) )
			return;
		var alloc = hxd.impl.Allocator.get();

		inline function allocBuffer(size, format, flags) {
			return alloc.allocBuffer(hxd.impl.Allocator.roundPOT(size), format, flags);
		}

		var realloc = false;
		var instanceDataSize = totalInstanceCount * batchShader.paramsSize;
		if ( instancesData == null || instancesData.isDisposed() || instancesData.vertices < instanceDataSize ) {
			if ( instancesData != null )
				alloc.disposeBuffer(instancesData);
			instancesData = allocBuffer( instanceDataSize, hxd.BufferFormat.VEC4_DATA, UniformReadWrite );
			realloc = true;
		}
		batchShader.Batch_StorageBuffer = instancesData;

		if ( hasSyncIDs ) {
			if ( syncIDs == null || syncIDs.isDisposed() || syncIDs.vertices < totalInstanceCount ) {
				if ( syncIDs != null )
					alloc.disposeBuffer(syncIDs);
				syncIDs = allocBuffer( totalInstanceCount, hxd.BufferFormat.INDEX32, Uniform );
				realloc = true;
			}
		}

		if ( instancesInfos == null || instancesInfos.isDisposed() || instancesInfos.vertices < totalInstanceCount ) {
			if ( instancesInfos != null )
				alloc.disposeBuffer(instancesInfos);
			instancesInfos = allocBuffer( totalInstanceCount, PASS_INSTANCES_INFOS_FMT, Uniform );
			realloc = true;
		}

		var instanceCursor = 0;
		if ( bufferHandles != null )
			bufferHandles.resize(0);
		if ( textureHandles != null )
			textureHandles.resize(0);
		for ( ed in toEmit ) {
			if ( ed.bufferRefs != null ) {
				if ( bufferHandles == null )
					bufferHandles = [];
				for ( bh in ed.bufferRefs.keys() )
					if ( bufferHandles.indexOf(bh) < 0 )
						bufferHandles.push(bh);
			}
			if ( ed.textureRefs != null ) {
				if ( textureHandles == null )
					textureHandles = [];
				for ( th in ed.textureRefs.keys() )
					if ( textureHandles.indexOf(th) < 0 )
						textureHandles.push(th);
			}

			var first = ( realloc || ed.uploadCursor != instanceCursor ) ? 0 : ed.uploadedCount;
			var count = ed.instanceCount - first;
			if ( hasSyncIDs && count > 0 )
				syncIDs.uploadBytes(ed.syncIDs, first * 4, count, instanceCursor + first);
			var infoFirst = hxd.Math.imin(first, ed.dirtyInfoFirst);
			var infoEnd = count > 0 ? ed.instanceCount : ed.dirtyInfoEnd;
			if( infoEnd > infoFirst )
				instancesInfos.uploadBytes(ed.instancesInfos, infoFirst * PASS_INSTANCES_INFOS_FMT.strideBytes,
					infoEnd - infoFirst, instanceCursor + infoFirst);

			ed.dirtyInfoFirst = ed.instanceCount;
			ed.dirtyInfoEnd = 0;
			var dataFirst = hxd.Math.imin(first, ed.dirtyTransformFirst);
			var dataEnd = count > 0 ? ed.instanceCount : ed.dirtyTransformEnd;
			if( dataEnd > dataFirst ) {
				var stride = batchShader.paramsSize;
				instancesData.uploadFloats(ed.instancesData, dataFirst * stride * 4, (dataEnd - dataFirst) * stride,
					(instanceCursor + dataFirst) * stride);
			}
			ed.dirtyTransformFirst = ed.instanceCount;
			ed.dirtyTransformEnd = 0;
			ed.uploadCursor = instanceCursor;
			ed.uploadedCount = ed.instanceCount;
			instanceCursor += ed.instanceCount;
		}
		instancesDirty = false;
	}

	function checkCommandBuffer( slots : Int, singleBucket : Bool ) {
		var alloc = hxd.impl.Allocator.get();
		var bucketCount = primitive.gpuSubPartInfos.vertices;
		var maxCommandCount = hxd.Math.imin(totalInstanceCount, bucketCount);

		inline function allocBuffer(size, format, flags) {
			return alloc.allocBuffer(hxd.impl.Allocator.roundPOT(size), format, flags);
		}

		if ( !singleBucket && (buckets == null || buckets.isDisposed() || buckets.vertices < bucketCount * slots * 2) ) {
			if ( buckets != null )
				alloc.disposeBuffer(buckets);
			buckets = allocBuffer(bucketCount * slots * 2, hxd.BufferFormat.INDEX32, UniformReadWrite);
		}
		if ( !singleBucket && (instanceSlots == null || instanceSlots.isDisposed() || instanceSlots.vertices < totalInstanceCount * slots * 2) ) {
			if ( instanceSlots != null )
				alloc.disposeBuffer(instanceSlots);
			instanceSlots = allocBuffer(totalInstanceCount * slots * 2, hxd.BufferFormat.INDEX32, UniformReadWrite);
		}
		if ( visibleInstanceIds == null || visibleInstanceIds.isDisposed() || visibleInstanceIds.vertices < totalInstanceCount * slots ) {
			if ( visibleInstanceIds != null )
				alloc.disposeBuffer(visibleInstanceIds);
			visibleInstanceIds = allocBuffer(totalInstanceCount * slots, hxd.BufferFormat.INDEX32, UniformReadWrite);
		}
		batchShader.Batch_InstanceIds = visibleInstanceIds;

		var prevSlots = commandSlots;
		if ( commandBuffer == null || commandBuffer.isDisposed() || commandCapacity < maxCommandCount || commandSlots < slots ) {
			if ( commandBuffer != null )
				alloc.disposeBuffer(commandBuffer);
			commandCapacity = hxd.Math.imax(commandCapacity, hxd.impl.Allocator.roundPOT(maxCommandCount));
			commandSlots = hxd.Math.imax(commandSlots, slots);
			commandBuffer = alloc.allocBuffer( commandCapacity * commandSlots, INDIRECT_DRAW_ARGUMENTS_FMT, UniformReadWrite );
			if ( command == null )
				command = new h3d.impl.InstanceBuffer();
			@:privateAccess command.data = commandBuffer.vbuf;
		}
		if ( countBuffer == null || countBuffer.buffer.isDisposed() || prevSlots != commandSlots ) {
			countBuffer?.dispose();
			countBuffer = new GPUCounter(commandSlots * 2);
			@:privateAccess command.countBuffer = countBuffer.buffer.vbuf;
		}
	}

	public function syncGPU(ctx : h3d.scene.RenderContext) {
		uploadInstances();
		var s = batcher.syncShader;
		s.instancesData = instancesData;
		s.instanceStride = batchShader.paramsSize;
		s.modelViewOffset = modelViewOffset;
		s.instanceCount = totalInstanceCount;
		s.syncIDs = syncIDs;
		ctx.computeDispatch(cast s, hxd.Math.ceil(totalInstanceCount/64.0), false);
	}

	public function fitsGpuLimits(ctx : RenderContext) {
		var slots = isShadowPass ? batcher.prepareCascades(ctx) + 1 : 1;
		var visible : Float = totalInstanceCount * 1.0 * slots;
		var data : Float = totalInstanceCount * 1.0 * batchShader.paramsSize;
		if( visible > 0x1000000 || data > 0x4000000 )
			return false;

		#if (hl && limen && gfx_vulkan)
		var vk = Std.downcast(ctx.engine.driver, h3d.impl.driver.vulkan.VulkanDriver);
		if( vk != null ) @:privateAccess {
			var limits = vk.limits;
			var buckets = primitive.gpuSubPartInfos.vertices;
			var draws = hxd.Math.imin(totalInstanceCount, buckets);
			if( limits.maxDrawIndirectCount >= 0 && draws > limits.maxDrawIndirectCount )
				return false;

			var maxStorage = limits.maxStorageBufferRange;
			if( maxStorage >= 0 && (hxd.impl.Allocator.roundPOT(Std.int(data)) * 16.0 > maxStorage ||
				hxd.impl.Allocator.roundPOT(Std.int(visible * 2)) * 4.0 > maxStorage ||
				hxd.impl.Allocator.roundPOT(draws) * slots * 20.0 > maxStorage ||
				primitive.gpuSubMeshInfos.getMemSize() > maxStorage || primitive.gpuSubPartInfos.getMemSize() > maxStorage ||
				primitive.gpuLodInfos.getMemSize() > maxStorage) )
				return false;

			var groups = Math.ceil(visible / 64.);
			if( hxd.Math.min(groups, 65535.) > limits.maxComputeWorkGroupCount ||
				Math.ceil(groups / 65535.) > limits.maxComputeWorkGroupCount1 )
				return false;
		}
		#end
		return true;
	}

	function canReuseVisibility(cascades : Int) {
		return batcher.reuseVisibility && !batcher.batchFlags.has(ManualEmitGPU) &&
			!batcher.isRelative && batcher.syncShader == null && !batcher.hzbCulling && cascades == 0 &&
			textureHandlePos.length == 0 && (!isShadowPass || (!batcher.shadowCameraFrustumCulling && batcher.shadowMaxDistance <= 0));
	}

	function visibilityMatches(ctx : RenderContext) {
		if( visibilityGeometry != primitive.gpuSubMeshInfos || visibilityFrustum == null ||
			visibleInstanceIds.isDisposed() || commandBuffer.isDisposed() || countBuffer.buffer.isDisposed() ||
			visibilityLodScale != ctx.meshLodScale || visibilityProjection != hxd.Math.max(ctx.camera.mproj._11, ctx.camera.mproj._22) ||
			visibilityCamera.x != ctx.camera.pos.x || visibilityCamera.y != ctx.camera.pos.y || visibilityCamera.z != ctx.camera.pos.z )
			return false;

		var a = visibilityFrustum;
		var b = ctx.camera.frustum;
		inline function same(a : h3d.col.Plane, b : h3d.col.Plane) @:privateAccess {
			return a.nx == b.nx && a.ny == b.ny && a.nz == b.nz && a.d == b.d;
		}
		return isShadowPass || (a.checkNearFar == b.checkNearFar && same(a.pleft, b.pleft) &&
			same(a.pright, b.pright) && same(a.ptop, b.ptop) && same(a.pbottom, b.pbottom) &&
			(!a.checkNearFar || (same(a.pnear, b.pnear) && same(a.pfar, b.pfar))));
	}

	function rememberVisibility(ctx : RenderContext) {
		var f = ctx.camera.frustum;
		if( visibilityFrustum == null )
			visibilityFrustum = f.clone();
		else {
			visibilityFrustum.pleft.load(f.pleft);
			visibilityFrustum.pright.load(f.pright);
			visibilityFrustum.ptop.load(f.ptop);
			visibilityFrustum.pbottom.load(f.pbottom);
			visibilityFrustum.pnear.load(f.pnear);
			visibilityFrustum.pfar.load(f.pfar);
			visibilityFrustum.checkNearFar = f.checkNearFar;
		}
		visibilityGeometry = primitive.gpuSubMeshInfos;
		visibilityCamera.set(ctx.camera.pos.x, ctx.camera.pos.y, ctx.camera.pos.z);
		visibilityProjection = hxd.Math.max(ctx.camera.mproj._11, ctx.camera.mproj._22);
		visibilityLodScale = ctx.meshLodScale;
	}

	public function emitGPU(ctx : h3d.scene.RenderContext) {
		var dirty = instancesDirty || instancesData == null || instancesData.isDisposed() ||
			instancesInfos == null || instancesInfos.isDisposed();
		uploadInstances();
		var cascades = isShadowPass ? batcher.prepareCascades(ctx) : 0;
		var cache = canReuseVisibility(cascades);
		if( cache && !dirty && visibilityMatches(ctx) )
			return;

		visibilityGeometry = null;
		var dispatches = ctx.engine.dispatches;
		var slots = cascades + 1;
		var bucketCount = primitive.gpuSubPartInfos.vertices;
		var singleBucket = bucketCount == 1 && slots == 1;
		checkCommandBuffer(slots, singleBucket);
		builderShader.singleBucket = singleBucket;
		builderShader.commandBuffer = commandBuffer;
		builderShader.countBuffer = countBuffer.buffer;
		builderShader.visibleInstanceIds = visibleInstanceIds;
		emittedCascades = cascades;
		builderShader.instancesData = instancesData;
		builderShader.instanceStride = batchShader.paramsSize;
		builderShader.modelViewOffset = modelViewOffset;
		builderShader.instancesInfos = instancesInfos;
		builderShader.subMeshInfos = primitive.gpuSubMeshInfos;
		builderShader.lodInfos = primitive.gpuLodInfos;
		builderShader.instanceCount = totalInstanceCount;
		builderShader.buckets = buckets;
		builderShader.instanceSlots = instanceSlots;
		builderShader.bucketCount = primitive.gpuSubPartInfos.vertices;
		builderShader.IS_RELATIVE = batcher.isRelative;
		builderShader.worldMatrix = batcher.getAbsPos();

		builderShader.frustum = ctx.getCameraFrustumBuffer();
		builderShader.frustumPlaneCount = ctx.camera.frustum.checkNearFar ? 6 : 4;

		builderShader.cascadeCount = cascades;
		builderShader.cascadeView = batcher.cascadeView;
		builderShader.cascadeMin = batcher.cascadeMin;
		builderShader.cascadeMax = batcher.cascadeMax;

		if ( isShadowPass ) {
			builderShader.ENABLE_FRUSTUM_CULLING = batcher.shadowCameraFrustumCulling;
			builderShader.ENABLE_HZB_CULLING = false;
			builderShader.ENABLE_DISTANCE_CLIPPING = batcher.shadowMaxDistance > 0.0;
			builderShader.maxDistance = batcher.shadowMaxDistance;
		} else {
			builderShader.ENABLE_FRUSTUM_CULLING = true;
			builderShader.ENABLE_DISTANCE_CLIPPING = false;
			var pyramid = batcher.hzbCulling ? @:privateAccess ctx.getBatchOcclusionPyramid() : null;
			builderShader.ENABLE_HZB_CULLING = pyramid != null;
			builderShader.hzb = pyramid;
			if ( pyramid != null ) {
				builderShader.hzbSize.set(pyramid.width, pyramid.height);
				builderShader.hzbMipCount = pyramid.mipLevels;
				builderShader.reverseDepth = ctx.camera.reverseDepth;
			}
		}

		builderShader.meshLodScale = ctx.meshLodScale;
		setupStreamingFeedback(ctx);

		var bucketGroups = hxd.Math.ceil(bucketCount * slots/64.0);
		bucketClearShader.buckets = buckets;
		bucketClearShader.bucketCount = bucketCount * slots;
		bucketClearShader.slotCount = slots;
		bucketClearShader.countBuffer = countBuffer.buffer;
		bucketClearShader.singleBucket = singleBucket;
		bucketClearShader.subPartInfos = primitive.gpuSubPartInfos;
		bucketClearShader.commandBuffer = commandBuffer;
		ctx.computeDispatch(bucketClearShader, bucketGroups);
		dispatchInstances(ctx, builderShader, totalInstanceCount);
		if( singleBucket ) {
			if( cache && ctx.engine.dispatches == dispatches + 2 )
				rememberVisibility(ctx);
			return;
		}
		ctx.memoryBarrier();
		bucketCommandsShader.buckets = buckets;
		bucketCommandsShader.bucketCount = bucketCount;
		bucketCommandsShader.slotCount = slots;
		bucketCommandsShader.commandCapacity = commandCapacity;
		bucketCommandsShader.instanceCount = totalInstanceCount;
		bucketCommandsShader.subPartInfos = primitive.gpuSubPartInfos;
		bucketCommandsShader.countBuffer = countBuffer.buffer;
		bucketCommandsShader.commandBuffer = commandBuffer;
		ctx.computeDispatch(bucketCommandsShader, bucketGroups);
		instanceScatterShader.buckets = buckets;
		instanceScatterShader.instanceSlots = instanceSlots;
		instanceScatterShader.visibleInstanceIds = visibleInstanceIds;
		instanceScatterShader.instanceCount = totalInstanceCount;
		instanceScatterShader.slotCount = slots;
		dispatchInstances(ctx, instanceScatterShader, totalInstanceCount * slots);
		if( cache && ctx.engine.dispatches == dispatches + 4 )
			rememberVisibility(ctx);
	}

	function dispatchInstances(ctx : RenderContext, shader : hxsl.Shader, count : Int) {
		var groups = (count + 63) >> 6;
		ctx.computeDispatch(shader, hxd.Math.imin(groups, 65535), Std.int((groups + 65534) / 65535), 1, false);
	}

	function setupStreamingFeedback( ctx : h3d.scene.RenderContext ) {
		var fb = textureHandlePos.length > 0 && textureHandles != null ? ctx.getStreamingFeedback() : null;
		if ( fb == null || !fb.isActive() ) {
			builderShader.ENABLE_STREAMING_FEEDBACK = false;
			return;
		}
		if ( textureHandlePosBuffer == null ) {
			var bytes = haxe.io.Bytes.alloc(textureHandlePos.length << 2);
			for ( i in 0...textureHandlePos.length )
				bytes.setInt32(i << 2, textureHandlePos[i]);
			textureHandlePosBuffer = new h3d.Buffer(textureHandlePos.length, hxd.BufferFormat.INDEX32, [UniformBuffer]);
			textureHandlePosBuffer.uploadBytes(bytes, 0, textureHandlePos.length);
		}
		builderShader.ENABLE_STREAMING_FEEDBACK = true;
		builderShader.streamingFeedback = fb.getBuffer();
		builderShader.feedbackSize = fb.getSize();
		builderShader.textureHandlePos = textureHandlePosBuffer;
		builderShader.textureHandleCount = textureHandlePos.length;
		fb.track(textureHandles);
	}

	public function draw( ctx : h3d.scene.RenderContext ) {
		var fb = ctx.streamingFeedback;
		if ( textureHandles != null )
			ctx.selectTextureHandles( textureHandles, fb == null || !fb.isActive() );
		if ( bufferHandles != null )
			ctx.selectBufferHandles( bufferHandles );
		var engine = ctx.engine;
		@:privateAccess engine.driver.selectMultiBuffers(primitive.formats, primitive.buffers);
		var slot = isShadowPass ? batcher.getShadowSlot(ctx, emittedCascades) : 0;
		@:privateAccess {
			command.commandCount = hxd.Math.imin(totalInstanceCount, primitive.gpuSubPartInfos.vertices);
			command.offset = slot * commandCapacity;
			command.countOffset = slot * 2;
		}
		engine.renderInstanced(primitive.indexes, command);
	}

	public function dispose() {
		var alloc = hxd.impl.Allocator.get();
		if ( buckets != null ) {
			alloc.disposeBuffer(buckets);
			buckets = null;
		}
		if ( instanceSlots != null ) {
			alloc.disposeBuffer(instanceSlots);
			instanceSlots = null;
		}
		if ( visibleInstanceIds != null ) {
			alloc.disposeBuffer(visibleInstanceIds);
			visibleInstanceIds = null;
		}
		if ( instancesData != null ) {
			alloc.disposeBuffer(instancesData);
			instancesData = null;
		}
		if ( instancesInfos != null ) {
			alloc.disposeBuffer(instancesInfos);
			instancesInfos = null;
		}
		if ( commandBuffer != null ) {
			alloc.disposeBuffer(commandBuffer);
			commandBuffer = null;
		}
		commandCapacity = 0;
		commandSlots = 0;
		emittedCascades = 0;
		if( syncIDs != null ) {
			alloc.disposeBuffer(syncIDs);
			syncIDs = null;
		}
		countBuffer?.dispose();
		countBuffer = null;
		textureHandlePosBuffer?.dispose();
		textureHandlePosBuffer = null;
		command = null;
		commandCapacity = commandSlots = 0;
		visibilityGeometry = null;
	}
}

@:allow(h3d.scene.BatchPass)
private class EmitData {
	public var instanceCount(default, null) : Int;
	var instancesInfos : haxe.io.Bytes;
	var instancesData : hxd.FloatBuffer;
	var syncIDs : haxe.io.Bytes;
	var batchPass : BatchPass;
	var bufferRefs : Map<h3d.BufferHandle, Int>;
	var textureRefs : Map<h3d.mat.TextureHandle, Int>;
	var capacity : Int = 0;
	var tmpInverse = new h3d.Matrix();
	var uploadCursor = -1;
	var uploadedCount = 0;
	var dirtyTransformFirst = 0;
	var dirtyTransformEnd = 0;
	var dirtyInfoFirst = 0;
	var dirtyInfoEnd = 0;

	public function new(bp : BatchPass) {
		batchPass = bp;
		bp.toEmit.push(this);
	};

	function growBytes( b : haxe.io.Bytes, count : Int, stride : Int ) {
		if ( b == null )
			return haxe.io.Bytes.alloc(hxd.Math.imax(count, capacity) * stride);
		var minSize = count * stride;
		if ( b.length >= minSize )
			return b;
		var n = haxe.io.Bytes.alloc( hxd.Math.imax((b.length >> 1) * 3, minSize) );
		n.blit(0, b, 0, b.length);
		return n;
	}

	public inline function reserve( count : Int ) {
		capacity += count;
	}

	inline function writeMatrix( pos : Int, m : h3d.Matrix ) {
		instancesData[pos++] = m._11;
		instancesData[pos++] = m._21;
		instancesData[pos++] = m._31;
		instancesData[pos++] = m._41;
		instancesData[pos++] = m._12;
		instancesData[pos++] = m._22;
		instancesData[pos++] = m._32;
		instancesData[pos++] = m._42;
		instancesData[pos++] = m._13;
		instancesData[pos++] = m._23;
		instancesData[pos++] = m._33;
		instancesData[pos++] = m._43;
		instancesData[pos++] = m._14;
		instancesData[pos++] = m._24;
		instancesData[pos++] = m._34;
		instancesData[pos++] = m._44;
	}

	public function emitInstance( subMeshID : Int, subPartID : Int, shaderData : ShaderData, worldPosition : h3d.Matrix, syncID : Int ) {
		if( subPartID < 0 || subPartID > 0xFFFF || subMeshID < 0 || subMeshID > 0xFFFF )
			throw "GPU batch mesh or subpart ID exceeds 16 bits";

		retainResources(shaderData);
		batchPass.instancesDirty = true;
		batchPass.totalInstanceCount++;
		var instanceID = instanceCount++;

		var instanceInfosStride = BatchPass.PASS_INSTANCES_INFOS_FMT.strideBytes;
		instancesInfos = growBytes(instancesInfos, instanceCount, instanceInfosStride);
		instancesInfos.setInt32(instanceID * instanceInfosStride, subMeshID << 16 | subPartID );

		if ( batchPass.hasSyncIDs ) {
			syncIDs = growBytes(syncIDs, instanceCount, 4);
			syncIDs.setInt32(instanceID << 2, syncID);
		}

		var instanceDataStride = batchPass.batchShader.paramsSize * 4;
		var minInstanceDataSize = instanceCount * instanceDataStride;
		if ( instancesData == null )
			instancesData = new hxd.FloatBuffer(hxd.Math.imax(instanceCount, capacity) * instanceDataStride);
		if ( instancesData.length < minInstanceDataSize)
			instancesData.grow((minInstanceDataSize >> 1) * 3);

		writeShaderData(instanceID, shaderData);
		writeTransform(instanceID * instanceDataStride, worldPosition, worldPosition);
	}

	function retainResources(shaderData : ShaderData) {
		if( shaderData.bufferHandles != null ) {
			if( bufferRefs == null )
				bufferRefs = [];
			for( handle in shaderData.bufferHandles )
				bufferRefs.set(handle, (bufferRefs.get(handle) ?? 0) + 1);
		}
		if( shaderData.textureHandles != null ) {
			if( textureRefs == null )
				textureRefs = [];
			for( handle in shaderData.textureHandles )
				textureRefs.set(handle, (textureRefs.get(handle) ?? 0) + 1);
		}
	}

	function replaceInstance(index : Int, mesh : Int, part : Int, old : ShaderData, next : ShaderData,
		worldPosition : h3d.Matrix, previousPosition : h3d.Matrix) {
		if( old != next ) {
			retainResources(next);
			if( old.bufferHandles != null )
				for( handle in old.bufferHandles ) {
					var refs = bufferRefs.get(handle) - 1;
					if( refs == 0 ) bufferRefs.remove(handle); else bufferRefs.set(handle, refs);
				}
			if( old.textureHandles != null )
				for( handle in old.textureHandles ) {
					var refs = textureRefs.get(handle) - 1;
					if( refs == 0 ) textureRefs.remove(handle); else textureRefs.set(handle, refs);
				}
			writeShaderData(index, next);
		}

		var offset = index * BatchPass.PASS_INSTANCES_INFOS_FMT.strideBytes;
		var packed = mesh << 16 | part;
		if( instancesInfos.getInt32(offset) != packed ) {
			instancesInfos.setInt32(offset, packed);
			dirtyInfoFirst = hxd.Math.imin(dirtyInfoFirst, index);
			dirtyInfoEnd = hxd.Math.imax(dirtyInfoEnd, index + 1);
		}

		updateTransform(index, worldPosition, previousPosition);
	}

	function writeShaderData(instanceID : Int, shaderData : ShaderData) {
		var instanceDataStride = batchPass.batchShader.paramsSize * 4;
		#if hl
		var instanceByteStride = instanceDataStride * 4;
		var instanceByteStart = instanceID * instanceByteStride;
		var dst = hl.Bytes.getArray(instancesData.getNative());
		var src = hl.Bytes.getArray(shaderData.data.getNative());
		dst.blit(instanceByteStart, src, 0, instanceByteStride);
		#else
		var data = shaderData.data;
		var instanceDataStart = instanceID * instanceDataStride;
		for ( i in 0...instanceDataStride )
			instancesData[instanceDataStart + i] = data[i];
		#end

	}

	function updateTransform(index : Int, worldPosition : h3d.Matrix, previousPosition : h3d.Matrix) {
		writeTransform(index * batchPass.batchShader.paramsSize * 4, worldPosition, previousPosition);
		dirtyTransformFirst = hxd.Math.imin(dirtyTransformFirst, index);
		dirtyTransformEnd = hxd.Math.imax(dirtyTransformEnd, index + 1);
		batchPass.instancesDirty = true;
	}

	function writeTransform(instanceDataStart : Int, worldPosition : h3d.Matrix, previousPosition : h3d.Matrix) {
		var bp = batchPass;
		if ( bp.modelViewPos >= 0 )
			writeMatrix(instanceDataStart + bp.modelViewPos, worldPosition);
		if ( bp.previousModelViewPos >= 0 )
			writeMatrix(instanceDataStart + bp.previousModelViewPos, previousPosition);
		if ( bp.modelViewInversePos >= 0 ) {
			tmpInverse.inverse3x4(worldPosition);
			writeMatrix(instanceDataStart + bp.modelViewInversePos, tmpInverse);
		}
	}

	public function dispose() {
		batchPass.instancesDirty = true;
		if ( batchPass.totalInstanceCount < instanceCount )
			throw "assert";
		batchPass.totalInstanceCount -= instanceCount;
		batchPass.toEmit.remove(this);
		batchPass = null;
		instancesData = null;
		instancesInfos = null;
		bufferRefs = null;
		textureRefs = null;
		instanceCount = 0;
		capacity = 0;
	}
}
