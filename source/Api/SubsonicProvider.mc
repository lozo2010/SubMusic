using Toybox.Communications;
using Toybox.Lang;
using Toybox.System;
using SubMusic.Utils;

class SubsonicProvider {
	
	private var d_api;

    // callbacks
    private var d_callback;  // callback for finished request
    private var d_fallback;  // fallback for failed request
    private var d_progress;  // intermediate callback to update request progress
	
	private var d_range;		// stores range for ranged requests

	// Navidrome native api, used to fetch playlist songs in pages
	// (Subsonic getPlaylist cannot be paged and fails with -402 on larger playlists)
	enum { ND_MAX_LIMIT = 20, }
	private var d_ndSupported = null;	// null = unknown, true/false after first try
	private var d_ndActive = false;		// true while a native request is running
	private var d_ndRetried = false;	// true if token was already refreshed
	private var d_ndId;
	private var d_ndStart;
	private var d_ndLimit;
	private var d_ndSongs;

	private var d_id;			// playlist id for getPlaylist

	function initialize(settings) {
		d_api = new SubsonicAPI(
			settings, 
			self.method(:onProgress), 
			self.method(:onError)
		);
	}
	
	function onSettingsChanged(settings) {
		if ($.debug) {
			System.println("SubsonicProvider::onSettingsChanged");
		}
		
		d_api.update(settings);
		d_ndSupported = null;		// server may have changed
	}
	
	// functions:
	// - ping				returns an object with server version
	// - recordPlay			submit a play
	// - getAllPlaylists	returns an array of all playlists available for Ampache user
	// - getPlaylist		returns an array of one playlist object for id
	// - getPlaylistSongs	returns an array of songs on the playlist with id
	// - getRefId			returns a refId for a song by id (this downloads the song)
	// - getArtwork			returns a BitmapResource for a song id
	// - getAllPodcasts		returns an array of all podcasts available for Ampache user
	// - getPodcast			returns an array of one podcast object for id
	// - getEpisodes		returns an array of episodes in the podcast with id
	//
	// to be added in the future:
	// - getUpdatedPlaylists - returns array of all playlists updated since Moment
	
	/**
	 * ping
	 *
	 * returns an object with server version
	 */
	function ping(callback) {
		d_callback = callback;
		
		d_api.ping(self.method(:onPing));
	}
	
	function recordPlay(id, time, callback) {
		d_callback = callback;
		
		var params = {
			"id" => id,
			"time" => time,
		};
		d_api.scrobble(self.method(:onRecordPlay), params);		// scrobble is only way to submit a play
	}

	/**
	 * getAllPlaylists
	 *
	 * returns array of all playlists available for Ampache user
	 */
	function getAllPlaylists(callback) {
		d_callback = callback;
		d_api.getPlaylists(self.method(:onGetAllPlaylists));
	}

	/**
	 * getPlaylist
	 *
	 * returns an array of one playlist object for id
	 */
	function getPlaylist(id, callback) {
		d_callback = callback;
		d_id = id;

		// getPlaylists does not include the songs, so the response stays small
		d_api.getPlaylists(self.method(:onGetPlaylist));
	}

	/**
	 * getPlaylistSongs
	 *
	 * returns an array of songs on the playlist with id
	 */
	function getPlaylistSongs(id, callback) {
		d_callback = callback;

		if (d_ndSupported != false) {
			d_ndId = id;
			d_ndStart = 0;
			d_ndLimit = ND_MAX_LIMIT;
			d_ndSongs = [];
			d_ndRetried = false;
			d_ndActive = true;
			ndNext();
			return;
		}

		getPlaylistSongsSubsonic(id);
	}

	function getPlaylistSongsSubsonic(id) {
		var params = {
			"id" => id,
		};

		d_api.getPlaylist(self.method(:onGetPlaylistSongs), params);
	}

	// request the next page of songs, login first if needed
	function ndNext() {
		if (d_api.ndToken() == null) {
			d_api.ndLogin(self.method(:onNdLogin));
			return;
		}
		d_api.ndPlaylistTracks(self.method(:onNdPlaylistTracks), d_ndId, d_ndStart, d_ndStart + d_ndLimit);
	}

	function onNdLogin(token) {
		d_ndSupported = true;
		ndNext();
	}

	function onNdPlaylistTracks(response) {
		if ($.debug) {
			System.println("SubsonicProvider::onNdPlaylistTracks( received: " + response.size() + ", total: " + d_ndSongs.size() + ")");
		}

		for (var idx = 0; idx < response.size(); ++idx) {
			var track = response[idx];

			var time = track["duration"];
			if (time == null) {
				time = 0;
			}
			// album art is shared by all songs of an album, less downloads
			var art_id = track["mediaFileId"];
			if (track["albumId"] != null) {
				art_id = "al-" + track["albumId"];
			}
			d_ndSongs.add(new Song({
				"id" => track["mediaFileId"],
				"title" => track["title"],
				"artist" => track["artist"],
				"time" => time.toNumber(),
				"mime" => suffixToMime(track["suffix"]),
				"art_id" => art_id,
			}));
		}

		// full page received, more songs may be available
		if (response.size() >= d_ndLimit) {
			d_ndStart += response.size();
			ndNext();
			return;
		}

		d_ndActive = false;
		var songs = d_ndSongs;
		d_ndSongs = null;
		d_callback.invoke(songs);
	}

	// handle errors of the native api, returns true if handled
	function onNdError(error) {
		// response too large, retry with smaller pages
		if ((error instanceof SubMusic.GarminSdkError)
			&& (error.respCode() == Communications.NETWORK_RESPONSE_TOO_LARGE)
			&& (d_ndLimit > 1)) {
			d_ndLimit = (d_ndLimit / 2).toNumber();
			if ($.debug) {
				System.println("SubsonicProvider native limit was lowered to " + d_ndLimit);
			}
			ndNext();
			return true;
		}

		// token expired, login once more
		if ((d_ndSupported == true)
			&& !d_ndRetried
			&& (error instanceof SubMusic.HttpError)
			&& (error.http_type() == SubMusic.HttpError.UNAUTHORIZED)) {
			d_ndRetried = true;
			d_api.ndClearToken();
			ndNext();
			return true;
		}

		d_ndActive = false;
		d_ndSongs = null;

		// native api not available (not Navidrome), fall back to Subsonic
		if (d_ndSupported != true) {
			if ($.debug) {
				System.println("SubsonicProvider native api not available: " + error.toString());
			}
			d_ndSupported = false;
			getPlaylistSongsSubsonic(d_ndId);
			return true;
		}
		return false;
	}

	static function suffixToMime(suffix) {
		if (!(suffix instanceof Lang.String)) {
			return null;
		}
		suffix = suffix.toLower();
		if (suffix.equals("mp3")) {
			return "audio/mpeg";
		}
		if (suffix.equals("m4a") || suffix.equals("mp4")) {
			return "audio/mp4";
		}
		if (suffix.equals("aac")) {
			return "audio/aac";
		}
		if (suffix.equals("wav")) {
			return "audio/wav";
		}
		return null;	// unsupported, will be transcoded to mp3
	}

	/**
	 * getRefId
	 *
	 *  returns a refId for a song by id (this downloads the song)
	 */	
	function getRefId(id, mime, type, callback) {
		d_callback = callback;

		var encoding = SubMusic.Utils.mimeToEncoding(mime);
		var format = "mp3";
		if (encoding == Media.ENCODING_INVALID) {
			// default to mp3 transcoding
			encoding = Media.ENCODING_MP3;
		} else {
			// if mime is supported, request raw
			format = "raw";
		}
		var params = {
			"id" => id,
			"format" => format,
		};
		d_api.stream(self.method(:onStream), params, encoding);
	}

	/**
	 * getArtwork
	 *
	 *  returns artwork for an object by id, type is not used here
	 */	
	function getArtwork(id, type, callback) {
		d_callback = callback;

		var params = {
			"id" => id,
		};
		d_api.getCoverArt(self.method(:onGetCoverArt), params);
	}

	/**
	 * getAllPodcasts
	 *
	 * returns array of all podcasts available for Subsonic user
	 */
	function getAllPodcasts(callback) {
		d_callback = callback;

		var params = {
			// id left blank to receive all
			"includeEpisodes" => "false",
		};
		d_api.getPodcasts(self.method(:onGetPodcasts), params);
	}

	/**
	 * getPodcast
	 *
	 * returns array of all podcasts available for Subsonic user
	 */
	function getPodcast(id, callback) {
		d_callback = callback;

		var params = {
			"id" => id,
			"includeEpisodes" => "false",
		};
		d_api.getPodcasts(self.method(:onGetPodcasts), params);
	}

	/**
	 * getEpisodes
	 *
	 * returns array of all episodes available for Subsonic user
	 */
	function getEpisodes(id, range, callback) {
		d_callback = callback;

		d_range = range;	// only used to slice response
		
		var params = {
			"id" => id,
			// includeEpisodes is true by default
		};
		d_api.getPodcasts(self.method(:onGetEpisodes), params);
	}
	
	function onPing(response) {
		if ($.debug) {
			System.println("SubsonicProvider::onPing( response = " + response + ")");
		}
		
		
		d_callback.invoke(response);
	}
	
	function onRecordPlay(response) {
		if ($.debug) {
			System.println("SubsonicProvider::onRecordPlay( response = " + response + ")");
		}
		
		d_callback.invoke(response); // expected empty element
	}

	function onGetAllPlaylists(response) {
		if ($.debug) {
			System.println("SubsonicProvider::onGetAllPlaylists( response = " + response + ")");
		}
		
		// response should be array, and have length
		if (!(response instanceof Lang.Array)
			|| (response.size() == 0)) {
			d_callback.invoke([]);
			return;
		}
		
		// construct the standard array of playlist objects
		var playlists = [];
		
		// construct the playlist instance
		for (var idx = 0; idx < response.size(); ++idx) {
			var playlist = response[idx];

			var songCount = playlist["songCount"];
			if (songCount == null) {
				songCount = 0;		// assume 0 if not defined
			}
			
			playlists.add(new Playlist({
				"id" => playlist["id"],
				"name" => playlist["name"],
				"songCount" => songCount.toNumber(),
				"remote" => true,
			}));
		}
		d_callback.invoke(playlists);
	}

	function onGetPodcasts(response) {
		if ($.debug) {
			System.println("SubsonicProvider::onGetPodcasts( response = " + response + ")");
		}
		
		// response should be array, and have length
		if (!(response instanceof Lang.Array)
			|| (response.size() == 0)) {
			d_callback.invoke([]);
			return;
		}
		
		// construct the standard array of podcast objects
		var podcasts = [];
		
		// construct the podcast instances
		for (var idx = 0; idx < response.size(); ++idx) {
			var podcast = response[idx];
			podcasts.add(new Podcast({
				"id" => podcast["id"],
				"name" => podcast["title"],
				"description" => podcast["description"],
				"copyright" => podcast["copyright"],
				"remote" => true,
				"art_id" => podcast["coverArt"],
			}));
		}
		d_callback.invoke(podcasts);
	}

	function onGetEpisodes(response) {
		if ($.debug) {
			System.println("SubsonicProvider::onGetEpisodes( response = " + response + ")");
		}
		
		// assume id ensures first item is needed
		if ( (response.size() == 0) 
			|| (response[0] == null)
			|| (response[0]["episode"] == null)) {
			d_callback.invoke([]);
			return;
		}
		
		response = response[0]["episode"];

		// response should be array, and have length
		if (!(response instanceof Lang.Array)
			|| (response.size() == 0)) {
			d_callback.invoke([]);
			return;
		}

		// construct the standard array of song objects
		var episodes = [];

		var start = d_range[0];
		var end = d_range[1];
		if (response.size() < end) {
			end = response.size();
		}
		
		// construct the song instances array
		for (var idx = start; idx != end; ++idx) {
			var episode = response[idx];

			var time = episode["duration"];
			if (time == null) {
				time = 0;
			}
			episodes.add(new Episode({
				"id" => episode["streamId"],
				"title" => episode["title"],
				"time" => time.toNumber(),
				"mime" => episode["contentType"],
				"art_id" => episode["coverArt"],
			}));
		}
		
		d_callback.invoke(episodes);
	}

	function onGetPlaylist(response) {
		if ($.debug) {
			System.println("SubsonicProvider::onGetPlaylist( response = " + response + ")");
		}
		
		// response is the array of all playlists, find the requested one
		if (!(response instanceof Lang.Array)) {
			d_callback.invoke([]);
			return;
		}
		for (var idx = 0; idx < response.size(); ++idx) {
			var playlist = response[idx];
			if (!d_id.toString().equals(playlist["id"].toString())) {
				continue;
			}

			var songCount = playlist["songCount"];
			if (songCount == null) {
				songCount = 0;		// assume 0 if not defined
			}

			d_callback.invoke([new Playlist({
					"id" => playlist["id"],
					"name" => playlist["name"],
					"songCount" => songCount.toNumber(),
					"remote" => true,
			})]);
			return;
		}
		d_callback.invoke([]);		// not found on server
	}

	function onGetPlaylistSongs(response) {
		if ($.debug) {
			System.println("SubsonicProvider::onGetPlaylistSongs( response = " + response + ")");
		}
		
		response = response["entry"];

		// response should be array, and have length
		if (!(response instanceof Lang.Array)
			|| (response.size() == 0)) {
			d_callback.invoke([]);
			return;
		}

		// construct the standard array of song objects
		var songs = [];
		
		// construct the song instances array
		for (var idx = 0; idx < response.size(); ++idx) {
			var song = response[idx];

			var time = song["duration"];
			if (time == null) {
				time = 0;
			}
			songs.add(new Song({
				"id" => song["id"],
				"title" => song["title"],
				"artist" => song["artist"],
				"time" => time.toNumber(),
				"mime" => song["contentType"],
				"art_id" => song["coverArt"],
			}));
		}
		
		d_callback.invoke(songs);
	}

	function onStream(contentRef) {
		d_callback.invoke(contentRef.getId());
	}

	function onGetCoverArt(artwork) {
		d_callback.invoke(artwork);
	}
	
	function onError(error) {
		if (d_ndActive && onNdError(error)) {
			return;
		}
		d_fallback.invoke(error);
	}

	function onProgress(progress) {
		d_progress.invoke(progress);
	}
    
    function setFallback(fallback) {
    	d_fallback = fallback;
    }

	function setProgressCallback(progress) {
		d_progress = progress;
	}
}