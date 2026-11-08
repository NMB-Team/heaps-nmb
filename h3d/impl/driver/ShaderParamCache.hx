package h3d.impl.driver;

import h3d.shader.Buffers.ShaderBufferData;

class ShaderParamCache {
	var content : ShaderBufferData;
	#if js
	var source : ShaderBufferData;
	var sourceWords : js.lib.Uint32Array;
	var contentWords : js.lib.Uint32Array;
	#end

	public function new() {
	}

	public function update(data:ShaderBufferData, count:Int, force = false) : Bool {
		if( content == null || content.length != count ) {
			content = new ShaderBufferData(count);
			#if js
			contentWords = new js.lib.Uint32Array(content.buffer, content.byteOffset, count);
			#end
			force = true;
		}
		// Parameters can contain integer and resource-handle bit patterns.
		#if hl
		var input = hl.Bytes.getArray(data.toData());
		var output = hl.Bytes.getArray(content.toData());
		var size = count << 2;
		if( !force && output.compare(0, input, 0, size) == 0 ) return false;
		output.blit(0, input, 0, size);
		#elseif js
		if( source != data ) {
			source = data;
			sourceWords = new js.lib.Uint32Array(data.buffer, data.byteOffset, data.length);
		}
		if( !force ) {
			var same = true;
			for( i in 0...count ) if( sourceWords[i] != contentWords[i] ) { same = false; break; }
			if( same ) return false;
		}
		for( i in 0...count ) contentWords[i] = sourceWords[i];
		#else
		if( !force ) {
			var same = true;
			for( i in 0...count )
				if( haxe.io.FPHelper.floatToI32(data[i]) != haxe.io.FPHelper.floatToI32(content[i]) ) { same = false; break; }
			if( same ) return false;
		}
		for( i in 0...count ) content[i] = data[i];
		#end
		return true;
	}
}
