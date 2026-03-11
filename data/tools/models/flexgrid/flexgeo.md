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

There are essentially 4 kinds of index elements:

* geometry elements: store N point values (`Point`, payload = N), or a fixed 4 point values (`Bounds`, payload = 0)
* geometry hierarchies: store trees using skip lists (payload = index of next sibling element)
  * doubles as storing the number of elements for the root node (next-sibling is the end of that root object's data)
  * empty (index = 0), invalid (child next sibling index exceeds its parent), and none (next sibling is None)
    are intentionally all treated as equivalent empty
* object tags (`Id`, `Tag`, `Bounds`)
* metadata on stored coord space `CoordSpace`. Multiple `CoordSpace` declarations in the same `FlexGeo` structure
  are invalid and not supported.

FlexGeo enables fast forward tree iteration and geometry algorithms in memory without deserialization / object construction.

FlexGeo is extremely cheap to serialize / deserialize, and uses - optionally - `msgpack` for index space savings.

FlexGeo is simple to construct and maintain, and supports linking arbitrary geometry substructures to other
cell data (`Id`), and/or additional locally stored arbitrary string data (`Tag`).

### Example: (Object Hierarchy + Bounds + Ids + Tagging)

```
index entries:
i   type            payload                       geometry indices
0   CoordSpace      (packed: data storage type = f64, coord space = World, coord type = PolarNorm)
1   GeoGrid         next-sibling (end) = 30
2     GeoCell       next-sibling = 21
3       GeoCellId   tag = 0 (value = 8 byte GeoCellKey)
4       Bounds      0                           <4 * 2 * 8 = 64 bytes>  (data[ 0 .. 0x40 ])
5       GeoObject   next-sibling = 20
6         Id            <parent cell id = local cell object 28>
7         MultiPolygon  next-sibling = 0 (N/A)
8           Bounds      0                       <4 * 2 * 8 = 64 bytes>  (data[ 0x40 .. 0x80 ])
9           Polygon     next-sibling = 17
10             Bounds                           <4 * 2 * 8 = 64 bytes>  (data[ 0x80 .. 0xC0 ])
11             OuterRing  next-sibling = 14
12               Bounds                         <4 * 2 * 8 = 64 bytes>  (data[ 0xC0 .. 0x100 ])
13               Points   num-points = 42       <42 * 2 * 8 = 672 bytes> (data[ 0x100 .. 0x3A0 ])
14             InnerRing  next-sibling = 0
15               Bounds   
16               Points   num-points = 13       <13 * 2 * 8 = 208 bytes> (data[ 0x3A0 .. 0x370 ])
17           Polygon    next-sibling = 0 (N/A)
18             Bounds
19             OuterRing
20                Points  num-points = 7        <7 * 2 * 8 = 112 bytes> (data[ 0x370 .. 0x3E0 ])
21       GeoObject
22         Id     <parent cell id = local cell object 3>
23         PointCloud
24           Id     <next point cell id = 124>
25           Point    1                         <2 * 8 = 16 bytes> (data[ 0x3E0 .. 0x3F0 ])
26           Point    1                         <2 * 8 = 16 bytes> (data[ 0x3F0 .. 0x400 ])
27           Tag      <next point cell local tag index = 1 (value at index = "Hello, flexgeo!")>
28           Id       <next point cell id = 214>
29           Point    1                         <2 * 8 = 16 bytes> (data[ 0x400 .. 0x410 ])
30   (None)
    ...
```
Data:
* index: u32[] with `.length >= 29`
* data:  ubyte[] with `.length >= 0x410`
* tags:  `[0: (8 bytes FlexCellId), 1: "Hello, flexgeo!"]`
* ids: parent cell ids, or `UUID[u32]` with `4` id elements

Destructured:

```
CoordSpace(storage=f64, space=World, type=PolarNorm)
GeoGrid
  GeoCell (CellId = (layer, x, y), Bounds = (...))
    GeoObject (Id = ...)
      MultiPolygon(Bounds = ...)
        Polygon(Bounds = ...)
          OuterRing(Bounds = ...)
            Points(42)
          InnerRing(Bounds = ...)
            Points(13)
    GeoObject (Id = ...)
      PointCloud
        Point(Id = ...)
        Point(Id = ..., Tag="Hello, flexgeo!")
```

### Serialization

#### MsgPack embedding:

* Flex-1 or Flex-2 stored as binary
* Flex-1 directly embedded within another MsgPack data stream

#### FlexGrid geometry storage:

* geometry data stored into `Map<u32 id, Flex-2 | binary(serialized Flex-1 | Flex-2)>`
* FlexCell serialized as `FixedMap<N>( geo = <geometry data>, ... )`
* serialized FlexCell stored/loaded from db (eg sqlite3)

#### Flex-1

Spec:
```
bytes                 values
[0..4]                "FLX1"
[4..8]                u32 data offset (in bytes)
[8..8 + data offset]  msgpack encoded data
                        FixedArray<1-3>(
                          required  index : u32[]
                          optional  tags  : Map<u32, Str>
                          optional  ids   : Map<u32, UUID as binary>
                        )
[8 + data.offset ..]  data bytes
```

#### Flex-2

Spec:
```
bytes                                 values
[0..4]                                "FLX2"
[4..8]                                u32 data offset (in bytes)
[8..12]                               u32 etc offset (or 0)
[12..16]                              u32 index count (# elements)
[16..]                              u32[index count] 
[..32 + data offset]                  optional 0-pad
[32 + data offset .. 32 + etc offset] data
[32 + etc offset .. ]                 optional FixedArray<1-2>( tags, optional ids )
```

##### Ids

* optional mapping of ids (*cell-local autoinc ids*) to UUIDs (stored as binary blobs)

#### Tags

* optional tag (arbitrary local data) annotated to FlexGeo objects
* primary use is to annotate additional info with the `PointCloud` type
* tags are geometry-local (ids are *cell-local*)
* the type stored for a sane FlexGeo format is `Str` (or potentially binary)
* tag values are expected to either be strings or JSON
* directly packing JSON-converted trees of arbitrary data would make sense, but implementing this as is into
  the current `FlexGeo` implementation would be prohibitively difficult
* essentially enables storing additional information for certain (technically any!) geometry type, without polluting
  `FlexCell` full of tons of point data ids. (current usage: point clouds of locally captured GPS data with
  additional tag information)

---

## Index Entry (packed u32)

```
bits [0..5]   type         GeoType (5 bits)
bits [5..31]  payload      uint (26 bits)
bits [31..32] continuation bit (reserved)
```

---

## GeoType Tags

| Tag          | Value | payload                      | geometry data consumed   |
|--------------|-------|------------------------------|--------------------------|
| None         | 0     | 0                            | 0                        |
| Point        | 1     | N                            | N points (N*2) values    |
| Bounds       | 2     | 0 (ignored)                  | 4 points (16 values): minx,miny,maxx,maxy |
| Id           | 3     | cell-local object index      | 0                        |
| Tag          | 4     | geometry-local tag index     | 0                        |
| GeoCellKey   | 5     | tag index (stored in tag data) | 0                      |
| GeoSpaceInfo | 6     | <packed coordinate system + data stride info>       | 0 |
| Reserved     | 7     | --                                                  | 0 |
| RingOuter    | 8     | 0 or offset of next sibling  | 0                        |
| RingInner    | 9     | 0 or offset of next sibling  | 0                        |
| Polygon      | 0xA   | 0 or offset of next sibling  | 0                        |
| MultiPolygon | 0xB   | 0 or offset of next sibling  | 0                        |
| Line         | 0xC   | 0 or offset of next sibling  | 0                        |
| LineString   | 0xD   | 0 or offset of next sibling  | 0                        |
| PointCloud   | 0xE   | 0 or offset of next sibling  | 0                        |
| RESERVED     | ...   | 0 or offset of next sibling  | 0                        |
| GeoObject    | 0x1D  | 0 or offset of next sibling  | 0                        |
| GeoCell      | 0x1E  | 0 or offset of next sibling  | 0                        |
| GeoGrid      | 0x1F  | 0 or offset of next sibling  | 0                        |

#### Nesting rules:

| Tag          | Allowed annotations          | Allowed children                                |
|--------------|------------------------------|-------------------------------------------------|
| GeoGrid      | Id, Tag, Bounds              | any < 0x1F                                      |
| GeoCell      | Id, Tag, Bounds, CellGridKey | any < 0x1E                                      |
| GeoCollection | Id, Tag, Bounds             | any <= 0x1D                                     |
| GeoObject    | Id, Tag, Bounds              | any <= 0x1C                                     |
| PointCloud   | Id, Tag, Bounds              | Point, Points, PointCloud                       |
| Poly         | Id, Tag, Bounds              | RingOuter, RingInner, Poly                      |
| Line         | Id, Tag, Bounds              | Point, Points, Line                             |
| Point        | Id, Tag, Bounds              | N/A                                             |
| RingInner    | Bounds                       | Points                                          |
| RingOuter    | Bounds                       | N/A                                             |
| Points       | N/A                          | N/A                                             |


## GeoSpaceInfo

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
