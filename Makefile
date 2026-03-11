all: run
clean:
	rm -rf data/flexgrid data/omf
	
run: data/flexgrid/santa_cruz.db mapview/libraylib.so
	cd mapview && dub run && cd ..
	
mapview/libraylib.so:
	cd mapview && dub run raylib-d:install

geojson_dataset: data/omf/santa_cruz/.bounds.txt
flexgrid_dataset: data/flexgrid/santa_cruz.db
	
summary: geojson_dataset
	data/tools/summarize_omf.d
summaries: summary places_summary address_summary
places_summary: geojson_dataset
	data/tools/find_building_places.d
address_summary: geojson_dataset
	data/tools/find_building_addresses.d
geojson_dump: dump.txt
dump.txt: geojson_dataset
	data/tools/dump_json.d > $@

data/flexgrid/santa_cruz.db: geojson_dataset
	cd pipeline && dub run && cd ..

data/omf/santa_cruz/.bounds.txt: data/tools/fetch_omf_data.d
	data/tools/fetch_omf_data.d -p santa_cruz
