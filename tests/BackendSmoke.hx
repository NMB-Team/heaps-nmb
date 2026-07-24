package tests;

import h3d.impl.driver.Driver;
import h3d.impl.driver.DriverFactory;
import h3d.impl.driver.nulls.NullDriver;

class BackendSmoke {

	static function main() {
		var factory : Class<DriverFactory> = DriverFactory;
		var driver : Class<Driver> = Driver;
		var nullDriver : Class<NullDriver> = NullDriver;
		var gpuBuffer : h3d.impl.driver.GPUBuffer = null;
		var texture : h3d.impl.driver.Texture = null;
		var query : h3d.impl.driver.Query = null;
		var feature = h3d.impl.driver.Feature.HardwareAccelerated;
		var queryKind = h3d.impl.driver.QueryKind.TimeStamp;
		var renderFlag = h3d.impl.driver.RenderFlag.CameraHandness;
		var dlssTag = h3d.impl.driver.dlss.DLSSTag.Depth;
		var dlssParams : Class<h3d.impl.driver.dlss.DLSSParams> = h3d.impl.driver.dlss.DLSSParams;
		var dlssSettings : Class<h3d.impl.driver.dlss.DLSSSettings> = h3d.impl.driver.dlss.DLSSSettings;
		var dlssQuality = h3d.impl.driver.dlss.DLSSQuality.Default;
		var dlssMode = h3d.impl.driver.dlss.DLSSMode.Off;
		var memoryType : Class<h3d.impl.allocator.MemoryType> = h3d.impl.allocator.MemoryType;
		var memoryPage : Class<h3d.impl.allocator.MemoryPage> = h3d.impl.allocator.MemoryPage;
		var memoryBlock : Class<h3d.impl.allocator.MemoryBlock> = h3d.impl.allocator.MemoryBlock;
		var allocatorPolicy : Class<h3d.impl.allocator.AllocatorPolicy> = h3d.impl.allocator.AllocatorPolicy;
		var scalePolicy : Class<h3d.impl.allocator.ScalePolicy> = h3d.impl.allocator.ScalePolicy;
		var allocator : Class<h3d.impl.allocator.Allocator> = h3d.impl.allocator.Allocator;
		var blockAllocator : Class<h3d.impl.allocator.BlockAllocator> = h3d.impl.allocator.BlockAllocator;
		var freeListAllocator : Class<h3d.impl.allocator.FreeListAllocator> = h3d.impl.allocator.FreeListAllocator;
		var freeList : Class<h3d.impl.allocator.FreeList> = h3d.impl.allocator.FreeList;
		var window : Class<hxd.Window> = hxd.Window;
		var pad : Class<hxd.Pad> = hxd.Pad;
		var event = new hxd.Event(EKeyDown);
		event.timestamp = 0.;
		event.isRepeat = false;
		var padEvent : hxd.Pad.PadEvent = { kind: EPadConnect, pad: null, timestamp: 0. };

		#if gfx_dx11
		var dx11Driver : Class<h3d.impl.driver.dx11.DX11Driver> = h3d.impl.driver.dx11.DX11Driver;
		var pipelineKind = h3d.impl.driver.dx11.PipelineKind.Vertex;
		var pipelineState : Class<h3d.impl.driver.dx11.PipelineState> = h3d.impl.driver.dx11.PipelineState;
		var shaderContext : Class<h3d.impl.driver.dx11.ShaderContext> = h3d.impl.driver.dx11.ShaderContext;
		var dx11Shader : Class<h3d.impl.driver.dx11.CompiledShader> = h3d.impl.driver.dx11.CompiledShader;
		#end

		#if gfx_dx12
		var dx12Driver : Class<h3d.impl.driver.dx12.DX12Driver> = h3d.impl.driver.dx12.DX12Driver;
		var tempObjects : Class<h3d.impl.driver.dx12.TempObjects> = h3d.impl.driver.dx12.TempObjects;
		var heapMemory : Class<h3d.impl.driver.dx12.memory.HeapMemoryType> = h3d.impl.driver.dx12.memory.HeapMemoryType;
		var bufferMemory : Class<h3d.impl.driver.dx12.memory.BufferMemoryType> = h3d.impl.driver.dx12.memory.BufferMemoryType;
		var descriptorHeap : Class<h3d.impl.driver.dx12.descriptor.DescriptorHeapBase> = h3d.impl.driver.dx12.descriptor.DescriptorHeapBase;
		var scratchHeap : Class<h3d.impl.driver.dx12.descriptor.ScratchHeap> = h3d.impl.driver.dx12.descriptor.ScratchHeap;
		var scratchHeapArray : Class<h3d.impl.driver.dx12.descriptor.ScratchHeapArray> = h3d.impl.driver.dx12.descriptor.ScratchHeapArray;
		var blockHeap : Class<h3d.impl.driver.dx12.descriptor.BlockHeap> = h3d.impl.driver.dx12.descriptor.BlockHeap;
		var frame : Class<h3d.impl.driver.dx12.frame.DX12Frame> = h3d.impl.driver.dx12.frame.DX12Frame;
		var resource : Class<h3d.impl.driver.dx12.resource.ResourceData> = h3d.impl.driver.dx12.resource.ResourceData;
		var buffer : Class<h3d.impl.driver.dx12.resource.BufferData> = h3d.impl.driver.dx12.resource.BufferData;
		var texture : Class<h3d.impl.driver.dx12.resource.TextureData> = h3d.impl.driver.dx12.resource.TextureData;
		var registers : Class<h3d.impl.driver.dx12.shader.ShaderRegisters> = h3d.impl.driver.dx12.shader.ShaderRegisters;
		var shader : Class<h3d.impl.driver.dx12.shader.CompiledShader> = h3d.impl.driver.dx12.shader.CompiledShader;
		var query : Class<h3d.impl.driver.dx12.query.QueryData> = h3d.impl.driver.dx12.query.QueryData;
		var readback : Class<h3d.impl.driver.dx12.readback.AsyncReadbackRequest> = h3d.impl.driver.dx12.readback.AsyncReadbackRequest;
		#end

		#if gfx_vulkan
		var vulkanDriver : Class<h3d.impl.driver.vulkan.VulkanDriver> = h3d.impl.driver.vulkan.VulkanDriver;
		var vulkanFrame : Class<h3d.impl.driver.vulkan.frame.VulkanFrame> = h3d.impl.driver.vulkan.frame.VulkanFrame;
		var swapchainImage : Class<h3d.impl.driver.vulkan.swapchain.VulkanSwapchainImage> = h3d.impl.driver.vulkan.swapchain.VulkanSwapchainImage;
		var shaderStage : Class<h3d.impl.driver.vulkan.shader.VulkanShaderStageData> = h3d.impl.driver.vulkan.shader.VulkanShaderStageData;
		var vulkanShader : Class<h3d.impl.driver.vulkan.shader.VulkanCompiledShader> = h3d.impl.driver.vulkan.shader.VulkanCompiledShader;
		#end

		#if gfx_opengl
		var openGLDriver : Class<h3d.impl.driver.opengl.OpenGLDriver> = h3d.impl.driver.opengl.OpenGLDriver;
		var openGLShader : Class<h3d.impl.driver.opengl.CompiledShader> = h3d.impl.driver.opengl.CompiledShader;
		var openGLAttribute : Class<h3d.impl.driver.opengl.CompiledAttribute> = h3d.impl.driver.opengl.CompiledAttribute;
		var openGLProgram : Class<h3d.impl.driver.opengl.CompiledProgram> = h3d.impl.driver.opengl.CompiledProgram;
		#end
	}
}
