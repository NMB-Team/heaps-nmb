package h3d.impl.driver.vulkan.resource;

#if (limen && gfx_vulkan)
import h3d.impl.driver.vulkan.resource.VulkanBuffer.VulkanBufferState;
import h3d.impl.driver.vulkan.resource.VulkanImage.VulkanImageState;
import limen.graphics.vulkan.command.Commands.VkCommandBuffer;
import limen.graphics.vulkan.command.Commands.VkPipelineStage2;
import limen.graphics.vulkan.memory.Memory.VkAccess2;
import limen.graphics.vulkan.memory.Memory.VkImageLayout;
import limen.graphics.vulkan.memory.Memory.VkImageAspectFlag;

class VulkanResourceState {
	@:noCompletion public static var barrierCount(default, null) = 0;

	public static inline function recordBarrier() {
		barrierCount++;
	}

	public static function transitionBuffer(command:VkCommandBuffer, buffer:VulkanBuffer, next:VulkanBufferState, offset:haxe.Int64, size:haxe.Int64) {
		if (buffer.state == next)
			switch (next) {
				case TransferDestination, StorageReadWrite, GraphicsStorageReadWrite:
				default: return;
			}
		recordBarrier();
		command.bufferBarrier2(buffer.buffer, (offset : hl.I64), (size : hl.I64), bufferStage(buffer.state), bufferAccess(buffer.state), bufferStage(next), bufferAccess(next));
		buffer.state = next;
	}

	public static function transitionImage(command:VkCommandBuffer, image:VulkanImage, mipLevel:Int, layer:Int, next:VulkanImageState,
		?aspectMask:haxe.EnumFlags<VkImageAspectFlag>) {
		if (aspectMask == null)
			aspectMask = image.aspect;
		if (image.aspect.has(DEPTH) && image.aspect.has(STENCIL) && (aspectMask.has(DEPTH) || aspectMask.has(STENCIL))) {
			final depthState = image.getState(mipLevel, layer, DEPTH);
			final stencilState = image.getState(mipLevel, layer, STENCIL);
			if (depthState != stencilState)
				throw 'Combined depth/stencil image ${image.debugName} has incompatible tracked aspect states';
			transitionImageAspects(command, image, mipLevel, layer, image.aspect.toInt(), DEPTH, true, depthState, next);
			return;
		}
		if (aspectMask.has(COLOR))
			transitionImageAspect(command, image, mipLevel, layer, COLOR, 1, next);
		if (aspectMask.has(DEPTH))
			transitionImageAspect(command, image, mipLevel, layer, DEPTH, 2, next);
		if (aspectMask.has(STENCIL))
			transitionImageAspect(command, image, mipLevel, layer, STENCIL, 4, next);
	}

	static function transitionImageAspect(command:VkCommandBuffer, image:VulkanImage, mipLevel:Int, layer:Int, aspect:VkImageAspectFlag,
		mask:Int, next:VulkanImageState) {
		final current = image.getState(mipLevel, layer, aspect);
		transitionImageAspects(command, image, mipLevel, layer, mask, aspect, false, current, next);
	}

	static function transitionImageAspects(command:VkCommandBuffer, image:VulkanImage, mipLevel:Int, layer:Int,
		mask:Int, aspect:VkImageAspectFlag, combinedDepthStencil:Bool, current:VulkanImageState, next:VulkanImageState) {
		if (current == next)
			switch (next) {
				case TransferDestination, ColorAttachment, DepthStencilAttachment, ShaderStorageWrite, ShaderStorageReadWrite, General:
				default: return;
			}
		recordBarrier();
		command.imageBarrier2(image.image, cast mask, mipLevel, 1, layer, 1, imageLayout(current), imageLayout(next), imageStage(current), imageAccess(current), imageStage(next), imageAccess(next));
		image.setState(mipLevel, layer, aspect, next);
		if (combinedDepthStencil)
			image.setState(mipLevel, layer, STENCIL, next);
	}

	static function bufferStage(state:VulkanBufferState):hl.I64 {
		return switch (state) {
			case Undefined: VkPipelineStage2.NONE;
			case HostWrite, HostRead: VkPipelineStage2.HOST;
			case TransferSource, TransferDestination: VkPipelineStage2.ALL_TRANSFER;
			case VertexInput, IndexInput: VkPipelineStage2.VERTEX_INPUT;
			case IndirectArgument: VkPipelineStage2.DRAW_INDIRECT;
			case UniformRead, GraphicsStorageRead, GraphicsStorageReadWrite: VkPipelineStage2.ALL_GRAPHICS;
			case ComputeUniformRead, StorageRead, StorageReadWrite: VkPipelineStage2.COMPUTE_SHADER;
		};
	}

	static function bufferAccess(state:VulkanBufferState):hl.I64 {
		return switch (state) {
			case Undefined: VkAccess2.NONE;
			case HostWrite: VkAccess2.HOST_WRITE;
			case HostRead: VkAccess2.HOST_READ;
			case TransferSource: VkAccess2.TRANSFER_READ;
			case TransferDestination: VkAccess2.TRANSFER_WRITE;
			case VertexInput: VkAccess2.VERTEX_ATTRIBUTE_READ;
			case IndexInput: VkAccess2.INDEX_READ;
			case IndirectArgument: VkAccess2.INDIRECT_COMMAND_READ;
			case UniformRead, ComputeUniformRead: VkAccess2.UNIFORM_READ;
			case StorageRead, GraphicsStorageRead: VkAccess2.SHADER_READ;
			case StorageReadWrite, GraphicsStorageReadWrite: shaderReadWrite();
		};
	}

	static function imageStage(state:VulkanImageState):hl.I64 {
		return switch (state) {
			case Undefined, Present: VkPipelineStage2.NONE;
			case TransferSource, TransferDestination: VkPipelineStage2.ALL_TRANSFER;
			case ShaderRead: VkPipelineStage2.ALL_GRAPHICS;
			case ComputeShaderRead, ShaderStorageRead, ShaderStorageWrite, ShaderStorageReadWrite: VkPipelineStage2.COMPUTE_SHADER;
			case ColorAttachment: VkPipelineStage2.COLOR_ATTACHMENT_OUTPUT;
			case DepthStencilAttachment, DepthStencilReadOnly: depthStages();
			case General: shaderStages();
		};
	}

	static function imageAccess(state:VulkanImageState):hl.I64 {
		return switch (state) {
			case Undefined, Present: VkAccess2.NONE;
			case TransferSource: VkAccess2.TRANSFER_READ;
			case TransferDestination: VkAccess2.TRANSFER_WRITE;
			case ShaderRead, ComputeShaderRead, ShaderStorageRead: VkAccess2.SHADER_READ;
			case ShaderStorageWrite: VkAccess2.SHADER_WRITE;
			case ShaderStorageReadWrite, General: shaderReadWrite();
			case ColorAttachment: (cast ((VkAccess2.COLOR_ATTACHMENT_READ : haxe.Int64) | (VkAccess2.COLOR_ATTACHMENT_WRITE : haxe.Int64)) : hl.I64);
			case DepthStencilAttachment: (cast ((VkAccess2.DEPTH_STENCIL_ATTACHMENT_READ : haxe.Int64) | (VkAccess2.DEPTH_STENCIL_ATTACHMENT_WRITE : haxe.Int64)) : hl.I64);
			case DepthStencilReadOnly: VkAccess2.DEPTH_STENCIL_ATTACHMENT_READ;
		};
	}

	static function imageLayout(state:VulkanImageState):VkImageLayout {
		return switch (state) {
			case Undefined: UNDEFINED;
			case TransferSource: TRANSFER_SRC_OPTIMAL;
			case TransferDestination: TRANSFER_DST_OPTIMAL;
			case ShaderRead, ComputeShaderRead: SHADER_READ_ONLY_OPTIMAL;
			case ShaderStorageRead, ShaderStorageWrite, ShaderStorageReadWrite, General: GENERAL;
			case ColorAttachment: COLOR_ATTACHMENT_OPTIMAL;
			case DepthStencilAttachment: DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
			case DepthStencilReadOnly: DEPTH_STENCIL_READ_ONLY_OPTIMAL;
			case Present: PRESENT_SRC_KHR;
		};
	}

	static inline function depthStages():hl.I64 {
		return (cast ((VkPipelineStage2.EARLY_FRAGMENT_TESTS : haxe.Int64) | (VkPipelineStage2.LATE_FRAGMENT_TESTS : haxe.Int64)) : hl.I64);
	}

	static inline function shaderStages():hl.I64 {
		return (cast ((VkPipelineStage2.VERTEX_SHADER : haxe.Int64) | (VkPipelineStage2.FRAGMENT_SHADER : haxe.Int64)
			| (VkPipelineStage2.COMPUTE_SHADER : haxe.Int64)) : hl.I64);
	}

	static inline function shaderReadWrite():hl.I64 {
		return (cast ((VkAccess2.SHADER_READ : haxe.Int64) | (VkAccess2.SHADER_WRITE : haxe.Int64)) : hl.I64);
	}
}
#end
