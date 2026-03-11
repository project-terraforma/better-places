# Better Places
Prototypes for the Overture Maps Foundation on places + geospatial data.

Scope crept into a mini few-dependencies D library + map viewer for working
with overture maps data thru geojson data.

## Demo

Run
```bash
make run
```

### Dependencies

* D (`ldc2` or `dmd`, `rdmd`, `dub`)
  * `wget dlang.org/install.sh && bash install.sh`
* sqlite3 
  * linux: `apt install sqlite3 libsqlite3-dev`
* the `overturemaps` python CLI
  * python
  * `pip3 install overturemaps --break-system-packages`

#### All dependencies:
```bash
wget dlang.org/install.sh && bash install.sh
pip3 install overturemaps --break-system-packages
sudo apt install sqlite3 libsqlite3-dev
cd mapview && dub run raylib-d:install && cd ..
```
```bash
make run
```

## To fetch source data:
### Overture Maps Data
```bash
data/tools/fetch_omf_data.d -p all
```
(fetches / caches data to `data/omf/santa_cruz`)

Pull geojson (note: will pull geojson by default)
```bash
data/tools/fetch_omf_data.d -p -f geojson
```

Pull geoparquet:
```bash
data/tools/fetch_omf_data.d -p -f geoparquet
```

Pull santa cruz data in the building and address themes in geoparquet (example):
```bash
data/tools/fetch_omf_data.d -p -f geoparquet sc -t building
data/tools/fetch_omf_data.d -p -f geoparquet sc building address
# ^ equivalent, can specify any combination of themes + datasets / regions
```

## General Overview

### Data Fetching Tools

* data fetching tools in `data/tools`
* overture data is fetched to `data/omf/<dataset_name>`
* statistical summaries / dumps to `data/summary/<dataset_name>`
  * (these are committed / updated)

### Experimental Map Viewer

* in `mapview`

### Ad hoc (temporary) geojson => flexgrid conversion script

* in `pipeline`

## Tools
Write out geojson data to a hex dump:
```bash
data/tools/dump_json.d > dump.txt
```

Collect data summary statistics etc on all fetched datasets (exported to `data/summary` etc)
```bash
data/tools/summarize_omf.d
```

## To add additional Overture datasets / regions:
(this is a bit janky and hardcoded, apologies)

### edit `fetch_omf_data.d`:

#### To add new regions / datasets

1) add a new target (eg `my_city` to the `Target` enum)
2) add a hardcoded case to the `BOUNDING_BOX` function for your new target
3) Congrats, you're done!
4) fetch your data by re-running `data/tools/fetch_omf_data.d -p all`
5) or `data/tools/fetch_omf_data.d -p my_city`

:D

#### To fetch additional themes:

1) Add the the new theme name to the `Theme` enum
2) re-fetch data with `data/tools/fetch_omf_data.d -p all`
3) or `data/tools/fetch_omf_data.d -p your_theme_name`

# Experimental map viewer

See `mapview`
