package h3d.impl.driver.dx12.resource;

#if ((hldx && gfx_dx12) || (hlsdl && gfx_dx12))
import h3d.impl.driver.dx12.descriptor.BlockHeap;

class BufferData extends ResourceData {
	public var view : dx.Dx12.VertexBufferView;
	public var iview : dx.Dx12.IndexBufferView;
	public var handle : h3d.BufferHandle = null;
	public var cViewIndex : Int = -1;
	public var sViewIndex : Int = -1;
	public var sViewStride : Int = -1;
	public var sViewsMap : Map<Int, Int>;
	public var uViewIndex : Int = -1;
	public var uViewStride : Int = -1;
	public var uViewsMap : Map<Int, Int>;
	public var size : Int;

	inline public function getSRV(stride:Int) {
		if(sViewStride == stride)
			return sViewIndex;
		if(sViewsMap != null) {
			var idx = sViewsMap.get(stride);
			return idx != null ? idx : -1;
		}
		return -1;
	}

	public function setSRV(stride:Int, idx:Int) {
		if(sViewIndex < 0) {
			sViewIndex = idx;
			sViewStride = stride;
			return;
		}
		if(sViewsMap == null)
			sViewsMap = new Map();
		sViewsMap.set(stride, idx);
	}

	inline public function getUAV(stride:Int) {
		if(uViewStride == stride)
			return uViewIndex;
		if(uViewsMap != null) {
			var idx = uViewsMap.get(stride);
			return idx != null ? idx : -1;
		}
		return -1;
	}

	public function setUAV(stride:Int, idx:Int) {
		if(uViewIndex < 0) {
			uViewIndex = idx;
			uViewStride = stride;
			return;
		}
		if(uViewsMap == null)
			uViewsMap = new Map();
		uViewsMap.set(stride, idx);
	}

	public function disposeViews(heap:BlockHeap) {
		if(cViewIndex != -1) {
			heap.disposeIndex(cViewIndex);
			cViewIndex = -1;
		}
		if(sViewIndex >= 0) {
			heap.disposeIndex(sViewIndex);
			sViewIndex = -1;
			sViewStride = -1;
		}
		if(sViewsMap != null) {
			for(v in sViewsMap)
				heap.disposeIndex(v);
			sViewsMap = null;
		}
		if(uViewIndex >= 0) {
			heap.disposeIndex(uViewIndex);
			uViewIndex = -1;
			uViewStride = -1;
		}
		if(uViewsMap != null) {
			for(v in uViewsMap)
				heap.disposeIndex(v);
			uViewsMap = null;
		}
	}
}
#end
