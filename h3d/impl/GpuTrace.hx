package h3d.impl;

import h3d.impl.driver.Driver;
import h3d.impl.driver.Query;
import h3d.impl.driver.QueryKind;

private class PassQuery {
	public var query : Query;
	public var name : String;
	public var frame : Int;
	public var timestamp : Float;

	public function new(query) this.query = query;
}

class GpuTrace {
	static inline var MAX_QUERIES = 128;

	var driver : Driver;
	var pending : Array<PassQuery> = [];
	var free : Array<PassQuery> = [];
	var allocated = 0;
	var supported = true;

	public function new(driver) this.driver = driver;

	public function begin(name : String, frame : Int) : PassQuery {
		if( !supported || !hxd.NMBTrace.durationAvailable() ) return null;
		var entry = free.pop();
		if( entry == null ) {
			if( allocated == MAX_QUERIES ) return null;
			try {
				var query = driver.allocQuery(QueryKind.TimeElapsed);
				if( query == null ) { supported = false; return null; }
				entry = new PassQuery(query);
				allocated++;
			} catch( e : Dynamic ) {
				supported = false;
				return null;
			}
		}
		try driver.beginQuery(entry.query) catch( e : Dynamic ) {
			free.push(entry);
			supported = false;
			return null;
		}
		entry.name = name;
		entry.frame = frame;
		// TimeElapsed supplies duration only; this is the CPU submission clock
		entry.timestamp = hxd.NMBTrace.now();
		return entry;
	}

	public function end(entry : PassQuery) {
		if( entry == null ) return;
		try {
			driver.endQuery(entry.query);
			pending.push(entry);
		} catch( e : Dynamic ) {
			free.push(entry);
			supported = false;
		}
	}

	public function poll(frame : Int) {
		if( !supported || !hxd.NMBTrace.enabled() ) return;
		var i = 0;
		while( i < pending.length ) {
			var entry = pending[i];
			if( entry.frame >= frame ) { i++; continue; }
			try {
				if( !driver.queryResultAvailable(entry.query) ) { i++; continue; }
				var duration = driver.queryResult(entry.query) / 1000.;
				if( Math.isFinite(duration) && duration >= 0 ) hxd.NMBTrace.duration("heaps.gpu", entry.name, entry.timestamp, duration);
				pending.splice(i, 1);
				free.push(entry);
			} catch( e : Dynamic ) {
				supported = false;
				return;
			}
		}
	}

	public function dispose() {
		for( entry in pending ) try driver.deleteQuery(entry.query) catch( e : Dynamic ) driver.log('GPU query cleanup failed: $e');
		for( entry in free ) try driver.deleteQuery(entry.query) catch( e : Dynamic ) driver.log('GPU query cleanup failed: $e');
		pending = [];
		free = [];
		allocated = 0;
	}
}
