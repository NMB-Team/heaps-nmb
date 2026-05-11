/*
	Copyright 2011 notmasteryet

	Licensed under the Apache License, Version 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at

		   http://www.apache.org/licenses/LICENSE-2.0

	Unless required by applicable law or agreed to in writing, software
	distributed under the License is distributed on an "AS IS" BASIS,
	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	See the License for the specific language governing permissions and
	limitations under the License.
 */

// - The JPEG specification can be found in the ITU CCITT Recommendation T.81
//   (www.w3.org/Graphics/JPEG/itu-t81.pdf)
// - The JFIF specification can be found in the JPEG File Interchange Format
//   (www.w3.org/Graphics/JPEG/jfif3.pdf)
// - The Adobe Application-Specific JPEG markers in the Supporting the DCT Filters
//   in PostScript Level 2, Technical Note #5116
//   (partners.adobe.com/public/developer/en/ps/sdk/5116.DCT_Filter.pdf)
package hxd.res;

@:noDebug
class NanoJpeg {
	public static function decode(bytes:haxe.io.Bytes, ?filter, position:Int = 0, size:Int = -1) {
		var imgData = JpegImage.decode(bytes);
		return {width: imgData.width, height: imgData.height, pixels: imgData.data};
	}
}

typedef DecoderOptions = {
	var ?useTArray:Bool;
	var ?colorTransform:Null<Bool>;
	var ?formatAsRGBA:Bool;
	var ?tolerantDecoding:Bool;
	var ?maxResolutionInMP:Float;
	var ?maxMemoryUsageInMB:Float;
}

typedef ImageData = {
	var width:Int;
	var height:Int;
	var data:haxe.io.Bytes;
	var ?exifBuffer:haxe.io.Bytes;
	var ?comments:Array<String>;
	var colorSpace:String;
}

// Dynamic object used throughout parsing (mirrors JS objects keyed by
// component id, frame fields, etc.)
typedef ComponentMap = haxe.ds.IntMap<Component>;

typedef JfifInfo = {
	var version:{major:Int, minor:Int};
	var densityUnits:Int;
	var xDensity:Int;
	var yDensity:Int;
	var thumbWidth:Int;
	var thumbHeight:Int;
	var thumbData:haxe.io.Bytes;
}

typedef AdobeInfo = {
	var version:Int;
	var flags0:Int;
	var flags1:Int;
	var transformCode:Int;
}

// A decoded image component (one per channel).
typedef Component = {
	var h:Int;
	var v:Int;
	var ?quantizationIdx:Int;
	var ?quantizationTable:haxe.io.Bytes; // Int32 array stored as Bytes (4 bytes/entry)
	var ?huffmanTableDC:Array<Dynamic>;
	var ?huffmanTableAC:Array<Dynamic>;
	var ?blocksPerLine:Int;
	var ?blocksPerColumn:Int;
	var ?blocks:Array<Array<haxe.io.Bytes>>; // each block = Int32Array[64]
	var ?pred:Int;
	// After building:
	var ?lines:Array<haxe.io.Bytes>; // Uint8 lines
	var ?scaleX:Float;
	var ?scaleY:Float;
}

// Huffman node is either Array<Dynamic> (children) or Int (leaf value).
// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
// Read a signed 32-bit integer from a Bytes at index i (big-endian).
inline function getInt32(b:haxe.io.Bytes, i:Int):Int {
	return b.getInt32(i * 4);
}

inline function setInt32(b:haxe.io.Bytes, i:Int, v:Int):Void {
	b.setInt32(i * 4, v);
}

inline function newInt32Array(len:Int):haxe.io.Bytes {
	var b = haxe.io.Bytes.alloc(len * 4);
	b.fill(0, len * 4, 0);
	return b;
}

inline function newUint8Array(len:Int):haxe.io.Bytes {
	var b = haxe.io.Bytes.alloc(len);
	b.fill(0, len, 0);
	return b;
}

// ---------------------------------------------------------------------------
// Main class
// ---------------------------------------------------------------------------

class JpegImage {
	// ---- static DCT constants ----
	static final dctZigZag:Array<Int> = [
		 0,  1,  8, 16,  9,  2,  3, 10,
		17, 24, 32, 25, 18, 11,  4,  5,
		12, 19, 26, 33, 40, 48, 41, 34,
		27, 20, 13,  6,  7, 14, 21, 28,
		35, 42, 49, 56, 57, 50, 43, 36,
		29, 22, 15, 23, 30, 37, 44, 51,
		58, 59, 52, 45, 38, 31, 39, 46,
		53, 60, 61, 54, 47, 55, 62, 63
	];

	static inline final dctCos1:Int = 4017; // cos(pi/16)
	static inline final dctSin1:Int = 799; // sin(pi/16)
	static inline final dctCos3:Int = 3406; // cos(3*pi/16)
	static inline final dctSin3:Int = 2276; // sin(3*pi/16)
	static inline final dctCos6:Int = 1567; // cos(6*pi/16)
	static inline final dctSin6:Int = 3784; // sin(6*pi/16)
	static inline final dctSqrt2:Int = 5793; // sqrt(2)
	static inline final dctSqrt1d2:Int = 2896; // sqrt(2)/2

	static var totalBytesAllocated:Int = 0;
	static var maxMemoryUsageBytes:Int = 0;

	// ---- instance fields ----
	public var width:Int = 0;
	public var height:Int = 0;
	public var jfif:Null<JfifInfo> = null;
	public var adobe:Null<AdobeInfo> = null;
	public var components:Array<{lines:Array<haxe.io.Bytes>, scaleX:Float, scaleY:Float}> = [];
	public var comments:Array<String> = [];
	public var exifBuffer:Null<haxe.io.Bytes> = null;
	public var opts:DecoderOptions;

	public function new(?opts:DecoderOptions) {
		this.opts = opts != null ? opts : {
			useTArray: false,
			colorTransform: null,
			formatAsRGBA: true,
			tolerantDecoding: true,
			maxResolutionInMP: 100.0,
			maxMemoryUsageInMB: 512.0,
		};
		this.comments = [];
		this.components = [];
	}

	// ---- static helpers ----

	public static function resetMaxMemoryUsage(maxBytes:Int):Void {
		totalBytesAllocated = 0;
		maxMemoryUsageBytes = maxBytes;
	}

	public static function getBytesAllocated():Int {
		return totalBytesAllocated;
	}

	public static function requestMemoryAllocation(increaseAmount:Int = 0):Void {
		var total = totalBytesAllocated + increaseAmount;
		if (total > maxMemoryUsageBytes) {
			var exceeded = Math.ceil((total - maxMemoryUsageBytes) / 1024.0 / 1024.0);
			throw 'maxMemoryUsageInMB limit exceeded by at least ${exceeded}MB';
		}
		totalBytesAllocated = total;
	}

	static function buildHuffmanTable(codeLengths:haxe.io.Bytes, values:haxe.io.Bytes):Array<Dynamic> {
		var k = 0;
		var length = 16;
		while (length > 0 && codeLengths.get(length - 1) == 0)
			length--;

		// stack of { children: Array<Dynamic>, index: Int }
		var stack:Array<{children:Array<Dynamic>, index:Int}> = [];
		var root:{children:Array<Dynamic>, index:Int} = {children: [], index: 0};
		stack.push(root);
		var p = root;

		for (i in 0...length) {
			var numCodes = codeLengths.get(i);
			for (j in 0...numCodes) {
				p = stack.pop();
				p.children[p.index] = values.get(k);
				while (p.index > 0) {
					if (stack.length == 0)
						throw 'Could not recreate Huffman Table';
					p = stack.pop();
				}
				p.index++;
				stack.push(p);
				while (stack.length <= i) {
					var q:{children:Array<Dynamic>, index:Int} = {children: [], index: 0};
					p.children[p.index] = q.children;
					p = q;
					stack.push(p);
				}
				k++;
			}
			if (i + 1 < length) {
				var q:{children:Array<Dynamic>, index:Int} = {children: [], index: 0};
				p.children[p.index] = q.children;
				p = q;
				stack.push(p);
			}
		}

		return stack[0].children;
	}

	static inline function clampTo8bit(a:Float):Int {
		return a < 0 ? 0 : (a > 255 ? 255 : Std.int(a));
	}

	// ---- parse ----

	public function parse(data:haxe.io.Bytes):Void {
		var maxResolutionInPixels = (opts.maxResolutionInMP != null ? opts.maxResolutionInMP : 100.0) * 1000.0 * 1000.0;
		var offset = 0;

		inline function readUint16():Int {
			var v = (data.get(offset) << 8) | data.get(offset + 1);
			offset += 2;
			return v;
		}

		inline function readDataBlock():haxe.io.Bytes {
			var length = readUint16();
			var arr = data.sub(offset, length - 2);
			offset += length - 2;
			return arr;
		}

		function prepareComponents(frame:{
			samplesPerLine:Int,
			scanLines:Int,
			components:ComponentMap,
			componentsOrder:Array<Int>,
			maxH:Int,
			maxV:Int,
			mcusPerLine:Int,
			mcusPerColumn:Int,
		}):Void {
			var maxH = 1;
			var maxV = 1;
			for (comp in frame.components) {
				if (comp.h > maxH)
					maxH = comp.h;
				if (comp.v > maxV)
					maxV = comp.v;
			}
			var mcusPerLine = Math.ceil(frame.samplesPerLine / 8.0 / maxH);
			var mcusPerColumn = Math.ceil(frame.scanLines / 8.0 / maxV);

			for (comp in frame.components) {
				var blocksPerLine = Math.ceil(Math.ceil(frame.samplesPerLine / 8.0) * comp.h / maxH);
				var blocksPerColumn = Math.ceil(Math.ceil(frame.scanLines / 8.0) * comp.v / maxV);
				var bplMcu = mcusPerLine * comp.h;
				var bpcMcu = mcusPerColumn * comp.v;
				var blocksToAllocate = bpcMcu * bplMcu;

				requestMemoryAllocation(blocksToAllocate * 256);

				var blocks:Array<Array<haxe.io.Bytes>> = [];
				for (r in 0...bpcMcu) {
					var row:Array<haxe.io.Bytes> = [];
					for (c in 0...bplMcu)
						row.push(newInt32Array(64));
					blocks.push(row);
				}

				comp.blocksPerLine = blocksPerLine;
				comp.blocksPerColumn = blocksPerColumn;
				comp.blocks = blocks;
			}

			frame.maxH = maxH;
			frame.maxV = maxV;
			frame.mcusPerLine = mcusPerLine;
			frame.mcusPerColumn = mcusPerColumn;
		}

		var jfif:Null<JfifInfo> = null;
		var adobe:Null<AdobeInfo> = null;

		// frame is built dynamically; we track fields separately
		var frameObj:Null<{
			extended:Bool,
			progressive:Bool,
			precision:Int,
			scanLines:Int,
			samplesPerLine:Int,
			components:ComponentMap,
			componentsOrder:Array<Int>,
			maxH:Int,
			maxV:Int,
			mcusPerLine:Int,
			mcusPerColumn:Int,
		}> = null;

		var resetInterval:Int = 0;
		var quantizationTables:Array<Null<haxe.io.Bytes>> = [for (_ in 0...16) null];
		var frames:Array<Dynamic> = [];
		var huffmanTablesAC:Array<Array<Dynamic>> = [];
		var huffmanTablesDC:Array<Array<Dynamic>> = [];

		var fileMarker = readUint16();
		var malformedDataOffset = -1;

		if (fileMarker != 0xFFD8)
			throw 'SOI not found';
		fileMarker = readUint16();

		while (fileMarker != 0xFFD9) { // EOI
			var i:Int;
			var j:Int;

			switch (fileMarker) {
				case 0xFF00: // byte stuffing – skip

				case 0xFFE0 | 0xFFE1 | 0xFFE2 | 0xFFE3 | 0xFFE4 | 0xFFE5 | 0xFFE6 | 0xFFE7 | 0xFFE8 | 0xFFE9 | 0xFFEA | 0xFFEB | 0xFFEC | 0xFFED | 0xFFEE |
					0xFFEF | 0xFFFE:
					{
						var appData = readDataBlock();

						if (fileMarker == 0xFFFE) {
							// COM – comment
							var sb = new StringBuf();
							for (ci in 0...appData.length)
								sb.addChar(appData.get(ci));
							this.comments.push(sb.toString());
						}

						if (fileMarker == 0xFFE0) {
							// APP0 – JFIF
							if (appData.length >= 5 && appData.get(0) == 0x4A && appData.get(1) == 0x46 && appData.get(2) == 0x49 && appData.get(3) == 0x46
								&& appData.get(4) == 0) {
								jfif = {
									version: {major: appData.get(5), minor: appData.get(6)},
									densityUnits: appData.get(7),
									xDensity: (appData.get(8) << 8) | appData.get(9),
									yDensity: (appData.get(10) << 8) | appData.get(11),
									thumbWidth: appData.get(12),
									thumbHeight: appData.get(13),
									thumbData: appData.sub(14, 3 * appData.get(12) * appData.get(13)),
								};
							}
						}

						if (fileMarker == 0xFFE1) {
							// APP1 – EXIF
							if (appData.length >= 5 && appData.get(0) == 0x45 && appData.get(1) == 0x78 && appData.get(2) == 0x69 && appData.get(3) == 0x66
								&& appData.get(4) == 0) {
								this.exifBuffer = appData.sub(5, appData.length - 5);
							}
						}

						if (fileMarker == 0xFFEE) {
							// APP14 – Adobe
							if (appData.length >= 6 && appData.get(0) == 0x41 && appData.get(1) == 0x64 && appData.get(2) == 0x6F && appData.get(3) == 0x62
								&& appData.get(4) == 0x65 && appData.get(5) == 0) {
								adobe = {
									version: appData.get(6),
									flags0: (appData.get(7) << 8) | appData.get(8),
									flags1: (appData.get(9) << 8) | appData.get(10),
									transformCode: appData.get(11),
								};
							}
						}
					}

				case 0xFFDB:
					{
						// DQT – Define Quantization Tables
						var qtLength = readUint16();
						var qtEnd = qtLength + offset - 2;
						while (offset < qtEnd) {
							var qtSpec = data.get(offset++);
							requestMemoryAllocation(64 * 4);
							var tableData = newInt32Array(64);
							if ((qtSpec >> 4) == 0) {
								for (jj in 0...64) {
									var z = dctZigZag[jj];
									setInt32(tableData, z, data.get(offset++));
								}
							} else if ((qtSpec >> 4) == 1) {
								for (jj in 0...64) {
									var z = dctZigZag[jj];
									setInt32(tableData, z, readUint16());
								}
							} else {
								throw 'DQT: invalid table spec';
							}
							quantizationTables[qtSpec & 15] = tableData;
						}
					}

				case 0xFFC0 | 0xFFC1 | 0xFFC2:
					{
						// SOF0/SOF1/SOF2 – Start of Frame
						readUint16(); // skip length
						var frame:{
							extended:Bool,
							progressive:Bool,
							precision:Int,
							scanLines:Int,
							samplesPerLine:Int,
							components:ComponentMap,
							componentsOrder:Array<Int>,
							maxH:Int,
							maxV:Int,
							mcusPerLine:Int,
							mcusPerColumn:Int,
						} = {
							extended: fileMarker == 0xFFC1,
							progressive: fileMarker == 0xFFC2,
							precision: data.get(offset++),
							scanLines: 0,
							samplesPerLine: 0,
							components: new haxe.ds.IntMap(),
							componentsOrder: [],
							maxH: 1,
							maxV: 1,
							mcusPerLine: 0,
							mcusPerColumn: 0,
						};
						frame.scanLines = readUint16();
						frame.samplesPerLine = readUint16();

						var pixelsInFrame:Float = frame.scanLines * frame.samplesPerLine;
						if (pixelsInFrame > maxResolutionInPixels) {
							var exceeded = Math.ceil((pixelsInFrame - maxResolutionInPixels) / 1e6);
							throw 'maxResolutionInMP limit exceeded by ${exceeded}MP';
						}

						var componentsCount = data.get(offset++);
						if (componentsCount == 0)
							throw 'Invalid sampling factor, expected values above 0';

						for (ii in 0...componentsCount) {
							var compId = data.get(offset);
							var h = data.get(offset + 1) >> 4;
							var v = data.get(offset + 1) & 15;
							var qId = data.get(offset + 2);
							if (h <= 0 || v <= 0)
								throw 'Invalid sampling factor, expected values above 0';
							frame.componentsOrder.push(compId);
							frame.components.set(compId, {
								h: h,
								v: v,
								quantizationIdx: qId,
							});
							offset += 3;
						}
						prepareComponents(frame);
						frames.push(frame);
						frameObj = frame;
					}

				case 0xFFC4:
					{
						// DHT – Define Huffman Tables
						var huffLen = readUint16();
						var huffEnd = huffLen - 2;
						var consumed = 0;
						while (consumed < huffEnd) {
							var htSpec = data.get(offset++);
							var codeLengths = newUint8Array(16);
							var clSum = 0;
							for (jj in 0...16) {
								var cl = data.get(offset++);
								codeLengths.set(jj, cl);
								clSum += cl;
							}
							requestMemoryAllocation(16 + clSum);
							var huffVals = newUint8Array(clSum);
							for (jj in 0...clSum)
								huffVals.set(jj, data.get(offset++));
							consumed += 17 + clSum;
							var table = buildHuffmanTable(codeLengths, huffVals);
							var idx = htSpec & 15;
							if ((htSpec >> 4) == 0) {
								while (huffmanTablesDC.length <= idx)
									huffmanTablesDC.push([]);
								huffmanTablesDC[idx] = table;
							} else {
								while (huffmanTablesAC.length <= idx)
									huffmanTablesAC.push([]);
								huffmanTablesAC[idx] = table;
							}
						}
					}

				case 0xFFDD:
					{
						// DRI – Define Restart Interval
						readUint16(); // skip length
						resetInterval = readUint16();
					}

				case 0xFFDC:
					{
						// Number of Lines marker
						readUint16();
						readUint16();
					}

				case 0xFFDA:
					{
						// SOS – Start of Scan
						readUint16(); // skip scan header length
						var selectorsCount = data.get(offset++);
						var scanComponents:Array<Component> = [];
						if (frameObj == null)
							throw 'SOS before SOF';
						for (ii in 0...selectorsCount) {
							var comp = frameObj.components.get(data.get(offset++));
							var tableSpec = data.get(offset++);
							comp.huffmanTableDC = huffmanTablesDC[tableSpec >> 4];
							comp.huffmanTableAC = huffmanTablesAC[tableSpec & 15];
							scanComponents.push(comp);
						}
						var spectralStart = data.get(offset++);
						var spectralEnd = data.get(offset++);
						var successiveApproximation = data.get(offset++);
						var processed = decodeScan(data, offset, frameObj, scanComponents, resetInterval, spectralStart, spectralEnd,
							successiveApproximation >> 4, successiveApproximation & 15,);
						offset += processed;
					}

				case 0xFFFF:
					{
						// Fill bytes
						if (data.get(offset) != 0xFF)
							offset--;
					}

				default:
					{
						if (data.get(offset - 3) == 0xFF && data.get(offset - 2) >= 0xC0 && data.get(offset - 2) <= 0xFE) {
							offset -= 3;
						} else if (fileMarker == 0xE0 || fileMarker == 0xE1) {
							if (malformedDataOffset != -1) {
								throw 'first unknown JPEG marker at offset ${StringTools.hex(malformedDataOffset)}, '
									+ 'second unknown JPEG marker ${StringTools.hex(fileMarker)} at offset ${StringTools.hex(offset - 1)}';
							}
							malformedDataOffset = offset - 1;
							var nextOffset = readUint16();
							if (data.get(offset + nextOffset - 2) == 0xFF) {
								offset += nextOffset - 2;
							}
						} else if ((fileMarker & 0xFF00) == 0xFF00) {
							var markerLength = readUint16();
							if (markerLength > 2)
								offset += markerLength - 2;
						} else {
							throw 'unknown JPEG marker ${StringTools.hex(fileMarker)}';
						}
					}
			}

			fileMarker = readUint16();
		}

		if (frames.length != 1)
			throw 'only single frame JPEGs supported';

		// Assign quantization tables to components
		for (fr in frames) {
			var cp:ComponentMap = fr.components;
			for (comp in cp) {
				comp.quantizationTable = quantizationTables[comp.quantizationIdx];
				comp.quantizationIdx = -1; // clear idx
			}
		}

		var frame = frameObj;
		if (frame == null)
			throw 'No frame parsed';

		this.width = frame.samplesPerLine;
		this.height = frame.scanLines;
		this.jfif = jfif;
		this.adobe = adobe;
		this.components = [];

		for (cid in frame.componentsOrder) {
			var comp = frame.components.get(cid);
			this.components.push({
				lines: buildComponentData(comp),
				scaleX: comp.h / frame.maxH,
				scaleY: comp.v / frame.maxV,
			});
		}
	}

	// ---- buildComponentData ----

	function buildComponentData(component:Component):Array<haxe.io.Bytes> {
		var lines:Array<haxe.io.Bytes> = [];
		var blocksPerLine = component.blocksPerLine;
		var blocksPerColumn = component.blocksPerColumn;
		var samplesPerLine = blocksPerLine << 3;
		var R = newInt32Array(64); // work buffer (Int32)
		var r = newUint8Array(64); // work buffer (Uint8)

		function quantizeAndInverse(zz:haxe.io.Bytes, dataOut:haxe.io.Bytes, dataIn:haxe.io.Bytes):Void {
			var qt = component.quantizationTable;
			var v0:Int;
			var v1:Int;
			var v2:Int;
			var v3:Int;
			var v4:Int;
			var v5:Int;
			var v6:Int;
			var v7:Int;
			var t:Int;

			// dequantize
			for (ii in 0...64)
				setInt32(dataIn, ii, getInt32(zz, ii) * getInt32(qt, ii));

			// inverse DCT on rows
			for (ii in 0...8) {
				var row = 8 * ii;
				if (getInt32(dataIn, 1 + row) == 0 && getInt32(dataIn, 2 + row) == 0 && getInt32(dataIn, 3 + row) == 0 && getInt32(dataIn, 4 + row) == 0
					&& getInt32(dataIn, 5 + row) == 0 && getInt32(dataIn, 6 + row) == 0 && getInt32(dataIn, 7 + row) == 0) {
					t = (dctSqrt2 * getInt32(dataIn, 0 + row) + 512) >> 10;
					for (k in 0...8)
						setInt32(dataIn, k + row, t);
					continue;
				}
				// stage 4
				v0 = (dctSqrt2 * getInt32(dataIn, 0 + row) + 128) >> 8;
				v1 = (dctSqrt2 * getInt32(dataIn, 4 + row) + 128) >> 8;
				v2 = getInt32(dataIn, 2 + row);
				v3 = getInt32(dataIn, 6 + row);
				v4 = (dctSqrt1d2 * (getInt32(dataIn, 1 + row) - getInt32(dataIn, 7 + row)) + 128) >> 8;
				v7 = (dctSqrt1d2 * (getInt32(dataIn, 1 + row) + getInt32(dataIn, 7 + row)) + 128) >> 8;
				v5 = getInt32(dataIn, 3 + row) << 4;
				v6 = getInt32(dataIn, 5 + row) << 4;
				// stage 3
				t = (v0 - v1 + 1) >> 1;
				v0 = (v0 + v1 + 1) >> 1;
				v1 = t;
				t = (v2 * dctSin6 + v3 * dctCos6 + 128) >> 8;
				v2 = (v2 * dctCos6 - v3 * dctSin6 + 128) >> 8;
				v3 = t;
				t = (v4 - v6 + 1) >> 1;
				v4 = (v4 + v6 + 1) >> 1;
				v6 = t;
				t = (v7 + v5 + 1) >> 1;
				v5 = (v7 - v5 + 1) >> 1;
				v7 = t;
				// stage 2
				t = (v0 - v3 + 1) >> 1;
				v0 = (v0 + v3 + 1) >> 1;
				v3 = t;
				t = (v1 - v2 + 1) >> 1;
				v1 = (v1 + v2 + 1) >> 1;
				v2 = t;
				t = (v4 * dctSin3 + v7 * dctCos3 + 2048) >> 12;
				v4 = (v4 * dctCos3 - v7 * dctSin3 + 2048) >> 12;
				v7 = t;
				t = (v5 * dctSin1 + v6 * dctCos1 + 2048) >> 12;
				v5 = (v5 * dctCos1 - v6 * dctSin1 + 2048) >> 12;
				v6 = t;
				// stage 1
				setInt32(dataIn, 0 + row, v0 + v7);
				setInt32(dataIn, 7 + row, v0 - v7);
				setInt32(dataIn, 1 + row, v1 + v6);
				setInt32(dataIn, 6 + row, v1 - v6);
				setInt32(dataIn, 2 + row, v2 + v5);
				setInt32(dataIn, 5 + row, v2 - v5);
				setInt32(dataIn, 3 + row, v3 + v4);
				setInt32(dataIn, 4 + row, v3 - v4);
			}

			// inverse DCT on columns
			for (ii in 0...8) {
				var col = ii;
				if (getInt32(dataIn, 1 * 8 + col) == 0 && getInt32(dataIn, 2 * 8 + col) == 0 && getInt32(dataIn, 3 * 8 + col) == 0
					&& getInt32(dataIn, 4 * 8 + col) == 0 && getInt32(dataIn, 5 * 8 + col) == 0 && getInt32(dataIn, 6 * 8 + col) == 0
					&& getInt32(dataIn, 7 * 8 + col) == 0) {
					t = (dctSqrt2 * getInt32(dataIn, ii) + 8192) >> 14;
					for (k in 0...8)
						setInt32(dataIn, k * 8 + col, t);
					continue;
				}
				// stage 4
				v0 = (dctSqrt2 * getInt32(dataIn, 0 * 8 + col) + 2048) >> 12;
				v1 = (dctSqrt2 * getInt32(dataIn, 4 * 8 + col) + 2048) >> 12;
				v2 = getInt32(dataIn, 2 * 8 + col);
				v3 = getInt32(dataIn, 6 * 8 + col);
				v4 = (dctSqrt1d2 * (getInt32(dataIn, 1 * 8 + col) - getInt32(dataIn, 7 * 8 + col)) + 2048) >> 12;
				v7 = (dctSqrt1d2 * (getInt32(dataIn, 1 * 8 + col) + getInt32(dataIn, 7 * 8 + col)) + 2048) >> 12;
				v5 = getInt32(dataIn, 3 * 8 + col);
				v6 = getInt32(dataIn, 5 * 8 + col);
				// stage 3
				t = (v0 - v1 + 1) >> 1;
				v0 = (v0 + v1 + 1) >> 1;
				v1 = t;
				t = (v2 * dctSin6 + v3 * dctCos6 + 2048) >> 12;
				v2 = (v2 * dctCos6 - v3 * dctSin6 + 2048) >> 12;
				v3 = t;
				t = (v4 - v6 + 1) >> 1;
				v4 = (v4 + v6 + 1) >> 1;
				v6 = t;
				t = (v7 + v5 + 1) >> 1;
				v5 = (v7 - v5 + 1) >> 1;
				v7 = t;
				// stage 2
				t = (v0 - v3 + 1) >> 1;
				v0 = (v0 + v3 + 1) >> 1;
				v3 = t;
				t = (v1 - v2 + 1) >> 1;
				v1 = (v1 + v2 + 1) >> 1;
				v2 = t;
				t = (v4 * dctSin3 + v7 * dctCos3 + 2048) >> 12;
				v4 = (v4 * dctCos3 - v7 * dctSin3 + 2048) >> 12;
				v7 = t;
				t = (v5 * dctSin1 + v6 * dctCos1 + 2048) >> 12;
				v5 = (v5 * dctCos1 - v6 * dctSin1 + 2048) >> 12;
				v6 = t;
				// stage 1
				setInt32(dataIn, 0 * 8 + col, v0 + v7);
				setInt32(dataIn, 7 * 8 + col, v0 - v7);
				setInt32(dataIn, 1 * 8 + col, v1 + v6);
				setInt32(dataIn, 6 * 8 + col, v1 - v6);
				setInt32(dataIn, 2 * 8 + col, v2 + v5);
				setInt32(dataIn, 5 * 8 + col, v2 - v5);
				setInt32(dataIn, 3 * 8 + col, v3 + v4);
				setInt32(dataIn, 4 * 8 + col, v3 - v4);
			}

			// convert to 8-bit
			for (ii in 0...64) {
				var sample = 128 + ((getInt32(dataIn, ii) + 8) >> 4);
				dataOut.set(ii, sample < 0 ? 0 : (sample > 0xFF ? 0xFF : sample));
			}
		}

		requestMemoryAllocation(samplesPerLine * blocksPerColumn * 8);

		for (blockRow in 0...blocksPerColumn) {
			var scanLine = blockRow << 3;
			for (ii in 0...8)
				lines.push(newUint8Array(samplesPerLine));
			for (blockCol in 0...blocksPerLine) {
				quantizeAndInverse(component.blocks[blockRow][blockCol], r, R);
				var off = 0;
				var sample = blockCol << 3;
				for (jj in 0...8) {
					var line = lines[scanLine + jj];
					for (ii in 0...8) {
						line.set(sample + ii, r.get(off++));
					}
				}
			}
		}
		return lines;
	}

	// ---- getData ----

	public function getData(width:Int, height:Int):haxe.io.Bytes {
		var scaleX:Float = this.width / width;
		var scaleY:Float = this.height / height;
		var offset = 0;
		var dataLength = width * height * this.components.length;
		requestMemoryAllocation(dataLength);
		var data = newUint8Array(dataLength);

		switch (this.components.length) {
			case 1:
				var c1 = this.components[0];
				for (y in 0...height) {
					var c1Line = c1.lines[Std.int(y * c1.scaleY * scaleY)];
					for (x in 0...width) {
						data.set(offset++, c1Line.get(Std.int(x * c1.scaleX * scaleX)));
					}
				}

			case 2:
				var c1 = this.components[0];
				var c2 = this.components[1];
				for (y in 0...height) {
					var c1Line = c1.lines[Std.int(y * c1.scaleY * scaleY)];
					var c2Line = c2.lines[Std.int(y * c2.scaleY * scaleY)];
					for (x in 0...width) {
						data.set(offset++, c1Line.get(Std.int(x * c1.scaleX * scaleX)));
						data.set(offset++, c2Line.get(Std.int(x * c2.scaleX * scaleX)));
					}
				}

			case 3:
				var colorTransform = true;
				if (adobe != null && adobe.transformCode != 0)
					colorTransform = true;
				else if (opts.colorTransform != null)
					colorTransform = opts.colorTransform;

				var c1 = this.components[0];
				var c2 = this.components[1];
				var c3 = this.components[2];
				for (y in 0...height) {
					var c1Line = c1.lines[Std.int(y * c1.scaleY * scaleY)];
					var c2Line = c2.lines[Std.int(y * c2.scaleY * scaleY)];
					var c3Line = c3.lines[Std.int(y * c3.scaleY * scaleY)];
					for (x in 0...width) {
						var R:Int;
						var G:Int;
						var B:Int;
						if (!colorTransform) {
							R = c1Line.get(Std.int(x * c1.scaleX * scaleX));
							G = c2Line.get(Std.int(x * c2.scaleX * scaleX));
							B = c3Line.get(Std.int(x * c3.scaleX * scaleX));
						} else {
							var Y = c1Line.get(Std.int(x * c1.scaleX * scaleX));
							var Cb = c2Line.get(Std.int(x * c2.scaleX * scaleX));
							var Cr = c3Line.get(Std.int(x * c3.scaleX * scaleX));
							R = clampTo8bit(Y + 1.402 * (Cr - 128));
							G = clampTo8bit(Y - 0.3441363 * (Cb - 128) - 0.71413636 * (Cr - 128));
							B = clampTo8bit(Y + 1.772 * (Cb - 128));
						}
						data.set(offset++, R);
						data.set(offset++, G);
						data.set(offset++, B);
					}
				}

			case 4:
				if (adobe == null)
					throw 'Unsupported color mode (4 components)';
				var colorTransform = false;
				if (adobe.transformCode != 0)
					colorTransform = true;
				else if (opts.colorTransform != null)
					colorTransform = opts.colorTransform;

				var c1 = this.components[0];
				var c2 = this.components[1];
				var c3 = this.components[2];
				var c4 = this.components[3];
				for (y in 0...height) {
					var c1Line = c1.lines[Std.int(y * c1.scaleY * scaleY)];
					var c2Line = c2.lines[Std.int(y * c2.scaleY * scaleY)];
					var c3Line = c3.lines[Std.int(y * c3.scaleY * scaleY)];
					var c4Line = c4.lines[Std.int(y * c4.scaleY * scaleY)];
					for (x in 0...width) {
						var C:Int;
						var M:Int;
						var Ye:Int;
						var K:Int;
						if (!colorTransform) {
							C = c1Line.get(Std.int(x * c1.scaleX * scaleX));
							M = c2Line.get(Std.int(x * c2.scaleX * scaleX));
							Ye = c3Line.get(Std.int(x * c3.scaleX * scaleX));
							K = c4Line.get(Std.int(x * c4.scaleX * scaleX));
						} else {
							var Y = c1Line.get(Std.int(x * c1.scaleX * scaleX));
							var Cb = c2Line.get(Std.int(x * c2.scaleX * scaleX));
							var Cr = c3Line.get(Std.int(x * c3.scaleX * scaleX));
							K = c4Line.get(Std.int(x * c4.scaleX * scaleX));
							C = 255 - clampTo8bit(Y + 1.402 * (Cr - 128));
							M = 255 - clampTo8bit(Y - 0.3441363 * (Cb - 128) - 0.71413636 * (Cr - 128));
							Ye = 255 - clampTo8bit(Y + 1.772 * (Cb - 128));
						}
						data.set(offset++, 255 - C);
						data.set(offset++, 255 - M);
						data.set(offset++, 255 - Ye);
						data.set(offset++, 255 - K);
					}
				}

			default:
				throw 'Unsupported color mode';
		}
		return data;
	}

	// ---- copyToImageData ----

	public function copyToImageData(image:{width:Int, height:Int, data:haxe.io.Bytes}, formatAsRGBA:Bool):Void {
		var width = image.width;
		var height = image.height;
		var dst = image.data;
		var src = getData(width, height);
		var i = 0;
		var j = 0;

		switch (this.components.length) {
			case 1:
				for (_ in 0...height) {
					for (__ in 0...width) {
						var Y = src.get(i++);
						dst.set(j++, Y);
						dst.set(j++, Y);
						dst.set(j++, Y);
						if (formatAsRGBA)
							dst.set(j++, 255);
					}
				}
			case 3:
				for (_ in 0...height) {
					for (__ in 0...width) {
						dst.set(j++, src.get(i++));
						dst.set(j++, src.get(i++));
						dst.set(j++, src.get(i++));
						if (formatAsRGBA)
							dst.set(j++, 255);
					}
				}
			case 4:
				for (_ in 0...height) {
					for (__ in 0...width) {
						var C = src.get(i++);
						var M = src.get(i++);
						var Y = src.get(i++);
						var K = src.get(i++);
						dst.set(j++, 255 - clampTo8bit(C * (1 - K / 255.0) + K));
						dst.set(j++, 255 - clampTo8bit(M * (1 - K / 255.0) + K));
						dst.set(j++, 255 - clampTo8bit(Y * (1 - K / 255.0) + K));
						if (formatAsRGBA)
							dst.set(j++, 255);
					}
				}
			default:
				throw 'Unsupported color mode';
		}
	}

	// ---- decodeScan ----

	function decodeScan(data:haxe.io.Bytes, startOffset:Int, frame:{
		mcusPerLine:Int,
		mcusPerColumn:Int,
		progressive:Bool,
		components:ComponentMap,
	}, components:Array<Component>,
			resetInterval:Int, spectralStart:Int, spectralEnd:Int, successivePrev:Int, successive:Int,):Int {
		var mcusPerLine = frame.mcusPerLine;
		var progressive = frame.progressive;
		var offset = startOffset;
		var bitsData = 0;
		var bitsCount = 0;

		// ---- inner bit-reading helpers ----

		function readBit():Int {
			if (bitsCount > 0) {
				bitsCount--;
				return (bitsData >> bitsCount) & 1;
			}
			bitsData = data.get(offset++);
			if (bitsData == 0xFF) {
				var nextByte = data.get(offset++);
				if (nextByte != 0)
					throw 'unexpected marker: ${StringTools.hex((bitsData << 8) | nextByte)}';
				// unstuff 0
			}
			bitsCount = 7;
			return bitsData >>> 7;
		}

		function decodeHuffman(tree:Array<Dynamic>):Null<Int> {
			var node:Dynamic = tree;
			while (true) {
				var bit = readBit();
				node = (node : Array<Dynamic>)[bit];
				if (Std.isOfType(node, Int))
					return node;
				if (!Std.isOfType(node, Array))
					throw 'invalid huffman sequence';
			}
			return null;
		}

		function receive(length:Int):Null<Int> {
			var n = 0;
			while (length > 0) {
				n = (n << 1) | readBit();
				length--;
			}
			return n;
		}

		function receiveAndExtend(length:Int):Null<Int> {
			var n = receive(length);
			if (n == null)
				return null;
			if (n >= (1 << (length - 1)))
				return n;
			return n + (-1 << length) + 1;
		}

		// ---- decode functions ----

		function decodeBaseline(comp:Component, zz:haxe.io.Bytes):Void {
			var t = decodeHuffman(comp.huffmanTableDC);
			if (t == null)
				throw 'invalid huffman sequence. t is null';
			var diff = t == 0 ? 0 : receiveAndExtend(t);
			comp.pred += diff;
			setInt32(zz, 0, comp.pred);
			var k = 1;
			while (k < 64) {
				var rs = decodeHuffman(comp.huffmanTableAC);
				if (rs == null)
					throw 'invalid huffman sequence. rs is null';
				var s = rs & 15;
				var r = rs >> 4;
				if (s == 0) {
					if (r < 15)
						break;
					k += 16;
					continue;
				}
				k += r;
				var z = dctZigZag[k];
				var v = receiveAndExtend(s);
				if (v == null)
					throw 'invalid huffman sequence. v is null';
				setInt32(zz, z, v);
				k++;
			}
		}

		function decodeDCFirst(comp:Component, zz:haxe.io.Bytes):Void {
			var t = decodeHuffman(comp.huffmanTableDC);
			if (t == null)
				throw 'invalid huffman sequence. t is null';
			var a = t == 0 ? 0 : receiveAndExtend(t);
			comp.pred += (a << successive);
			setInt32(zz, 0, comp.pred);
		}

		function decodeDCSuccessive(comp:Component, zz:haxe.io.Bytes):Void {
			setInt32(zz, 0, getInt32(zz, 0) | (readBit() << successive));
		}

		var eobrun = 0;

		function decodeACFirst(comp:Component, zz:haxe.io.Bytes):Void {
			if (eobrun > 0) {
				eobrun--;
				return;
			}
			var k = spectralStart;
			var e = spectralEnd;
			while (k <= e) {
				var rs = decodeHuffman(comp.huffmanTableAC);
				if (rs == null)
					throw 'invalid huffman sequence. rs is null';
				var s = rs & 15;
				var r = rs >> 4;
				if (s == 0) {
					if (r < 15) {
						var b = receive(r);
						if (b == null)
							throw 'invalid huffman sequence. b is null';
						eobrun = b + (1 << r) - 1;
						break;
					}
					k += 16;
					continue;
				}
				k += r;
				var z = dctZigZag[k];
				var v = receiveAndExtend(s);
				if (v == null)
					throw 'invalid huffman sequence. v is null';
				setInt32(zz, z, v * (1 << successive));
				k++;
			}
		}

		var successiveACState = 0;
		var successiveACNextValue = 0;

		function decodeACSuccessive(comp:Component, zz:haxe.io.Bytes):Void {
			var k = spectralStart;
			var e = spectralEnd;
			var r = 0;
			while (k <= e) {
				var z = dctZigZag[k];
				var zzVal = getInt32(zz, z);
				var direction = zzVal < 0 ? -1 : 1;
				switch (successiveACState) {
					case 0:
						{
							var rs = decodeHuffman(comp.huffmanTableAC);
							if (rs == null)
								throw 'invalid huffman sequence. rs is null';
							var s = rs & 15;
							r = rs >> 4;
							if (s == 0) {
								if (r < 15) {
									var b = receive(r);
									if (b == null)
										throw 'invalid huffman sequence. b is null';
									eobrun = b + (1 << r);
									successiveACState = 4;
								} else {
									r = 16;
									successiveACState = 1;
								}
							} else {
								if (s != 1)
									throw 'invalid ACn encoding';
								var v = receiveAndExtend(s);
								if (v == null)
									throw 'invalid huffman sequence. v is null';
								successiveACNextValue = v;
								successiveACState = r != 0 ? 2 : 3;
							}
							continue;
						}
					case 1 | 2:
						if (zzVal != 0) {
							setInt32(zz, z, zzVal + (readBit() << successive) * direction);
						} else {
							r--;
							if (r == 0)
								successiveACState = successiveACState == 2 ? 3 : 0;
						}
					case 3:
						if (zzVal != 0) {
							setInt32(zz, z, zzVal + (readBit() << successive) * direction);
						} else {
							setInt32(zz, z, successiveACNextValue << successive);
							successiveACState = 0;
						}
					case 4:
						if (zzVal != 0) {
							setInt32(zz, z, zzVal + (readBit() << successive) * direction);
						}
				}
				k++;
			}
			if (successiveACState == 4) {
				eobrun--;
				if (eobrun == 0)
					successiveACState = 0;
			}
		}

		// ---- MCU / block dispatch ----

		function decodeMcu(comp:Component, decodeFn:(Component, haxe.io.Bytes) -> Void, mcu:Int, row:Int, col:Int):Void {
			var mcuRow = Std.int(mcu / mcusPerLine);
			var mcuCol = mcu % mcusPerLine;
			var blockRow = mcuRow * comp.v + row;
			var blockCol = mcuCol * comp.h + col;
			if (comp.blocks[blockRow] == null && opts.tolerantDecoding)
				return;
			decodeFn(comp, comp.blocks[blockRow][blockCol]);
		}

		function decodeBlock(comp:Component, decodeFn:(Component, haxe.io.Bytes) -> Void, mcu:Int):Void {
			var blockRow = Std.int(mcu / comp.blocksPerLine);
			var blockCol = mcu % comp.blocksPerLine;
			if (comp.blocks[blockRow] == null && opts.tolerantDecoding)
				return;
			decodeFn(comp, comp.blocks[blockRow][blockCol]);
		}

		// ---- select decode function ----

		var decodeFn:(Component, haxe.io.Bytes) -> Void;
		if (progressive) {
			if (spectralStart == 0)
				decodeFn = successivePrev == 0 ? decodeDCFirst : decodeDCSuccessive;
			else
				decodeFn = successivePrev == 0 ? decodeACFirst : decodeACSuccessive;
		} else {
			decodeFn = decodeBaseline;
		}

		var mcu = 0;
		var mcuExpected:Int;
		var componentsLength = components.length;

		if (componentsLength == 1) {
			mcuExpected = components[0].blocksPerLine * components[0].blocksPerColumn;
		} else {
			mcuExpected = mcusPerLine * frame.mcusPerColumn;
		}

		if (resetInterval == 0)
			resetInterval = mcuExpected;

		while (mcu < mcuExpected) {
			for (ii in 0...componentsLength)
				components[ii].pred = 0;
			eobrun = 0;

			if (componentsLength == 1) {
				var comp = components[0];
				for (n in 0...resetInterval) {
					decodeBlock(comp, decodeFn, mcu);
					mcu++;
				}
			} else {
				for (n in 0...resetInterval) {
					for (ii in 0...componentsLength) {
						var comp = components[ii];
						var h = comp.h;
						var v = comp.v;
						for (jj in 0...v) {
							for (kk in 0...h) {
								decodeMcu(comp, decodeFn, mcu, jj, kk);
							}
						}
					}
					mcu++;
					if (mcu == mcuExpected)
						break;
				}
			}

			// Skip trailing bytes until next marker
			if (mcu == mcuExpected) {
				while (offset < data.length - 2) {
					if (data.get(offset) == 0xFF && data.get(offset + 1) != 0x00)
						break;
					offset++;
				}
			}

			// Find marker
			bitsCount = 0;
			var marker = (data.get(offset) << 8) | data.get(offset + 1);
			if (marker < 0xFF00)
				throw 'marker was not found';
			if (marker >= 0xFFD0 && marker <= 0xFFD7) { // RSTx
				offset += 2;
			} else {
				break;
			}
		}

		return offset - startOffset;
	}

	// ---------------------------------------------------------------------------
	// Top-level decode function
	// ---------------------------------------------------------------------------

	public static function decode(jpegData:haxe.io.Bytes, ?userOpts:DecoderOptions):ImageData {
		var opts:DecoderOptions = {
			colorTransform: null,
			useTArray: false,
			formatAsRGBA: true,
			tolerantDecoding: true,
			maxResolutionInMP: 100.0,
			maxMemoryUsageInMB: 512.0,
		};
		if (userOpts != null) {
			if (userOpts.colorTransform != null)
				opts.colorTransform = userOpts.colorTransform;
			if (userOpts.useTArray != null)
				opts.useTArray = userOpts.useTArray;
			if (userOpts.formatAsRGBA != null)
				opts.formatAsRGBA = userOpts.formatAsRGBA;
			if (userOpts.tolerantDecoding != null)
				opts.tolerantDecoding = userOpts.tolerantDecoding;
			if (userOpts.maxResolutionInMP != null)
				opts.maxResolutionInMP = userOpts.maxResolutionInMP;
			if (userOpts.maxMemoryUsageInMB != null)
				opts.maxMemoryUsageInMB = userOpts.maxMemoryUsageInMB;
		}

		var decoder = new JpegImage(opts);
		JpegImage.resetMaxMemoryUsage(Std.int(opts.maxMemoryUsageInMB * 1024 * 1024));
		decoder.parse(jpegData);

		var channels = opts.formatAsRGBA ? 4 : 3;
		var bytesNeeded = decoder.width * decoder.height * channels;
		JpegImage.requestMemoryAllocation(bytesNeeded);

		var imageData = haxe.io.Bytes.alloc(bytesNeeded);
		var image:ImageData = {
			width: decoder.width,
			height: decoder.height,
			exifBuffer: decoder.exifBuffer,
			data: imageData,
			comments: decoder.comments.length > 0 ? decoder.comments : null,
			colorSpace: 'srgb',
		};

		decoder.copyToImageData(image, opts.formatAsRGBA);
		return image;
	}
}