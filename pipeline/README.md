# "pipeline"

exists exclusively as a simple data pipline script to convert geojson collections into a flexgrid sqlite store

can't be implemented as a `rdmd` script (ish) due to more complex dependencies and thus the move here specifically to `dub`

should be refactored entirely (WIP) into / replacing `models.flexgrid_plugins.omf_loader`

and integrated into eg. `mapview` (and other tools!) to auto convert and furthermore *ideally* run fetch requests way more efficiently

(eg chunk a get all things in this bounds request into multiple requests (flexgrid!), process independently, parallel, and potentially all in memory. TBD)