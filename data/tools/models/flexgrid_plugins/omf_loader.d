module models.flexgrid_plugins.omf_loader;
import models.flexgrid.grid;
import models.omf;
import std;

void loadOmfGeoJson(FlexGrid toGrid, string fromOmfGeoJsonPath) {
    writefln("loading dataset '%s' to %s", fromOmfGeoJsonPath, toGrid);
    scope dataset = new OmfDataset();
    dataset.loadGeoJson(fromOmfGeoJsonPath);
    writefln("loaded dataset '%s'; loading into %s", fromOmfGeoJsonPath, toGrid);
    load(toGrid, dataset);
}
void load (FlexGrid toGrid, OmfDataset fromDataset) {
    static foreach (PART; OmfDataset.PARTS) {
        load(toGrid, mixin("fromDataset."~PART));
    }
}
void load (FlexGrid grid, OmfCollection!Building buildings) {

}
void load (FlexGrid grid, OmfCollection!BuildingPart buildings) {

}
void load (FlexGrid grid, OmfCollection!Place buildings) {

}
void load (FlexGrid grid, OmfCollection!(models.omf.Address) buildings) {

}
