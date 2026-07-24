package h3d.impl.driver;

enum QueryKind {
	/**
		The GPU timestamp in nanoseconds when `endQuery` is performed.
	**/
	TimeStamp;
	/**
		The number of samples that pass the depth buffer between `beginQuery` and `endQuery`.
	**/
	Samples;
	/**
		The GPU elapsed time in nanoseconds between `beginQuery` and `endQuery`.
	**/
	TimeElapsed;
}
