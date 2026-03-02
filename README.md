# Better Places
Project / prototypes for the Overture Maps Foundation at correcting pin placements, collecting more data,
and fixing / associating data within OMF that's missing useful relational labels.

Plus other experiments etc.

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

## Dependencies

* docker TBD
* https://dlang.org
  * (install from there or use `ldc` aka `ldc2`: https://github.com/ldc-developers/ldc)
  * you need `rdmd` (`apt install <dmd | ldc>` / `brew install <dmd | ldc>` should suffice, probably)
  * note that `ldc` is variously called `ldc` and `ldc2`
  * (note: LDC is the LLVM based D compiler; `dmd` is the *very fast* reference
    compiler w/ its own backend. `dmd` is / was very x86/64 dependent, and ARM ie aarch64 support is an active work in progress)
* `overturemaps` python CLI
  * https://docs.overturemaps.org/getting-data/overturemaps-py/
  * (the data fetching + processing tools in `data/tools` are just structured wrappers around that)

## General Overview

### Data Fetching Tools

* data fetching tools in `data/tools`
* overture data is fetched to `data/omf/<dataset_name>`
* statistical summaries / dumps to `data/summary/<dataset_name>`
  * (these are committed / updated)

### Experimental Map Viewer

* in progress

### Local Crowdsourced Data App

* early prototypes in a separate repo, needs to be committed here

### Other data fetching tools + datasets

* in progress

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

Demo w/ a single copy + paste: (docker TBD)
```bash
data/tools/fetch_omf_data.d -p all
cd mapview
dub upgrade
dub run raylib-d:install
dub run
```
