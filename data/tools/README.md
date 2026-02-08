# Data Fetching Tools
### Requirements

* install D + `rdmd`:
  * https://dlang.org
  * https://github.com/ldc-developers/ldc

### fetch_omf_data.d

Fetches (and locally caches) overture map data for predefined regions ("Targets"), themes, and data formats.

Current targets:

* `santa_cruz` aka `sc`

Run from the root directory:
```bash
data/tools/fetch_omf_data.d <args>
```
#### Args:
* `-p`, `--parallel`: run all data fetches or other operations in parallel (recommended)
* `-f`: format (`geojson` | `parquet`)
* `--clean`: remove all selected files
* `-r` | `--refetch`: fetch or refetch all selected files
* fetch (default behavior) ignores files that already exist locally
* `<target name>` | `<OMF Theme>` | `"all"`: stuff to fetch / refetch / remove
* with no arguments: defaults to `"all"`

Examples:
* fetch all santa cruz data: `data/tools/fetch_omf_data.d sc`
* fetch all buildings: `data/tools/fetch_omf_data.d building building_part`
* refetch all geojson: `data/tools/fetch_omf_data.d -r -f geojson`
