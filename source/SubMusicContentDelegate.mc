using Toybox.Media;
using SubMusic;
using SubMusic.ScrobbleStore;

// This class handles events from the system's media
// player. getContentIterator() returns an iterator
// that iterates over the songs configured to play.
class SubMusicContentDelegate extends Media.ContentDelegate {

	private var d_iterator;
	
	enum { START, SKIP_NEXT, SKIP_PREVIOUS, PLAYBACK_NOTIFY, COMPLETE, STOP, PAUSE, RESUME, }
	private var d_events = ["Start", "Skip Next", "Skip Previous", "Playback Notify", "Complete", "Stop", "Pause", "Resume"];

    function initialize() {
        ContentDelegate.initialize();

        resetContentIterator();
    }

    // Returns an iterator that is used by the system to play songs.
    // A custom iterator can be created that extends Media.ContentIterator
    // to return only songs chosen in the sync configuration mode.
    function getContentIterator() {
        return d_iterator;
    }

    // Respond to a user ad click
    function onAdAction(adContext) {
    	if ($.debug) {
    		System.println("Ad Action: " + getSongName(adContext));
    	}
    }
    
    function onCustomButton(button) {
    	if ($.debug) {
    		System.println("Custom Button clicked: " + button);
    	}
    }

    // Respond to a thumbs-up action
    function onThumbsUp(contentRefId) {
    	if ($.debug) {
    		System.println("Thumbs Up: " + getSongName(contentRefId));
    	}
    }

    // Respond to a thumbs-down action
    function onThumbsDown(contentRefId) {
    	if ($.debug) {
    		System.println("Thumbs Down: " + getSongName(contentRefId));
    	}
    }

    // Respond to a command to turn shuffle on or off
    function onShuffle() {
    	d_iterator.toggleShuffle();
    }
    
    function onRepeat() {
    	if ($.debug) {
    		System.println("Repeat Mode change");
    	}
    }
    
    function resetContentIterator() {
    	d_iterator = new SubMusicContentIterator();
    	return d_iterator;
    }
    
    function onMore() {
    	if ($.debug) {
    		System.println("onMore is called");
    	}
    }
    
    function onLibrary() {
    	if ($.debug) {
    		System.println("onLibrary is called");
    	}
    }

    // Handles a notification from the system that an event has
    // been triggered for the given song
    function onSong(contentRefId, songEvent as Media.SongEvent, playbackPosition) as Void {
    	// nothing to do without content (e.g. playback started with nothing loaded)
    	if (contentRefId == null) {
    		return;
    	}
    	if ($.debug) {
    		System.println("onSong Event (" + songEvent + "): " + contentRefId + " at position " + playbackPosition);
    	}
	
		var audio = findAudioByRefId(contentRefId);
		if (audio == null) { return; }
		
		if (songEvent == START) {
			// set the artwork
			Media.setAlbumArt(audio.artwork());
			return;
		}

    	if (songEvent == PLAYBACK_NOTIFY) {
			// record a play
    		ScrobbleStore.add(new SubMusic.Scrobble({
    			"id" => audio.id(),
    		}));
    		return;
    	}
    	
    	// record time if podcast mode
		var iplayable = new SubMusic.IPlayable();
    	if (!iplayable.podcast_mode()) {
    		return;
    	}
    	
    	if ((songEvent == SKIP_NEXT)
			|| (songEvent == SKIP_PREVIOUS)
			|| (songEvent == STOP)
			|| (songEvent == PAUSE)
			|| (songEvent == COMPLETE)) {

			// record playback position
    		audio.setPlayback(playbackPosition);
    	}   		
    }

	function findAudioByRefId(refId) {
		// trick: guess id and type from playable, the event can be for the
		// current, previous or next audio (e.g. after a skip)
		var iplayable = new SubMusic.IPlayable();
		var songidx = iplayable.songidx();
		if (songidx != null) {
			var guesses = [songidx, songidx - 1, songidx + 1];
			for (var idx = 0; idx != guesses.size(); ++idx) {
				if (guesses[idx] < 0) {
					continue;
				}
				var audio = iplayable.getAudio(guesses[idx]);
				if ((audio instanceof SubMusic.Audio)
					&& (audio.refId() == refId)) {
					if ($.debug) {
						System.println("SubMusicContentDelegate::findAudioByRefId( refId: " + refId + " ) - guessed");
					}
					return audio;
				}
			}
		}
		// if trick not successful, do exhaustive search
		if ($.debug) {
			System.println("SubMusicContentDelegate::findAudioByRefId( refId: " + refId + " ) - not guessed");
		}
		var ids = [ SongStore.getIds(), EpisodeStore.getIds() ];
		for (var typ = 0; typ != Audio.END; ++typ) {
			if (ids[typ] == null) { continue; }
			for (var idx = 0; idx != ids[typ].size(); ++idx) {
				// compare the stored refId only, creating an Audio for every
				// stored song trips the watchdog on large libraries
				if (Audio.refIdOf(ids[typ][idx], typ) == refId) {
					return new Audio(ids[typ][idx], typ);
				}
			}
		}
		return null;
	}
    
    function findSongByRefId(refId) {
		var ids = SongStore.getIds();
		for (var idx = 0; idx < ids.size(); ++idx) {
			var isong = new ISong(ids[idx]);
			if (refId == isong.refId()) {
				return isong;
			}
		}
		return null;
	}
    
    function getSongName(refId) {
    	return Media.getCachedContentObj(new Media.ContentRef(refId, Media.CONTENT_TYPE_AUDIO)).getMetadata().title;
    }
}
