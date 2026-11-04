//TARGETS=hldx12
//PARAM=-D gfx_d3d12ma

class Dx12TransientAliasing extends hxd.App {
	override function init() {
		var driver : h3d.impl.driver.dx12.DX12Driver = cast @:privateAccess engine.driver;
		for( i in 0...3 ) driver.validateTransientTargetPair(true);
		engine.dispose();
		Sys.println("Transient target pair: PASS");
		Sys.exit(0);
	}

	static function main() {
		h3d.impl.driver.dx12.DX12Driver.DEBUG = true;
		new Dx12TransientAliasing();
	}
}
