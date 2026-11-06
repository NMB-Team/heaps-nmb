package hxd.fmt;

import haxe.io.Bytes;
import haxe.io.BytesData;
import hxd.Pixels;

#if hl
final class Qoi {
	public static function decode(bytes:Bytes):Pixels {
		var width = 0;
		var height = 0;
		final data = decodeNative(bytes.getData().bytes, bytes.length, width, height);
		if (data == null)
			return null;
		return new Pixels(width, height, Bytes.ofData(new BytesData(data, width * height * 4)), RGBA);
	}

	public static function encode(pixels:Pixels, colorspace:Int = 0):Bytes {
		var source = pixels;
		if (source.format != RGBA) {
			source = pixels.clone();
			source.convert(RGBA);
		}
		var size = 0;
		final data = encodeNative(source.bytes.getData().bytes, source.bytes.length, source.offset, source.width, source.height, colorspace, size);
		if (source != pixels)
			source.dispose();
		if (data == null)
			throw "Could not encode QOI image";
		return Bytes.ofData(new BytesData(data, size));
	}

	@:hlNative("fmt", "qoi_decode")
	static function decodeNative(data:hl.Bytes, length:Int, width:hl.Ref<Int>, height:hl.Ref<Int>):hl.Bytes {
		return null;
	}

	@:hlNative("fmt", "qoi_encode")
	static function encodeNative(data:hl.Bytes, length:Int, offset:Int, width:Int, height:Int, colorspace:Int, size:hl.Ref<Int>):hl.Bytes {
		return null;
	}
}
#end
