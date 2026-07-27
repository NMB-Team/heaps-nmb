package h3d.impl.driver.dx12.resource;

#if (limen && gfx_dx12)
import limen.graphics.d3d12.DX12Core.DxgiFormat;

import h3d.impl.driver.dx12.descriptor.BlockHeap;

class TextureData extends ResourceData {
	public var format : DxgiFormat;
	public var color : h3d.Vector4;
	var clearColorChanges : Int;
	var cpuViewBits : Int = -1;
	var cpuViewIndex : Int = -1;
	var cpuViewsMap : Map<Int, Int>;

	inline public function getView(bits:Int) {
		if(cpuViewBits == bits)
			return cpuViewIndex;
		if(cpuViewsMap != null) {
			var idx = cpuViewsMap.get(bits);
			return idx != null ? idx : -1;
		}
		return -1;
	}

	public function setView(bits:Int, idx:Int) {
		if(cpuViewIndex < 0) {
			cpuViewIndex = idx;
			cpuViewBits = bits;
			return;
		}
		if(cpuViewsMap == null)
			cpuViewsMap = new Map();
		cpuViewsMap.set(bits, idx);
	}

	public function setClearColor(c:h3d.Vector4) {
		var color = color;
		if(clearColorChanges > 10 || (color.r == c.r && color.g == c.g && color.b == c.b && color.a == c.a))
			return false;
		clearColorChanges++;
		color.load(c);
		return true;
	}

	public function disposeViews(heap:BlockHeap) {
		if(cpuViewIndex >= 0) {
			heap.disposeIndex(cpuViewIndex);
			cpuViewIndex = -1;
			cpuViewBits = -1;
		}
		if(cpuViewsMap != null) {
			for(v in cpuViewsMap)
				heap.disposeIndex(v);
			cpuViewsMap = null;
		}
	}
}
#end
