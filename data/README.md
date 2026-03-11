# Fetched cached data + data fetching tools
## Structure (code):
* `data/tools`: 
  * D scripts to fetch and process data in geojson format from overture
  * D infrastructure (`data/tools/models`) that implements MVP infrastructure for working with geospatial map data:
    * `models.geometry`:
      * Point, Geometry, AABB data structures
      * typed unit type tagging and unit conversions 
        * `PolarDeg`: polar coordinates, degrees (-180 to +180)
        * `PolarRad`: polar coordinates, radians (unused)
        * `PolarNorm`: polar coordinates, normalized (-180 to +180) => (0 to 360) => (0 to 1)
        * `Meters`: linear units, meters. Used (TBD) for radial calculations etc. Used in very approximate (incorrect) form for getting an idea about bounding box sizes etc (TODO: implement that properly)
        * proper spatial projection and eg. webmercator TBD
      * (PolarDeg, PolarRad, PolarNorm, Meters) 
    * `models.geojson`: MVP geojson implementation (using `std.json`). uses `models.geometry`
    * `models.omf`: decodes OMF (overture maps foundation) properly typed data from OMF fetches (in geojson) format. MVP
    * `models.flexgrid`: partial in progress flexgrid implementation
      * GOAL: MVP implementation, usable for
        * map visualization: `../mapview`, `models.flexgrid_plugins.flexgrid_viewer`
        * data processing, ie running radial find all objects of type T1 within radius of all objects of type T2
        * data layers (=> data processing pipelines)
        * `FlexGeo` (flexgrid geometry) spec. in progress, needs MVP
          * current impl (in progress) probably overkill, just need MVP
          * *just* needs to transform geometry from geojson => our intermediate (`models.geometry`) => flexgeo
          * needs to serialize to/from binary using `msgpack` (or even simpler!)
          * very simple awesome (albeit overkill) custom geometry interchange format
        * serialization + data storage:
          * cells have:
            * id map (maps UUIDs <=> local flex cells)
            * geometry (hashtable of local cell id => flexgeo)
            * point data (hashtable of local cell id => Point)
            * object data (hashtable of local cell id => FlexObject derived classes)
          * interchange: dump cell data to / read from binary blobs using `msgpack`
            * (and potentially custom / super simple flexgeo + point geometry)
          * store / load cell binary blobs into SQLite
          * enables (potentially) using LRU w/ lazy async loading (and eviction) of cell data for mapviewer and data processing pipelines
            * DO NOT NEED LRU. MVP: just load data lazily, be able to store / write out (overkill: transactions, easy: save() method or whatever) from memory
      * status: incomplete / in progress, needs MVP

Refactor needed? possibly but not necessarily. in progress.

## structure: data
* data loaded in using `fetch_omf.d` to `data/omf/<location>/<themes>.geojson`
  * location = bounding box. currently hardcoded
    * bounding box dumped out to `.bounds.txt`
* summarization scripts write to `data/summary`, `data/place_summary` etc
  * text dumps to just explore the data and collect statistics etc
* `../dump.txt` is produced by running `dump_json.d > dump.txt` from the root directory
  * just the geojson file dumped out as an easy to read whitespace oriented text dump, using our intermediate data formats

TODO:
* sql cache in eg. `data/flexgrid/<name>/grid.db`
* process script to read geojson data and write that into a `grid.db` sqlite file
* sqlite table to store status of data processing / loading etc
  * locations: name, coordinates (string, comma separated 4-tuple in polar degree coordinates (see .bounds.txt)), id (autoinc)
  * themes: name, id (autoinc)
  * processing table: location id, theme id, status (integer), relative source file path, SHA hash of source file contents
* pipeline processing
  * pipelines: name, id (autoinc), script file (rel path)
  * pipeline versions: id (pipeline), version (autoinc), script file hash
    * inputs: blob, msgpack encoded array of layer ids
    * outputs: blob, msgpack encoded array of layer ids
  * pipeline state:
    * id (pipeline), version id (pipeline versions)

SQLITE flexgrid format:
* layers: table of (string name, int autoinc id, string source (relpath, or null))
* cells: table of (cell id (primary, computed as per flexgrid), layer id, data id)
* data (optional): table of (data id (autoinc), data blob)

storage format:
* path (eg. `data/flexgrid/<name>/`)
  * flexgrid file: `grid.db`
  * pipelines file / status: `pipelines.db`
