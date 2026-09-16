package hxsl;

class VulkanGlslBinding {
	public final set:Int;
	public final binding:Int;

	public function new(set:Int, binding:Int) {
		this.set = set;
		this.binding = binding;
	}
}

class VulkanGlslConstantMember {
	public final variableId:Int;
	public final offset:Int;

	public function new(variableId:Int, offset:Int) {
		this.variableId = variableId;
		this.offset = offset;
	}
}

class VulkanGlslConstantBlock {
	public final name:String;
	public final set:Int;
	public final binding:Int;
	public final members:Array<VulkanGlslConstantMember>;

	public function new(name:String, set:Int, binding:Int, members:Array<VulkanGlslConstantMember>) {
		this.name = name;
		this.set = set;
		this.binding = binding;
		this.members = members.copy();
	}
}

class VulkanGlslBindlessLayout {
	public final set:Int;
	public final imageBinding:Int;
	public final samplerBinding:Int;
	public final bufferBinding:Int;
	public final imageCapacity:Int;
	public final samplerCapacity:Int;
	public final bufferCapacity:Int;

	public function new(set:Int, imageBinding:Int, samplerBinding:Int, bufferBinding:Int,
		imageCapacity:Int, samplerCapacity:Int, bufferCapacity:Int) {
		this.set = set;
		this.imageBinding = imageBinding;
		this.samplerBinding = samplerBinding;
		this.bufferBinding = bufferBinding;
		this.imageCapacity = imageCapacity;
		this.samplerCapacity = samplerCapacity;
		this.bufferCapacity = bufferCapacity;
	}
}

class VulkanGlslLayout {
	public final bindings:Map<Int, VulkanGlslBinding> = new Map();
	public final locations:Map<Int, Int> = new Map();
	public final constantBlocks:Array<VulkanGlslConstantBlock> = [];
	public var bindless:VulkanGlslBindlessLayout;

	public function new() {}

	public function requireBinding(variableId:Int):VulkanGlslBinding {
		final result = bindings.get(variableId);
		if (result == null)
			throw 'Vulkan GLSL resource variable $variableId has no resolved ABI binding';
		return result;
	}

	public function requireLocation(variableId:Int):Int {
		final result = locations.get(variableId);
		if (result == null)
			throw 'Vulkan GLSL interface variable $variableId has no resolved ABI location';
		return result;
	}
}
