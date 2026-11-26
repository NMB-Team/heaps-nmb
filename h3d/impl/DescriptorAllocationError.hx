package h3d.impl;

class DescriptorAllocationError extends haxe.Exception {
	public final recoverable : Bool;

	public function new(message : String, recoverable : Bool, ?previous : haxe.Exception) {
		this.recoverable = recoverable;
		super(message, previous);
	}
}
