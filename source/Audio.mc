
class Audio extends Storable {

	hidden var d_audio;

	enum { SONG, PODCAST_EPISODE, END }		// only add types at end, as these are stored
	static private var s_types = ["song", "podcast_episode"];

	// storage for playable class
	hidden var d_storage = {
		"id" => null,
		"type" => SONG,
	};

	// refId of stored audio, without creating the full object (song + artwork),
	// use this when checking many ids, as creating all objects trips the watchdog
	static function refIdOf(id, type) {
		var storage = (type == PODCAST_EPISODE) ? EpisodeStore.get(id) : SongStore.get(id);
		if (storage == null) {
			return null;
		}
		return storage["refId"];
	}

	function initialize(id, type) {
		//if ($.debug) {
		//	System.println("Audio::initialize( id = " + id + " type = " + type + " )");
		//}

		Storable.initialize({ "id" => id, "type" => type, });

		if (type.equals(PODCAST_EPISODE)) {
			d_audio = new IEpisode(id);
		} else {
			d_audio = new ISong(id);
		}
	}
	
	// getters
	function id() {
		return d_audio.id();
	}

	function artwork() {
		return d_audio.artwork();
	}

	function title() {
		return d_audio.title();
	}

	function artist() {
		return d_audio.artist();
	}

	function time() {
		return d_audio.time();
	}

	function playback() {
		return d_audio.playback();
	}

	function setPlayback(value) {
		return d_audio.setPlayback(value);
	}
	
	function mime() {
		return d_audio.mime();
	}

	function refId() {
		return d_audio.refId();
	}
	
	function setRefId(refId) {
		return d_audio.setRefId(refId);
	}

	function type() {
		return get("type");
	}

	static function typeToString(type) {
		return s_types[type];
	}

	function metadata() {
		return d_audio.metadata();
	}
}