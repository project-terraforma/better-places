# experimental local map data viewer
## Setup
### Setup / Run
run, from the parent directory:
```bash
data/tools/fetch_omf_data.d -p all
cd mapview
dub upgrade
dub run raylib-d:install
dub run
```
### Run
```bash
dub run
```
### Data
make sure you pulled data / the santa cruz data set (above)

## Dependencies
* https://dlang.org
* https://code.dlang.org/packages/raylib-d
* https://www.raylib.com/

## Controls
* press ESC to exit

## Notes:

There are *intentionally* two different point / vec2 types in use here.
* Point: (from `data/tools/models/geometry/package.d`)
  * geospatial `Point` type
  * f64 precision
  * generally / nearly always represents Lat/Long
* Vector2: the `raylib` Vec2 type
  * from `raymath` (and specifically the `raylib-d` bindings)
  * f32 precision
  * generally used to represent *pixel* / *screenspace* coordinates
  * (and potentially anything cached / precomputed etc)
* having separate types to represent different coordinate systems (and by-spec precision) is a generally excellent idea
* note that there are also two AABB / Rect types:
  * `AABB` (ours, from `models.geometry`) is a pair of **min/max** `Point` values.
  * `Rectangle` (used extensively by raylib) is an **x/y + width/height** structure. 
  * Both are functionally identical and there are only fairly minor performance tradeoffs in chosing a `min_point` + `bounds` vs `min + max point` implementation.
  * the `AABB` implementation (ours) uses simple `min/max` values as the primary use there is working with polygons (`Ring`s, and compositions of `Ring`s) and bounds checking, both of which are slightly more efficient using just min/max values
  * for working extensively with rect calculations (UI etc) the point + bounds approach is generally better as you will often ideally be working with those separated components. /2c

## TODO

* webmercator map projection (currenly using RAW lat/long => screenspace, which obviously produces minor x/y distortion errors without a spherical (or janky ass webmercator) projection)
* map panning
* mouseover
* viewing data / props
* search + go-to
* view filtering (and/or toolkit for easy view filtering)
* better / faster data backend
* better rendering
* etc
