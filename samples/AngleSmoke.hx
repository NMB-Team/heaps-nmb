class AngleSmoke extends hxd.App {
	var batch:Null<h3d.scene.MeshBatch>;
	var frames = 0;

	override function init():Void {
		print(engine.rendererName());
		print(engine.driverName(true));

		final triangle = new h3d.prim.Polygon([
			new h3d.col.Point(-1, 0, 0),
			new h3d.col.Point(1, 0, 0),
			new h3d.col.Point(0, 1.5, 0)
		]);
		triangle.addNormals();
		final triangleMesh = new h3d.scene.Mesh(triangle, s3d);
		triangleMesh.material.color.setColor(0xFF8040);
		triangleMesh.material.shadows = false;
		triangleMesh.x = -1.5;

		final cube = new h3d.prim.Cube(1, 1, 1, true);
		cube.addNormals();
		final cubeMesh = new h3d.scene.Mesh(cube, s3d);
		cubeMesh.x = 1.5;
		cubeMesh.material.color.setColor(0x4080FF);
		cubeMesh.material.shadows = false;

		if (!hxd.GraphicsDriverConfig.usesVulkan()) {
			batch = new h3d.scene.MeshBatch(cube, s3d);
			batch.material.color.setColor(0x40FF80);
			batch.material.shadows = false;
		}

		final tile = h2d.Tile.fromColor(0xFF4080, 96, 96);
		final bitmap = new h2d.Bitmap(tile, s2d);
		bitmap.x = 16;
		bitmap.y = 16;

		final target = new h3d.mat.Texture(64, 64, [Target]);
		engine.driver.setRenderTarget(target);
		engine.driver.clear(new h3d.Vector4(0.1, 0.4, 0.8, 1));
		engine.driver.setRenderTarget(null);
		final targetBitmap = new h2d.Bitmap(h2d.Tile.fromTexture(target), s2d);
		targetBitmap.x = 128;
		targetBitmap.y = 16;

		final text = new h2d.Text(hxd.res.DefaultFont.get(), s2d);
		text.text = "ANGLE Heaps smoke test";
		text.x = 16;
		text.y = 128;

		new h3d.scene.fwd.DirLight(new h3d.Vector(-1, -2, -4), s3d);
		s3d.camera.pos.set(0, -6, 3);
		s3d.camera.target.set(0, 0, 0.5);
	}

	override function update(dt:Float):Void {
		if (batch != null) {
			batch.begin(4);
			for (index in 0...4) {
				batch.x = -1.5 + index;
				batch.y = 2;
				batch.z = 0;
				batch.setScale(0.35);
				batch.emitInstance();
			}
		}
		if (++frames >= 60)
			hxd.System.exit();
	}

	private static function print(value:String):Void {
		#if sys
		Sys.println(value);
		#else
		trace(value);
		#end
	}

	static function main():Void {
		#if sys
		try {
			new AngleSmoke();
		} catch (error:Dynamic) {
			Sys.println(Std.string(error));
			Sys.exit(1);
		}
		#else
		new AngleSmoke();
		#end
	}
}
