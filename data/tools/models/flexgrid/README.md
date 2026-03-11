# FlexGrid

Semi-novel very experimental backing spatial data structure / spatial data store.

Solves practically the problem of a reasonably efficient spatial data structure + binary format for `mapview`, and experimentally is of interest / utility for significantly speeding up data processing O(N^2) lookup queries
once / if implemented.

Core idea: extremely simple, highly scalable (theoretically) geohashing on packed `u64` (level,x,y) keys from any point or AABB (and thus any geometry) data. 

Sparse data structure, ie hashmap of CellKeys => Cells.

level is determined / must fit within delta between min,max bounds.

ie is `let sz = bounds.size; let maxExent = max(sz.x, sz.y)`

cell bucket is set by the minimum value. (`bounds.minv`, or `point`)

cell bounds have an AABB and can (as per spec, ish) grow up to either
`2` or `4` times the normally allowable cell size. (trivially solves overlap issue on spatial tree structures; cells are automatically multilevel and follow a "scales" pattern)

due to access patterns spatial queries require accesssing multiple cells sequentially and at different levels. `FlexIndex` exists (in spec) to solve this and should be very efficient. albeit unimplemented here (WIP)

cells are subdivided global coordinates (in `PolarNorm` space, ie `[0,1]`), subdivided `4^k` times at layer `k >= 0`. The root level `0` should be a single cell.

Semi-solves (well ish) problem of at poles coordiates courtesy of the fact that geometry (albeit not points!) will automatically filter up to an appropirate subdivision level. ie geometry at poles should still work (well ish), at higher overlaps, and will scale over the pole if needed via cell extents. At erm one pole anyways. In general this hasn't been tested but is an "interesting" (and yes slightly pathological) approach.

An additional fix for points would be to do a projection at (x,y) to meters and use a meter / size based

Thanks to `tools/models/geometry.unit.d` if fully implemented this should be quite trivial.

(ie. `bounds.size.to!Meters(projectionSpace)`. or something)

## File Structure

In need of cleanup.

* `common.d`: common defns incl setting / defining (for everything else using flexgrid!!) the geometry coordinate space used
* `key.d`: implements the `FlexCellKey` structure + lookups
* `grid.d`: needs to be refaactored. includes `FlexCell` and `FlexGrid` implementations
* `flexobject.d`: typed object data (transformed from OMF "props" (ie properties)), plus anything else
* `flexgeo/`: custom binary geometry format. also experimental. clever/too clever. technically allows storing efficiently packed arbitrarily complex r-trees and data structures of ANY geometry combination, with AABB "tagging" and attaching / linking to cell-local UUIDs. in essentially two single `uint[]` and `double[]` arrays that can be just packed sequentially in memory and that basically don't (see `FLX1`) need to be deserialized or parsed before use.
* `serio.d`: binary serialization / deserialization using `msgpack`. `flexgeo` serialization is custom using one of two interchange formats and is handled by `flexgeo/serio.d`
* `flexstore.d`: data backend, loading/storing and streaming (TBD) to a databackend, ie (KISS) sqlite3.

Note that the data storage format (ie flexgrid) is *extremely* simple, and could be streamed to/from memory with fixed memory pools and a LRU cache. (albeit iff mind you you don't particularly mind blowing up to
gigabytes+ of persistently cached map data in eg. a map viewer, data
processing pipeline, etc)

```sql
CREATE TABLE IF NOT EXISTS flexgrid (
    key     INTEGER,
    layer   INTEGER,
    level   INTEGER,    -- redundant, packed in key
    x       INTEGER,    -- redundant, packed in key
    y       INTEGER,    -- redundant, packed in key
    data    BLOB,
    PRIMARY KEY(key, layer)
);
CREATE TABLE IF NOT EXISTS layers (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    name    TEXT
);
```

Note that flexgrid in a nutshell is just an extremely simple hierarchical arbitrarily (ish) large scene graph format, that
is technically utterly agnostic to coordinate projection
space and could work happily with both polar and linear
coordinate systems with some caveats.

Effective limits on it are that the maximum subdivision level
with full use of `u64`s (and fixing the issue that sqlite is
*signed integer based* and doesn't particularly like / handle
well signed integer behavior w/r the D lib I'm using), is 
`u4,u30,u30` = `4^15` subdiv levels `<=>` `2^30` bits of subdivision.
ie. 15 (or 16 depending on how you're counting) layers max.

Past that point you're back in (totally nonstandard) UUID territory,
with to eg. `u48 x,y`, `u6 level`, `u26 whatever` layout. Which would
actually map very nicely to the idea of having `u26` (or `u22`, going full bore and actually straight up implementing a custom type-8 UUID), bits for layer ids. ie 4M (or 64M!) max defined data layers. And `u48` = 24 levels max (4^24 max) subdivisions over any coordinate space.
