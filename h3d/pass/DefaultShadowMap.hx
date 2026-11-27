package h3d.pass;

class DefaultShadowMap extends DirShadowMap {

	var shadowMapId : Int;
	var shadowViewProjId : Int;
	var shadowColorId : Int;
	var shadowPowerId : Int;
	var shadowBiasId : Int;
	var shadowMapValue : {texture:h3d.mat.Texture, channel:hxsl.Channel};

	public var color : h3d.Vector;

	public function new(size=1024,?format:hxd.PixelFormat) {
		if( format != null )
			this.format = format;
		super(null);
		this.size = size;
		color = new h3d.Vector();
		mode = Dynamic;
		shadowMapId = hxsl.Globals.allocID("shadow.map");
		shadowViewProjId = hxsl.Globals.allocID("shadow.viewProj");
		shadowColorId = hxsl.Globals.allocID("shadow.color");
		shadowPowerId = hxsl.Globals.allocID("shadow.power");
		shadowBiasId = hxsl.Globals.allocID("shadow.bias");
	}

	override function draw( passes, ?sort ) {
		super.draw(passes, sort);
		var channel = format == h3d.mat.Texture.nativeFormat ? hxsl.Channel.PackedFloat : hxsl.Channel.R;
		if( shadowMapValue == null || shadowMapValue.texture != dshader.shadowMap || shadowMapValue.channel != channel )
			shadowMapValue = {texture:dshader.shadowMap, channel:channel};
		ctx.globals.fastSet(shadowMapId, shadowMapValue);
		ctx.globals.fastSet(shadowViewProjId, getShadowViewProj());
		ctx.globals.fastSet(shadowColorId, color);
		#if hl
		ctx.globals.fastSetFloat(shadowPowerId, power);
		ctx.globals.fastSetFloat(shadowBiasId, bias);
		#else
		ctx.globals.fastSet(shadowPowerId, power);
		ctx.globals.fastSet(shadowBiasId, bias);
		#end
	}

}
