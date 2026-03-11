# data/tools/models

Tiny D support library for working with geospatial data

Used by scripts in `/tools` (hence this directory), and by `/mapview` etc

* `geojson` (basic geojson support built off of `geometry`)
* `geometry` (generic point, bounds, polygon, line types *and typed unit-errors-are-compiler-errors* unit conversion to/from `PolarDeg` (standard), `PolarRad` (radians), `PolarNorm` (internal, maps `[-180,+180]` to `[-0.5, +0.5]`, `[0, 360]` to `[0, 1]`, etc))
* `omf`: intermediates and typed data structures for working with omf data themes thru geojson
* `flexgrid`: see `/flexgrid`
* `flexgeo`: see `/flexgrid/flexgeo`
* `flexgrid_plugins`: theoretically supposed to disentangle OMF data from flexgrid a la `omf` (should be renamed to `omf_geojson`) w/r `geojson`. de facto however needs heavy refactoring and there is code that
needs cleanup there, in `flexgrid`, and in `pipeline`. (WIP)

