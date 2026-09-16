package h3d.impl.driver.vulkan.shader;

#if (limen && gfx_vulkan)
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanShaderAbi;
import h3d.impl.driver.vulkan.shader.VulkanShaderAbi.VulkanShaderStage;
import limen.graphics.vulkan.internal.VulkanBindings.ShaderKind;
import limen.graphics.vulkan.shader.ShaderCompiler;
import limen.graphics.vulkan.shader.ShaderCompiler.ShaderCompileRequest;
import limen.graphics.vulkan.shader.ShaderCompiler.ShaderOptimizationMode;
import limen.graphics.vulkan.shader.SpirvReflection;

class VulkanCompiledStageSource {
	public final stage:VulkanShaderStage;
	public final sourceName:String;
	public final entryPoint:String;
	public final source:String;
	public final sourceHash:String;
	public final spirv:haxe.io.Bytes;
	public final spirvHash:String;
	public final reflection:SpirvReflection;

	public function new(stage, sourceName, entryPoint, source, sourceHash, spirv, spirvHash, reflection) {
		this.stage = stage;
		this.sourceName = sourceName;
		this.entryPoint = entryPoint;
		this.source = source;
		this.sourceHash = sourceHash;
		this.spirv = spirv;
		this.spirvHash = spirvHash;
		this.reflection = reflection;
	}
}

class VulkanCompiledProgramData {
	public final cacheKey:String;
	public final stages:Array<VulkanCompiledStageSource>;

	public function new(cacheKey:String, stages:Array<VulkanCompiledStageSource>) {
		this.cacheKey = cacheKey;
		this.stages = stages.copy();
	}

	public function requireStage(stage:VulkanShaderStage):VulkanCompiledStageSource {
		for (value in stages)
			if (value.stage == stage)
				return value;
		throw 'Compiled Vulkan shader program $cacheKey has no ${VulkanShaderAbi.stageName(stage)} stage';
	}
}

private typedef GeneratedStage = {
	var stage:VulkanShaderStage;
	var kind:ShaderKind;
	var sourceName:String;
	var source:String;
	var sourceHash:String;
}

class VulkanShaderCompilerService {
	final compiler = new ShaderCompiler();
	final cache:Map<String, VulkanCompiledProgramData> = new Map();
	final optimization:ShaderOptimizationMode;
	final debugInfo:Bool;

	public function new() {
		#if debug
		optimization = None;
		debugInfo = true;
		#else
		optimization = Performance;
		debugInfo = false;
		#end
	}

	public function compile(shader:hxsl.RuntimeShader, abi:VulkanShaderAbi):VulkanCompiledProgramData {
		final generated = generate(shader, abi);
		final cacheKey = makeCacheKey(shader, abi, generated);
		final cached = cache.get(cacheKey);
		if (cached != null)
			return cached;

		final stages = [];
		for (stage in generated) {
			saveGeneratedArtifact(stage, cacheKey);
			final request = new ShaderCompileRequest(stage.source, stage.sourceName, "main", stage.kind, Vulkan13, Spirv16,
				optimization, debugInfo, true);
			final result = compiler.compile(request);
			if (!result.succeeded) {
				saveFailureArtifact(stage, cacheKey);
				throw 'Vulkan shader compilation failed: program=${shader.signature}, stage=${VulkanShaderAbi.stageName(stage.stage)}, '
					+ 'source=${stage.sourceName}, entry=main, target=Vulkan 1.3/SPIR-V 1.6, status=${result.status}, '
					+ 'warnings=${result.warnings}, errors=${result.errors}\n${result.diagnostics}';
			}
			final spirv = result.spirv;
			final reflection = try SpirvReflection.reflect(spirv) catch (error:Dynamic) {
				saveFailureArtifact(stage, cacheKey);
				throw 'Vulkan SPIR-V validation/reflection failed: program=${shader.signature}, stage=${VulkanShaderAbi.stageName(stage.stage)}, '
					+ 'source=${stage.sourceName}, target=Vulkan 1.3/SPIR-V 1.6: $error';
			};
			VulkanShaderAbiVerifier.verifyStage(abi, stage.stage, reflection);
			final compiled = new VulkanCompiledStageSource(stage.stage, stage.sourceName, "main", stage.source, stage.sourceHash,
				spirv, haxe.crypto.Sha256.make(spirv).toHex(), reflection);
			stages.push(compiled);
			saveSuccessArtifacts(compiled, cacheKey);
		}
		if (shader.mode != Compute)
			VulkanShaderAbiVerifier.verifyGraphicsLink(findReflection(stages, Vertex), findReflection(stages, Fragment));
		final program = new VulkanCompiledProgramData(cacheKey, stages);
		cache.set(cacheKey, program);
		return program;
	}

	public function dispose() {
		compiler.dispose();
		cache.clear();
	}

	function generate(shader:hxsl.RuntimeShader, abi:VulkanShaderAbi):Array<GeneratedStage> {
		final identity = haxe.crypto.Sha256.encode(shader.signature == null ? Std.string(shader.id) : shader.signature).substr(0, 16);
		final result = [];
		if (shader.mode == Compute)
			result.push(generateStage(shader.compute, Compute, ShaderKind.Compute, identity, abi));
		else {
			result.push(generateStage(shader.vertex, Vertex, ShaderKind.Vertex, identity, abi));
			result.push(generateStage(shader.fragment, Fragment, ShaderKind.Fragment, identity, abi));
		}
		return result;
	}

	function generateStage(data:hxsl.RuntimeShader.RuntimeShaderData, stage:VulkanShaderStage, kind:ShaderKind, identity:String, abi:VulkanShaderAbi):GeneratedStage {
		final output = new hxsl.GlslOut();
		output.version = 450;
		output.isVulkan = true;
		output.vulkanLayout = abi.glslLayout(stage);
		final source = output.run(data.data);
		final stageName = VulkanShaderAbi.stageName(stage).toLowerCase();
		return {
			stage: stage,
			kind: kind,
			sourceName: 'hxsl-$identity-$stageName.glsl',
			source: source,
			sourceHash: haxe.crypto.Sha256.encode(source),
		};
	}

	function makeCacheKey(shader:hxsl.RuntimeShader, abi:VulkanShaderAbi, stages:Array<GeneratedStage>):String {
		final identity = shader.signature == null ? 'runtime:${shader.id}' : shader.signature;
		final sourceHashes = [for (stage in stages) '${stage.stage}:${stage.sourceHash}'].join("|");
		final options = 'vulkan=1.3|spirv=1.6|optimization=$optimization|debug=$debugInfo|warningsAsErrors=true';
		return haxe.crypto.Sha256.encode('$identity|sources=$sourceHashes|abi=${abi.version}|$options|capabilities=${VulkanShaderAbi.CAPABILITY_MODE}');
	}

	static function findReflection(stages:Array<VulkanCompiledStageSource>, stage:VulkanShaderStage):SpirvReflection {
		for (value in stages)
			if (value.stage == stage)
				return value.reflection;
		throw 'Missing ${VulkanShaderAbi.stageName(stage)} reflection';
	}

	static function artifactDirectory():Null<String> {
		#if sys
		final root = Sys.getEnv("VULKAN_SHADER_ARTIFACT_DIR");
		if (root != null && root.length != 0)
			return root;
		final runDirectory = Sys.getEnv("VERIFY_RUN_DIR");
		return runDirectory == null || runDirectory.length == 0 ? null : haxe.io.Path.join([runDirectory, "shaders"]);
		#else
		return null;
		#end
	}

	static function saveFailureArtifact(stage:GeneratedStage, cacheKey:String) {
		#if sys
		final directory = artifactDirectory();
		if (directory == null)
			return;
		sys.FileSystem.createDirectory(directory);
		final name = '${cacheKey.substr(0, 16)}-${VulkanShaderAbi.stageName(stage.stage).toLowerCase()}';
		sys.io.File.saveContent(haxe.io.Path.join([directory, '$name.glsl']), stage.source);
		#end
	}

	static function saveGeneratedArtifact(stage:GeneratedStage, cacheKey:String) {
		#if (sys && debug)
		final directory = artifactDirectory();
		if (directory == null)
			return;
		sys.FileSystem.createDirectory(directory);
		final name = '${cacheKey.substr(0, 16)}-${VulkanShaderAbi.stageName(stage.stage).toLowerCase()}';
		sys.io.File.saveContent(haxe.io.Path.join([directory, '$name.glsl']), stage.source);
		#end
	}

	static function saveSuccessArtifacts(stage:VulkanCompiledStageSource, cacheKey:String) {
		#if (sys && debug)
		final directory = artifactDirectory();
		if (directory == null)
			return;
		sys.FileSystem.createDirectory(directory);
		final name = '${cacheKey.substr(0, 16)}-${VulkanShaderAbi.stageName(stage.stage).toLowerCase()}';
		sys.io.File.saveContent(haxe.io.Path.join([directory, '$name.glsl']), stage.source);
		sys.io.File.saveBytes(haxe.io.Path.join([directory, '$name.spv']), stage.spirv);
		sys.io.File.saveContent(haxe.io.Path.join([directory, '$name.reflection.json']), haxe.Json.stringify(stage.reflection, null, "  "));
		#end
	}
}
#end
