# Known Issues

## geometry/algorithms.d

### [FIXED] `withinRadiusOf(AABB, ...)` referenced non-existent `bounds.x`/`bounds.y`
Used `bounds.x` / `bounds.y` (no such property on `TAABB`). Fixed with `clamp(point.x, bounds.minv.x, bounds.maxv.x)`.

### [FIXED] `withinRadiusOf(TPoint, ...)` comparison inverted and `dy` assigned twice
`r2 <= rx + ry` should be `dx*dx + dy*dy <= r2`; `dy = U1.to!(U2)(dy = ...)` was self-referential. Fixed.

### [FIXED] `withinRadiusOf(Prim, ...)` — `Prim` not in scope in `algorithms.d`
Removed; functionality inlined in `iteration.d`'s `WithinRadiusOf.matches(Prim)`.

## flexgrid.flexgeo.iteration

## flexgeo/conv.d

### [BUG] `boundsIndex` is an entity index used as a points index
`createBounds()` returns `g.entities.length - 1` (the entity index of the new Bounds entity),
which `begin()` stores in `EntityBuildInfo.boundsIndex`. The `end()` fix then patches
`g.points[tos.boundsIndex]`. This is only correct when entity count and points count happen to
be equal, which is true for the very first bounds entity but diverges as soon as any actual ring
points are written between `createBounds()` calls.

Example — polygon with outer ring (3 pts) + inner ring (3 pts):
- ring0's bounds placeholder: entity index 2, points index 2 → patch lands correctly
- ring1's bounds placeholder: entity index 4, points index 7 → patch writes to g.points[4,5]
  which are ring0's first actual points, not the placeholders at [7,8]

**Fix:** `createBounds()` should return the points index (`g.points.length - 2` after appending
the two placeholders), not the entity index. `EntityBuildInfo.boundsIndex` stores this points
index and `end()` already uses it correctly otherwise.

### [BUG] Ring entity `payload` is never set, so ring points are invisible to the iterator
`end(false)` skips writing `payload` entirely. But for data-type entities (RingOuter, RingInner),
the iterator in `matchesAnyPolygon` uses `child.payload` as the point count:
```d
auto ringPoints = geo[0..child.payload]; geo = geo[child.payload..$];
```
With payload=0, every ring appears empty and `geo` is never advanced, corrupting all subsequent
geometry iteration for that cell.

**Fix:** `EntityBuildInfo` needs a `pointsStart` field set at `begin()` time
(`cast(uint)g.points.length`). For ring/data-type entities, `end()` should write
`payload = cast(uint)(g.points.length - tos.pointsStart)` regardless of the
`writeChildOffsetToPayload` flag (which controls the entity-count payload used by containers).
These are two separate things that need separate handling.

## flexgeo/iteration.d

Note: most of these are in code paths that are not yet exercised (templated / uncompiled).

### [BUG] `matchVisitImpl` references `g.geometry` — field does not exist
```d
auto geo = g.geometry;  // FlexGeo has `points`, not `geometry`
```
Should be `g.points`.

### [BUG] `matchVisitImpl` references `GeoType.Index` — variant does not exist in enum
```d
case GeoType.Index: ...  // enum has GeoType.Id
```
Should be `GeoType.Id`.

### [BUG] `matchVisitImpl` uses local `bounds` (always null) instead of `visitState.bounds`
```d
if (visitState.bounds) {
    auto bbox = AABB(bounds[0], bounds[1]);  // `bounds` is the null local, not visitState.bounds
```
Should be `AABB(visitState.bounds[0], visitState.bounds[1])`.

### [BUG] `matchesAnyPolygon` — Polygon case incorrectly advances `geo` by entity count
```d
case GeoType.Polygon: {
    auto polyPoints = geo[0..child.payload]; geo = geo[child.payload..$];  // payload = entity count
    ...
    if (matchesAnyPolygon(query, childEnts, geo)) { ... }  // also advances geo via ref
```
`child.payload` for a Polygon is its entity child count, not a point count. Slicing and advancing
`geo` here is wrong; the recursive call handles geo advancement through the `ref` parameter.
The `polyPoints` / `geo = geo[child.payload..$]` lines should be removed for the Polygon case.

### [BUG] `visitMatchingAll` uses wrong `MatchType`
```d
bool visitMatchingAll (...) {
    return matchVisitImpl!(TQuery, MatchType.VisitAnyMatching, v);  // should be VisitAllMatching
```

### [BUG] `visitMatchingAll` / `visitMatchingAny` missing template arguments to `matchVisitImpl`
Both call `matchVisitImpl!(TQuery, MatchType.xxx, v)` where `v` is a value not a type. The
third template parameter is `TVisitor`. The value `v` should be passed as a runtime argument,
not a template argument. Compare correct pattern:
```d
matchVisitImpl!(TQuery, MatchType.VisitAllMatching, TVisitor)(query, g, v)
```

## flexgrid/flexstore.d

### [BUG] `import core.sync: Mutex` — wrong module path
Should be `import core.sync.mutex : Mutex`.

### [BUG] `loadLayers` never populates the layers map
Iterates rows and asserts but never inserts into `layers`:
```d
// missing: layers[name] = cast(uint) id;
```
`grid.loadLayers(layers)` is always called with an empty map.

### [BUG] `preloadGrid` queries wrong table
Queries `layers` instead of `flexgrid`, so `key`/`layer` column peeks are reading string data.

### [BUG] `saveGrid` key and layer bindings are swapped
```d
stmt.bind(1, layer.id);                        // position 1 = :key
stmt.bind(2, cell.cellKey.value.reinterpLong); // position 2 = :layer
```
`layer.id` goes in as the key and the cell key goes in as the layer id.

### [BUG] `saveGrid` uses `.parallel` with a shared `Statement` — data race
`stmt` is declared outside the parallel foreach. SQLite `Statement` is not thread-safe.
Move `stmt` inside the outer foreach, or drop `.parallel`.

### [BUG] `lazyPreloadGrid` sets `loadedGrid = true` before loading completes
The flag is set inside `synchronized(mutex)` but the actual load calls happen after the
synchronized block exits. A concurrent caller sees the flag and returns before data is ready.
