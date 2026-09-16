package h3d.impl.driver.vulkan.resource;

#if (limen && gfx_vulkan)
import haxe.Int64;
import limen.graphics.vulkan.memory.Memory.VkBuffer;
import limen.graphics.vulkan.memory.Memory.VkBufferUsageFlag;

enum abstract VulkanBufferState(Int) {
	var Undefined;
	var HostWrite;
	var HostRead;
	var TransferSource;
	var TransferDestination;
	var VertexInput;
	var IndexInput;
	var IndirectArgument;
	var UniformRead;
	var ComputeUniformRead;
	var StorageRead;
	var StorageReadWrite;
	var GraphicsStorageRead;
	var GraphicsStorageReadWrite;
}

class VulkanBuffer {
	public var buffer(default, null):VkBuffer;
	public var allocation(default, null):VulkanAllocation;
	public var size(default, null):Int64;
	public var usage(default, null):haxe.EnumFlags<VkBufferUsageFlag>;
	public var stride(default, null):Int;
	public var state:VulkanBufferState;
	public var debugId(default, null):Int;
	public var debugName(default, null):String;
	public var lastSubmission = 0;
	public var disposed(default, null) = false;

	public function new(buffer:VkBuffer, allocation:VulkanAllocation, size:Int64, usage:haxe.EnumFlags<VkBufferUsageFlag>, stride:Int, state:VulkanBufferState, debugId:Int, debugName:String) {
		this.buffer = buffer;
		this.allocation = allocation;
		this.size = size;
		this.usage = usage;
		this.stride = stride;
		this.state = state;
		this.debugId = debugId;
		this.debugName = debugName;
	}

	@:allow(h3d.impl.driver.vulkan.VulkanDriver)
	function markDisposed() {
		disposed = true;
	}
}

class VulkanUploadBuffer extends VulkanBuffer {}
class VulkanReadbackBuffer extends VulkanBuffer {}
#end
