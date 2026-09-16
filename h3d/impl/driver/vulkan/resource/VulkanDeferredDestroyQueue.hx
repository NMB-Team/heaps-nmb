package h3d.impl.driver.vulkan.resource;

#if (limen && gfx_vulkan)
private class VulkanRetiredResource {
	public var serial:Int;
	public var destroy:Void->Void;

	public function new(serial:Int, destroy:Void->Void) {
		this.serial = serial;
		this.destroy = destroy;
	}
}

class VulkanDeferredDestroyQueue {
	final retired:Array<VulkanRetiredResource> = [];

	public var pendingCount(get, never):Int;

	inline function get_pendingCount():Int {
		return retired.length;
	}

	public function new() {}

	public function retire(serial:Int, destroy:Void->Void) {
		retired.push(new VulkanRetiredResource(serial, destroy));
	}

	public function collect(completedSerial:Int) {
		var index = 0;
		while (index < retired.length) {
			final resource = retired[index];
			if (resource.serial <= completedSerial) {
				retired.splice(index, 1);
				resource.destroy();
			} else
				index++;
		}
	}

	public function drain() {
		for (resource in retired)
			resource.destroy();
		retired.resize(0);
	}
}
#end
