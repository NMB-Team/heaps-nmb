package h3d.impl;
import haxe.macro.Context;
import haxe.macro.Expr;

class MacroHelper {

#if macro

	static function replaceGLLoop( e : Expr, members : Map<String,String> ) {
		switch( e.expr ) {
		case EField({ expr: EConst(CIdent("gl" | "GL")) }, name) if( members != null ):
			var owner = members.get(name);
			if( owner == null ) Context.error("Unknown Limen OpenGL member: " + name, e.pos);
			e.expr = Context.parse(owner + "." + name, e.pos).expr;
		case EConst(CIdent("gl")):
			e.expr = EConst(CIdent("GL"));
		default:
			haxe.macro.ExprTools.iter(e, e -> replaceGLLoop(e, members));
		}
	}

	public static function replaceGL() {
		var members : Map<String,String> = null;
		if( Context.defined("limen") ) {
			members = new Map();
			for( module in ["command.Commands", "device.Capabilities", "format.Formats", "pipeline.State", "query.Queries", "render.Framebuffers", "resource.Buffers", "resource.Textures", "shader.Shaders", "vertex.VertexArrays"] ) {
				var path = "limen.graphics.renderer.opengl." + module;
				switch( Context.getType(path) ) {
				case TInst(c, _):
					for( field in c.get().statics.get() ) members.set(field.name, path);
				default:
				}
			}
		}
		var fields = Context.getBuildFields();
		for( f in fields )
			switch( f.kind ) {
			case FFun(f):
				if( f.expr != null ) replaceGLLoop(f.expr, members);
			case FVar(_,e):
				if( e != null ) replaceGLLoop(e, members);
			default:
			}
		return fields;
	}

#end

	public static macro function getResourcesPath() {
		var dir = haxe.macro.Context.definedValue("resourcesPath");
		if( dir == null ) dir = "res";
		return macro $v{try Context.resolvePath(dir) catch( e : Dynamic ) null};
	}

}