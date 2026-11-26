package h3d.shader;

class HZB extends h3d.shader.ScreenShader {
	static public function build(depth : h3d.mat.Texture, target : h3d.mat.Texture, scratch : h3d.mat.Texture,
		pass : h3d.pass.ScreenFx<HZB>, compareMax : Bool) {
		var engine = h3d.Engine.getCurrent();
		var shader = pass.shader;
		shader.compareMax = compareMax;
		var previousFilter = depth.filter;
		depth.filter = Nearest;
		h3d.pass.Copy.run(depth, target);
		depth.filter = previousFilter;
		target.filter = scratch.filter = Nearest;
		target.mipMap = scratch.mipMap = Nearest;

		var width = target.width;
		var height = target.height;
		for( level in 1...target.mipLevels ) {
			var source = level & 1 == 0 ? scratch : target;
			var destination = level & 1 == 0 ? target : scratch;
			source.startingMip = level - 1;
			shader.source = source;
			shader.sourceWidth = width;
			shader.sourceHeight = height;
			engine.pushTarget(destination, 0, level);
			pass.render();
			engine.popTarget();

			if( destination == scratch )
				h3d.pass.Copy.run(scratch, target, None, null, 0, level, level);

			width = hxd.Math.imax(1, width >> 1);
			height = hxd.Math.imax(1, height >> 1);
		}
		target.startingMip = 0;
		scratch.startingMip = 0;
		shader.source = null;
	}


	static var SRC = {
		@const var compareMax : Bool;
		@param var source : Sampler2D;
		@param var sourceWidth : Int;
		@param var sourceHeight : Int;
		var depth : Float;
		var prevTexelPos : IVec2;

		function compareDepth( offset : IVec2 ) {
			var texel = min(prevTexelPos + offset, ivec2(sourceWidth - 1, sourceHeight - 1));
			var depth2 = source.fetch(texel).x;
			depth = compareMax ? max(depth, depth2) : min(depth, depth2);
		}

		function fragment() {
			prevTexelPos = ivec2(floor(fragCoord.xy) * 2.0);
			depth = source.fetch(prevTexelPos).x;
			compareDepth(ivec2(1, 0));
			compareDepth(ivec2(0, 1));
			compareDepth(ivec2(1, 1));
			var prevWidthOdd = (sourceWidth & 1) != 0;
			var prevHeightOdd = (sourceHeight & 1) != 0;
			if ( prevWidthOdd ) {
				compareDepth(ivec2(2, 0));
				compareDepth(ivec2(2, 1));
			}
			if ( prevHeightOdd ) {
				compareDepth(ivec2(0, 2));
				compareDepth(ivec2(1, 2));
			}
			if ( prevWidthOdd && prevHeightOdd )
				compareDepth(ivec2(2, 2));

			output.color = vec4(depth.xxx, 1.0);
		}
	}
}