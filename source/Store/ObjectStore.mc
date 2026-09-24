using Toybox.Application;
using Toybox.Lang;

/*
 * Store number of items in a Dictionary by id
 * Item class should have a function id()
 * Item class should have a function toStorage()
 *
 * Items are spread over BUCKETS storage keys, since a single storage value
 * is limited in size (32 KB). Storing all items under one key limits the
 * number of songs to ~130 and makes every save rewrite all items.
 */
class ObjectStore extends Store {

	enum { BUCKETS = 8, }

	private var d_okey;
	private var d_buckets;		// array of dictionaries, item id is key

	function initialize(key) {
		Store.initialize(key, {});		// loads the legacy (single key) dictionary, if any
		d_okey = key;

		d_buckets = new [BUCKETS];
		for (var bucket = 0; bucket != BUCKETS; ++bucket) {
			var stored = Application.Storage.getValue(bucketKey(bucket));
			d_buckets[bucket] = (stored != null) ? stored : {};
		}

		// migrate the legacy dictionary into the buckets
		var legacy = Store.value();
		if (legacy.size() == 0) {
			return;
		}
		var ids = legacy.keys();
		for (var idx = 0; idx != ids.size(); ++idx) {
			d_buckets[bucketOf(ids[idx])].put(ids[idx], legacy[ids[idx]]);
		}
		for (var bucket = 0; bucket != BUCKETS; ++bucket) {
			write(bucket);
		}
		Application.Storage.deleteValue(d_okey);
		Store.setValue({});
	}

	// returns a connected item
	function get(id) {
		if (id == null)  {
			return null;
		}
		return d_buckets[bucketOf(id)].get(id);
	}

	function getIds() {
		var ret = [];
		for (var bucket = 0; bucket != BUCKETS; ++bucket) {
			ret.addAll(d_buckets[bucket].keys());
		}
		return ret;
	}

	function getValues() {
		var ret = [];
		for (var bucket = 0; bucket != BUCKETS; ++bucket) {
			ret.addAll(d_buckets[bucket].values());
		}
		return ret;
	}

	function save(item) {
		if ($.debug) {
			System.println("ObjectStore::save( item : " + item.toStorage() + " )");
		}

		// return false if failed save
		var id = item.id();
		if (id == null) {
			return false;
		}

		// save details of the item
		var bucket = bucketOf(id);
		d_buckets[bucket].put(id, item.toStorage());
		return write(bucket);
	}

	// returns true if item id entry removed from storage or is not in storage
	function remove(item) {
		if ($.debug) {
			System.println("ObjectStore::remove( " + item.toStorage() + " )");
		}

		var id = item.id();
        if (id == null)  {
			return true;
		}

		var bucket = bucketOf(id);
		d_buckets[bucket].remove(id);
		return write(bucket);
	}

	hidden function write(bucket) {
		try {
			Application.Storage.setValue(bucketKey(bucket), d_buckets[bucket]);
		} catch (exception instanceof Toybox.Lang.StorageFullException) {
			return false;
		}
		return true;
	}

	hidden function bucketKey(bucket) {
		return "os" + d_okey + "_" + bucket;
	}

	// deterministic bucket for an id, based on its last character
	hidden function bucketOf(id) {
		if (id instanceof Lang.Number) {
			return ((id % BUCKETS) + BUCKETS) % BUCKETS;
		}
		var chars = id.toString().toCharArray();
		if (chars.size() == 0) {
			return 0;
		}
		return chars[chars.size() - 1].toNumber() % BUCKETS;
	}
}
