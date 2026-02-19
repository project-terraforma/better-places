# experimental local map data viewer
## Setup / Run
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
