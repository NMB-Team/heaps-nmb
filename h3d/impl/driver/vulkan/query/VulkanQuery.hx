package h3d.impl.driver.vulkan.query;

#if (limen && gfx_vulkan)
import haxe.Int64;
import hxd.Math;
import h3d.impl.driver.QueryKind;
import limen.graphics.vulkan.Runtime;
import limen.graphics.vulkan.command.Commands.VkCommandBuffer;
import limen.graphics.vulkan.internal.VulkanBindings.VkContext;
import limen.graphics.vulkan.query.Queries.VkQueryPool;
import limen.graphics.vulkan.query.Queries.VkQueryPoolCreateInfo;
import limen.graphics.vulkan.query.Queries.VkQueryResultFlag;
import limen.graphics.vulkan.query.Queries.VkQueryType;

enum abstract VulkanQueryState(Int) {
	final Idle;
	final Recording;
	final PendingSubmission;
	final InFlight;
	final Available;
}

class VulkanQuery {
	public final kind:QueryKind;
	public var state = VulkanQueryState.Idle;
	public var generation = 0;
	public var result = 0.;
	public var resultValid = false;
	public var deleted = false;
	public var current:VulkanQueryGeneration;

	public function new(kind:QueryKind) {
		this.kind = kind;
	}
}

class VulkanQueryGeneration {
	public final owner:VulkanQuery;
	public final generation:Int;
	public final frameIndex:Int;
	public final page:VulkanQueryPage;
	public final firstSlot:Int;
	public final slotCount:Int;
	public var submissionSerial = 0;

	public function new(owner:VulkanQuery, frameIndex:Int, page:VulkanQueryPage, firstSlot:Int, slotCount:Int) {
		this.owner = owner;
		this.generation = owner.generation;
		this.frameIndex = frameIndex;
		this.page = page;
		this.firstSlot = firstSlot;
		this.slotCount = slotCount;
	}
}

class VulkanQueryPage {
	public final pool:VkQueryPool;
	public final type:VkQueryType;
	public final capacity:Int;
	public var used = 0;

	public function new(pool:VkQueryPool, type:VkQueryType, capacity:Int) {
		this.pool = pool;
		this.type = type;
		this.capacity = capacity;
	}
}

private class VulkanQueryFrame {
	public final timestampPages:Array<VulkanQueryPage> = [];
	public final occlusionPages:Array<VulkanQueryPage> = [];
	public final generations:Array<VulkanQueryGeneration> = [];
	public var submissionSerial = 0;

	public function new() {}
}

class VulkanQueryManager {
	public static inline final PAGE_CAPACITY = 256;
	static inline final VK_SUCCESS = 0;
	static inline final VK_NOT_READY = 1;
	static inline final UINT64_HIGH_BIT = 9223372036854775808.;

	final context:VkContext;
	final timestampValidBits:Int;
	final timestampPeriod:Float;
	final preciseOcclusion:Bool;
	final frames:Array<VulkanQueryFrame>;

	public function new(context:VkContext, frameCount:Int, timestampValidBits:Int, timestampPeriod:Float, preciseOcclusion:Bool) {
		this.context = context;
		this.timestampValidBits = timestampValidBits;
		this.timestampPeriod = timestampPeriod;
		this.preciseOcclusion = preciseOcclusion;
		frames = [for (_ in 0...frameCount) new VulkanQueryFrame()];
		for (frame in frames) {
			if (timestampValidBits > 0)
				frame.timestampPages.push(createPage(VkQueryType.TIMESTAMP));
			if (preciseOcclusion)
				frame.occlusionPages.push(createPage(VkQueryType.OCCLUSION));
		}
	}

	public function alloc(kind:QueryKind):VulkanQuery {
		switch (kind) {
		case TimeStamp, TimeElapsed:
			if (timestampValidBits <= 0)
				throw "Vulkan GPU timestamp queries are not supported by the graphics queue";
		case Samples:
			if (!preciseOcclusion)
				throw "Vulkan precise occlusion queries are not supported by this device";
		}
		return new VulkanQuery(kind);
	}

	public function beginFrame(frameIndex:Int, command:VkCommandBuffer) {
		final frame = frames[frameIndex];
		if (frame.submissionSerial != 0)
			throw "Vulkan query frame pages were reused before submission retirement";
		for (page in frame.timestampPages) {
			page.used = 0;
			command.resetQueryPool(page.pool, 0, page.capacity);
		}
		for (page in frame.occlusionPages) {
			page.used = 0;
			command.resetQueryPool(page.pool, 0, page.capacity);
		}
	}

	public function start(query:VulkanQuery, frameIndex:Int, command:VkCommandBuffer, suspendForGrowth:Void->Void):VulkanQueryGeneration {
		validate(query);
		if (query.state == Recording)
			throw "Vulkan query begin called twice without endQuery";
		query.generation++;
		query.resultValid = false;
		query.state = Recording;
		final slotCount = query.kind == TimeElapsed ? 2 : 1;
		final pages = query.kind == Samples ? frames[frameIndex].occlusionPages : frames[frameIndex].timestampPages;
		var page:VulkanQueryPage = null;
		for (candidate in pages)
			if (candidate.used + slotCount <= candidate.capacity) {
				page = candidate;
				break;
			}
		if (page == null || page.used + slotCount > page.capacity) {
			suspendForGrowth();
			page = createPage(query.kind == Samples ? VkQueryType.OCCLUSION : VkQueryType.TIMESTAMP);
			pages.push(page);
			command.resetQueryPool(page.pool, 0, page.capacity);
		}
		final generation = new VulkanQueryGeneration(query, frameIndex, page, page.used, slotCount);
		page.used += slotCount;
		query.current = generation;
		frames[frameIndex].generations.push(generation);
		return generation;
	}

	public function end(query:VulkanQuery) {
		validate(query);
		if (query.state != Recording)
			throw "Vulkan query end called without a matching beginQuery";
		query.state = PendingSubmission;
	}

	public function endTimestamp(query:VulkanQuery) {
		validate(query);
		if (query.kind != TimeStamp)
			throw "Vulkan timestamp completion requires a TimeStamp query";
		query.state = PendingSubmission;
	}

	public function submitted(frameIndex:Int, serial:Int) {
		frames[frameIndex].submissionSerial = serial;
		for (generation in frames[frameIndex].generations) {
			if (generation.submissionSerial != 0)
				continue;
			generation.submissionSerial = serial;
			final query = generation.owner;
			if (isCurrent(generation) && !query.deleted)
				query.state = InFlight;
		}
	}

	public function completeFrame(frameIndex:Int) {
		final frame = frames[frameIndex];
		if (frame.submissionSerial == 0)
			return;
		for (page in frame.timestampPages)
			resolvePage(frame, page);
		for (page in frame.occlusionPages)
			resolvePage(frame, page);
		frame.generations.resize(0);
		frame.submissionSerial = 0;
	}

	public inline function hasSubmitted(frameIndex:Int):Bool {
		return frames[frameIndex].submissionSerial != 0;
	}

	public function delete(query:VulkanQuery) {
		validate(query);
		if (query.state == Recording)
			throw "Cannot delete a Vulkan query while it is recording";
		query.deleted = true;
		query.resultValid = false;
		query.current = null;
	}

	public function available(query:VulkanQuery):Bool {
		validate(query);
		if (query.state == Idle || query.state == Recording)
			return false;
		return query.resultValid;
	}

	public function requireResult(query:VulkanQuery):Float {
		validate(query);
		if (query.state == Idle || query.state == Recording)
			throw "Vulkan query result requested before endQuery";
		if (!query.resultValid)
			throw "Vulkan query result is not available after submission completion";
		return query.result;
	}

	public function dispose() {
		for (frame in frames) {
			for (page in frame.timestampPages)
				context.destroyQueryPool(page.pool);
			for (page in frame.occlusionPages)
				context.destroyQueryPool(page.pool);
			frame.timestampPages.resize(0);
			frame.occlusionPages.resize(0);
			frame.generations.resize(0);
		}
	}

	public function pageCounts():{timestamp:Int, occlusion:Int} {
		var timestamp = 0;
		var occlusion = 0;
		for (frame in frames) {
			timestamp += frame.timestampPages.length;
			occlusion += frame.occlusionPages.length;
		}
		return {timestamp: timestamp, occlusion: occlusion};
	}

	function createPage(type:VkQueryType):VulkanQueryPage {
		final info = new VkQueryPoolCreateInfo();
		info.queryType = type;
		info.queryCount = PAGE_CAPACITY;
		final pool = context.createQueryPool(info);
		if (pool == null)
			throw Runtime.error('Failed to create Vulkan $type query pool');
		return new VulkanQueryPage(pool, type, PAGE_CAPACITY);
	}

	function resolvePage(frame:VulkanQueryFrame, page:VulkanQueryPage) {
		if (page.used == 0)
			return;
		final data = new hl.Bytes(page.used * 8);
		var flags = new haxe.EnumFlags<VkQueryResultFlag>();
		flags.set(RESULT_64);
		final status = context.getQueryPoolResults(page.pool, 0, page.used, page.used * 8, data, (Int64.ofInt(8) : hl.I64), flags);
		if (status == VK_NOT_READY)
			throw "Vulkan query page remained unavailable after its submission fence completed";
		if (status != VK_SUCCESS)
			throw Runtime.error("Failed to retrieve Vulkan query page results");
		final values:hl.BytesAccess<Int64> = data;
		for (generation in frame.generations)
			if (generation.page == page)
				cache(generation, values[generation.firstSlot], generation.slotCount == 2 ? values[generation.firstSlot + 1] : Int64.ofInt(0));
	}

	function cache(generation:VulkanQueryGeneration, first:Int64, second:Int64) {
		final query = generation.owner;
		if (!isCurrent(generation) || query.deleted)
			return;
		query.result = switch (query.kind) {
		case TimeStamp: unsignedToFloat(normalizeTimestamp(first, timestampValidBits)) * timestampPeriod;
		case TimeElapsed: elapsedNanoseconds(first, second, timestampValidBits, timestampPeriod);
		case Samples: unsignedToFloat(first);
		}
		query.resultValid = true;
		query.state = Available;
	}

	public static function elapsedNanoseconds(start:Int64, end:Int64, validBits:Int, period:Float):Float {
		return unsignedToFloat(normalizeTimestamp(end - start, validBits)) * period;
	}

	public static function normalizeTimestamp(value:Int64, validBits:Int):Int64 {
		if (validBits >= 64)
			return value;
		final shift = 64 - validBits;
		return (value << shift) >>> shift;
	}

	static inline function unsignedToFloat(value:Int64):Float {
		if (value.high >= 0)
			return Math.int64ToFloat(value);
		return Math.int64ToFloat(Int64.make(value.high & 0x7FFFFFFF, value.low)) + UINT64_HIGH_BIT;
	}

	inline function isCurrent(generation:VulkanQueryGeneration):Bool {
		return generation.owner.current == generation && generation.owner.generation == generation.generation;
	}

	inline function validate(query:VulkanQuery) {
		if (query == null)
			throw "Vulkan query is null";
		if (query.deleted)
			throw "Vulkan query has been deleted";
	}
}
#end
