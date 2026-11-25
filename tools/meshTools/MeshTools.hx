class MeshTools {

	static function main() {
		var args = Sys.args();
		if( args.length < 2 )
			exit();

		switch(args[0]) {
			case "mikktspace":
				mikktspace(args);
			case "optimize":
				optimize(args, -1, 0.);
			case "simplify":
				if( args.length < 4 )
					exit();
				var targetIndexCount = Std.parseInt(args[3]);
				if( targetIndexCount == null || targetIndexCount < 0 )
					exit();
				optimize(args, targetIndexCount, args.length > 4 ? Std.parseFloat(args[4]) : 0.05);
			case "vhacd":
				vhacd(args);
			default:
				exit();
		}
	}

	static function mikktspace(args) {
		if ( args.length < 3 )
			exit();

		var threshold = args.length > 3 ? Std.parseFloat(args[3]) : 180;

		var input = new haxe.io.BytesInput(sys.io.File.getBytes(args[1]));
		var m = new hxd.tools.Mikktspace();
		var vertCount = input.readInt32();
		m.stride = input.readInt32();
		m.xPos = input.readInt32();
		m.normalPos = input.readInt32();
		m.uvPos = input.readInt32();
		m.buffer = input.read(vertCount * m.stride * 4);

		m.indices = input.readInt32();
		m.indexes = input.read(m.indices * 4);

		var tangents = haxe.io.Bytes.alloc(4 * 4 * vertCount);
		tangents.fill(0,tangents.length,0);
		for( i in 0...vertCount )
			tangents.setFloat(i * 16, 1);
		m.tangents = tangents;
		m.tangentStride = 4;
		m.tangentPos = 0;

		m.compute(threshold);

		sys.io.File.saveBytes(args[2], tangents);
	}

	static function optimize(args, targetIndexCount:Int, targetError:Float) {
		if ( args.length < 3 )
			exit();

		var input = new haxe.io.BytesInput(sys.io.File.getBytes(args[1]));
		var vertexCount = input.readInt32();
		var vertexSize = input.readInt32();
		var vertices = input.read(vertexCount * vertexSize);
		var indexCount = input.readInt32();
		var indices = input.read(indexCount << 2);

		var mesh = hxd.tools.MeshOptimizer.optimize(hl.Bytes.fromBytes(vertices), vertexCount, vertexSize, hl.Bytes.fromBytes(indices), indexCount, targetIndexCount, targetError);

		var outputData = new haxe.io.BytesBuffer();
		outputData.addInt32(mesh.vertexCount);
		outputData.addBytes(vertices, 0, mesh.vertexCount * vertexSize);
		outputData.addInt32(mesh.indexCount);
		outputData.addBytes(indices, 0, mesh.indexCount << 2);
		sys.io.File.saveBytes(args[2], outputData.getBytes());
	}

	static function vhacd(args) {
		if ( args.length < 3 )
			exit();

		var input = new haxe.io.BytesInput(sys.io.File.getBytes(args[1]));
		var dataSize = 3 << 2;
		var pointCount = input.readInt32();
		var points = hl.Bytes.fromBytes(input.read(pointCount * dataSize));
		var triangleCount = input.readInt32();
		var triangles = hl.Bytes.fromBytes(input.read(triangleCount * dataSize));
		var vhacdInstance = new hxd.tools.VHACD();
		var params = new hxd.tools.VHACD.Parameters();
		if ( args.length >= 4 ) {
			params.maxConvexHulls = Std.parseInt(args[3]);
		}
		if ( args.length >= 5 ) {
			params.maxResolution = Std.parseInt(args[4]);
		}
		if ( !vhacdInstance.compute(points, pointCount, triangles, triangleCount, params) ) {
			Sys.println("Failed to compute convex hulls");
			Sys.exit(1);
		}
		var convexHullCount = vhacdInstance.getConvexHullCount();
		var convexHull = new hxd.tools.VHACD.ConvexHull();
		var outputData = new haxe.io.BytesBuffer();
		outputData.addInt32(convexHullCount);
		for ( i in 0...convexHullCount) {
			vhacdInstance.getConvexHull(i, convexHull);
			var pointCount = convexHull.pointCount;
			outputData.addInt32(pointCount);
			outputData.add(haxe.io.Bytes.ofData(new haxe.io.BytesData(convexHull.points, pointCount * dataSize << 1)));
			var triangleCount = convexHull.triangleCount;
			outputData.addInt32(triangleCount);
			outputData.add(haxe.io.Bytes.ofData(new haxe.io.BytesData(convexHull.triangles, triangleCount * dataSize)));
		}
		vhacdInstance.clean();
		vhacdInstance.release();

		sys.io.File.saveBytes(args[2], outputData.getBytes());
	}

	static function exit() {
		Sys.println("MeshTools :\n
			meshtools mikktspace [input] [ouput] (angle)\n
			meshtools optimize [input] [output]\n
			meshtools simplify [input] [output] [targetCount] (deformationFactor)\n
			meshtools vhacd [input] [output]
		");
		Sys.exit(1);
	}

}
