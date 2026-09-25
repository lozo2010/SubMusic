class AudioSync extends Deferrable {

	private var d_provider = SubMusic.Provider.get();
	private var d_audio = null;		// front of the todos
	
	private var d_failed = [];		// array of all failed
	
	private var f_progress; 		// callback on progress
	
	// store sync size
	private var d_todo = [];		// array of [id, type] pairs, the Audio object is only created
									// for the front item, so large syncs do not run out of memory
	private var d_todo_total;		// the number of items that had to be synced

	function initialize(progress, done, fail) {
		if ($.debug) {
			System.println("AudioSync::initialize()");
		}
		Deferrable.initialize(method(:sync), done, fail);		// make sync the deferred task
		
		f_progress = progress;
		
        d_provider.setFallback(method(:onError));
		d_provider.setProgressCallback(method(:onProgress));

		// first delete the todeletes
		var ids = SongStore.getDeletes();
		for (var idx = 0; idx < ids.size(); ++idx) {
			var id = ids[idx];
			var isong = new ISong(id);
			isong.remove();					// remove from Store
		}
		
		// now get the todos from songs and episodes
		var types = [ Audio.SONG, Audio.PODCAST_EPISODE];
		ids = [ SongStore.getIds(), EpisodeStore.getIds() ];
		for (var typ = 0; typ != Audio.END; ++typ) {
			for (var idx = 0; idx != ids[typ].size(); ++idx) {
				// only add to todo if not yet stored
				if (Audio.refIdOf(ids[typ][idx], typ) == null) {
					d_todo.add([ids[typ][idx], typ]);
				}
			}
		}
		d_todo_total = d_todo.size();
	}
	
	function sync() {
		// if songs all finished, complete this task
		if (d_todo.size() == 0) {
	   		return Deferrable.complete();				// set complete
		}

		// update progress
		f_progress.invoke(progress());
		
		// start download
		d_audio = new Audio(d_todo[0][0], d_todo[0][1]);
		d_provider.getRefId(d_audio.id(), d_audio.mime(), d_audio.type(), method(:onDownloaded));
		return Deferrable.defer();
	}

	function progress() {
		// determine what is left to do
		var todo = 0;
		if (d_todo != null) { todo = d_todo.size(); }
		
		var done = d_todo_total - todo;
		var progress = (100 * done) / d_todo_total.toFloat();
		return progress;
	}

	// handle callback on intermediate progress
	function onProgress(progress) {
		if ($.debug) {
			System.println("AudioSync::onProgress( progress: " + progress + " )");
		}
		progress /= d_todo_total.toFloat();
		f_progress.invoke(progress() + progress);
	}
	
    // Callback for when a song is downloaded
	function onDownloaded(refId) {
		// update refId
		d_audio.setRefId(refId);

		// continue to next song
		next();
	
		sync();
	}
    
    function onError(error) {
    	if ($.debug) {
    		System.println("AudioSync::onError(" + error.shortString() + " : " + error.toString() + ")");
    	}

    	// indicate failed sync
//   	d_playlist.setError(error); TODO
    	// check if song in progress
		if (d_audio == null) {
			Deferrable.cancel(error);
			return;
		}
		// record the cause of failure
//	    	d_todo[0].setError(error);				TODO
		
		d_failed.add(d_todo[0][0]);

		// remove first element from todo list
		next();

		sync();
		return;
    }

	// drop the front of the todos
	function next() {
		d_audio = null;
		d_todo = d_todo.slice(1, null);
	}
}