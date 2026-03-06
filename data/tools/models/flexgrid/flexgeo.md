# FlexGeo: Binary Geometry Format Spec

**Status:** v0.1 MVP spec

---

## Overview

FlexGeo is a compact binary geometry format for storing geospatial primitives
within FlexGrid cells. Each geometry blob is two parallel flat arrays:

```
index : uint[]    — packed Index entries describing structure
data  : double[]  — flat coordinate values (x, y interleaved)
```

Serialized to/from binary using msgpack as a 2-element array `[index, data]`.

---

## Index Entry (packed u32)

```
bits [3:0]   type       GeoType  (4 bits)
bits [5:4]   coordType  CoordType (2 bits)
bits [31:6]  count      uint (26 bits)
```

---

## GeoType Tags

| Tag          | Value | `count` meaning              | data consumed            |
|--------------|-------|------------------------------|--------------------------|
| None         | 0     | —                            | 0                        |
| Bounds       | 1     | 0 (ignored)                  | 4 doubles: minx,miny,maxx,maxy |
| Id           | 2     | local cell object id         | 0                        |
| Point        | 3     | N points                     | N×2 doubles (x,y pairs) |
| RingOuter    | 4     | N following index entries    | 0                        |
| RingInner    | 5     | N following index entries    | 0                        |
| Polygon      | 6     | N following index entries    | 0                        |
| MultiPolygon | 7     | N following index entries    | 0                        |
| Line         | 8     | N following index entries    | 0                        |
| LineString   | 9     | N following index entries    | 0                        |
| GeoObject    | 0xA   | N following index entries    | 0                        |

Container entries (RingOuter..GeoObject) set `count` to the total number of
index entries that follow (all descendants, not just immediate children).
This makes forward-skipping O(1) — just add `count+1` to the index cursor.

---

## CoordType Tags

| Tag         | Value | Unit              |
|-------------|-------|-------------------|
| PolarDeg    | 0     | degrees (−180…+180) |
| PolarNorm   | 1     | normalized (0…1)  |
| PolarRad    | 2     | radians           |
| LocalMeters | 3     | cell-local meters |

`coordType` is meaningful on `Bounds` and `Point` entries; ignored on containers.

---

## Layout Rules & Examples

### Point
```
[Point(ct, N)]  followed by N×2 doubles in data
```

### GeoObject (geometry with a local id)
```
[GeoObject(count=N), Id(id), [Bounds?], <geometry index entries...>]
```

### Polygon (outer ring + optional inner rings)
```
[Polygon(count=N), [Bounds?],
    RingOuter(count=M), Point(ct, n), ...
    RingInner(count=K), Point(ct, m), ...
    ...]
```

### MultiPolygon
```
[MultiPolygon(count=N), [Bounds?],
    Polygon(count=M), ...,
    Polygon(count=K), ...,
    ...]
```

---

## Serialization

msgpack format: 2-element array `[index_as_uint_array, data_as_double_array]`

```d
import msgpack;
ubyte[] packed = pack(geo.index, geo.data);
FlexGeo unpacked; unpacked.index = ...; unpacked.data = ...; // unpack(packed, ...)
```

---

## Notes

- All coordinates 2D (x/y). Z/W deferred.
- Cell-local coordinates: future optimization — store as `LocalMeters` offsets
  from `cell.bounds.minv`, enabling f32 storage. MVP uses doubles throughout.
- `Id.count` is the local cell object id (26 bits ≈ 64M objects per cell).
- AABB hints embedded inline as `Bounds` entries are optional but recommended
  for containers, enabling bounds-rejection without scanning child points.
