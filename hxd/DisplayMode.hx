package hxd;

#if limen
typedef DisplayMode = limen.platform.window.WindowMode;
#else
enum DisplayMode {
	Windowed; 				// 0
	ExclusiveFullscreen;	// 1
	WindowedFullscreen; 	// 2
	DesktopFullscreen; 		// 3
	#if js
	FullscreenResize; 		// 4 - web only
	#end
}
#end