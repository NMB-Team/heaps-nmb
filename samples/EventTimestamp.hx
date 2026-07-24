class EventTimestamp extends hxd.App {

	override function init() {
		#if hlsdl
		hxd.Window.getInstance().addEventTarget(onEvent);
		hxd.Pad.wait(pad -> pad.onPadEvent = onPadEvent);
		#end
	}

	#if hlsdl
	private function onEvent(event : hxd.Event) {
		if( event.timestamp == 0. )
			return;
		checkTimestamp(event.timestamp);
		trace('${event.kind}: timestamp=${event.timestamp}, age=${sdl.Sdl.getTime() - event.timestamp}, repeat=${event.isRepeat}');
	}

	private function onPadEvent(event : hxd.Pad.PadEvent) {
		checkTimestamp(event.timestamp);
		trace('${event.kind}: timestamp=${event.timestamp}, age=${sdl.Sdl.getTime() - event.timestamp}');
	}

	private function checkTimestamp(timestamp : Float) {
		if( timestamp > sdl.Sdl.getTime() + 0.001 )
			throw "Native event timestamp is ahead of the SDL clock";
	}
	#end

	private static function main() {
		new EventTimestamp();
	}
}
