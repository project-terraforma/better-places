module models.flexgrid_plugins.omf_loader;
import models.flexgrid;
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
    size_t i = 0;
    foreach (item; buildings.items.byValue) {
        auto bounds = item.geo.bounds.to!PolarNorm;
        auto key = FlexCellKey.from(bounds);
        auto cell = grid.getOrCreateCell(key);
        auto id = item.id;
        cell.bbx[id] = bounds;
        cell.geo[id] = TGeometry!PolarDeg(item.geo);
        cell.props[id] = item.props;
        cell.bounds.grow(bounds.maxv);
        ++i;
    }
    writefln("loaded %s buildings", i);
    writefln("has %s cells", grid.cells.length);
    size_t n = 0;
    foreach (cell; grid.cells.byValue) {
        writefln("cell %x: %s items, size = %s (%s), at = (%s,%s,%s), = %s to %s",
            cell.cellKey.value,
            cell.bbx.length,
            cell.bounds.size.to!Meters,
            cell.bounds.size.to!PolarDeg,
            cell.level,
            cell.cellKey.x,
            cell.cellKey.y,
            cell.bounds.minv.to!PolarDeg,
            cell.bounds.maxv.to!PolarDeg
        );
        if (++n > 100) break;
    }
}
void load (FlexGrid grid, OmfCollection!BuildingPart buildings) {

}
void load (FlexGrid grid, OmfCollection!Place buildings) {

}
void load (FlexGrid grid, OmfCollection!(models.omf.Address) buildings) {

}
