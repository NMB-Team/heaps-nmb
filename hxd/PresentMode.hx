package hxd;

#if limen
typedef PresentMode = limen.graphics.PresentMode;
#else
// litteraly from Limen
enum abstract PresentMode(Int) from Int to Int {
	/**
		Presents frames immediately without waiting for vertical synchronization.

		This minimizes presentation latency, but may cause visible screen tearing
		when a frame is presented while the display is in the middle of a refresh.
	**/
	public final Immediate = 0;

	/**
		Synchronizes frame presentation with the display refresh cycle.

		This prevents screen tearing by waiting for vertical synchronization before
		presenting a frame. Presentation latency may be higher than with Immediate.
	**/
	public final VSync = 1;

	/**
		Uses adaptive vertical synchronization when supported by the platform.

		Frames are synchronized with the display refresh cycle while rendering keeps
		up with the refresh rate. If a frame misses the synchronization interval,
		the platform may present it immediately to reduce stutter at the cost of
		possible screen tearing.

		Platforms that do not support adaptive synchronization may fall back to
		regular VSync.
	**/
	public final Adaptive = -1;
}
#end
