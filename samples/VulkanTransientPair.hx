class VulkanTransientPair extends hxd.App {
	var remaining = 3;

	override function render(engine:h3d.Engine) {
		var driver:h3d.impl.driver.vulkan.VulkanDriver = cast @:privateAccess engine.driver;
		driver.validateTransientTargetPair(true);
		remaining--;
	}

	override function update(dt:Float) {
		if (remaining == 0) {
			engine.dispose();
			Sys.println("Vulkan transient target pair: PASS");
			Sys.exit(0);
		}
	}

	static function main() {
		limen.graphics.renderer.vulkan.internal.VulkanBindings.ENABLE_VALIDATION = true;
		new VulkanTransientPair();
	}
}
