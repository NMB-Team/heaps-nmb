class EventTimestamp extends hxd.App {

	override function init() {
		#if limen
		hxd.Window.getInstance().addEventTarget(onEvent);
		hxd.Pad.wait(pad -> pad.onPadEvent = onPadEvent);
		#end
	}

	#if limen
	private function onEvent(event : hxd.Event) {
		if( event.timestamp == 0 )
			return;
		checkTimestamp(event.timestamp);
		trace('${event.kind}: timestamp=${event.timestamp}, ageNs=${limen.platform.Platform.getTimestamp() - event.timestamp}, repeat=${event.isRepeat}');
	}

	private function onPadEvent(event : hxd.Pad.PadEvent) {
		checkTimestamp(event.timestamp);
		trace('${event.kind}: timestamp=${event.timestamp}, ageNs=${limen.platform.Platform.getTimestamp() - event.timestamp}');
	}

	private function checkTimestamp(timestamp : haxe.Int64) {
		if( timestamp > limen.platform.Platform.getTimestamp() )
			throw "Native event timestamp is ahead of the SDL clock";
	}
	#end

	private static function main() {
		new EventTimestamp();
	}
}
