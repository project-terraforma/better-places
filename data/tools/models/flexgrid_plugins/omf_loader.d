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
void loadInto (FlexGrid toGrid, OmfDataset fromDataset) {
    auto tr = toGrid.beginDataAddTransaction();
    auto grid = tr.grid;
    static foreach (PART; OmfDataset.PARTS) {
        loadInto(grid, mixin("fromDataset."~PART), PART);
    }
    static foreach (PART; OmfDataset.PARTS) {
        postprocess(grid, mixin("fromDataset."~PART), PART);
    }
    tr.commit();
}
void postprocess (FlexGrid grid, OmfCollection!Building part, string partName) {
    auto buildings = grid.layerRequired("omf.building");
    auto address = grid.layerRequired("omf.address");
    auto addressRadius = Scalar!(Meters)(300.0);
    auto streetRadius = Scalar!(Meters)(500.0);

    static void assignNearbyStreets(
        FlexView                            view,
        IdTaggedGeometry!(PolarNorm)        buildingGeometry,
        IdTaggedLineSegments!(PolarNorm)[]  streets,
    ) {
        foreach (streetGeometry; streets) {
            if (view.raycastsHitsAnyIntervening(buildingGeometry, streetGeometry)) {}
            else {
                auto building = view.get!OmfBuilding(geo.id);
                auto street = view.get!OmfStreet(street.id);
                building.addNearbyStreet(street,
                    buildingGeometry.selectEdgeSegmentsThatAreFacing(streetGeometry)
                );
            }
        }
    }
    grid.forAllLineSegmentsWithinOrNearRadiusOfGeometryOnLayers(
        buildings, streets, buildingStreetRadius,
        &assignNearbyStreets
    );
    static void assignPossibleBuildingAddresses(
        FlexView                            view,
        Geometry!(PolarNorm)                geo,
        Point!(PolarNorm)                   pointsWithinGeometry,
        PointRadius!(PolarNorm,Meters)[]    pointsNearGeometry,
        Scalar!(Meters)                     searchRadius
    ) {
        // TODO: algorithm
        // ideas:
        // 1) warn (insert into an error/warning dataset) about any points on or very near building geometry
        //    that do
    }
    grid.forAllPointsWithinOrNearRadiusOfGeometryOnLayers(
        buildings, address, addressRadius,
        &assignPossibleBuildingAddresses
    );
}


void loadInto (TPart,TUnit=PolarNorm)(FlexGrid grid, OmfCollection!TPart part, string partName) {
    auto layer = grid.layer("omf."~partName);
    foreach (item; part.items.byValue) {
        static if (__traits(compiles, item.point)) {
            // Point data: Places, Addresses
            auto key    = FlexCellKey.from(item.point);
            auto cell   = grid.getCel(key);
            auto id     = cell.getId(key, layer, item.id);
            cell.assign(id, item.point);
            grid.addGlobalIdLookup(id, layer, item.id, item.point);
            auto props = item.buildObject(id, cell);
            cell.assign(id, props);
        } else {
            // Geometry data: Buildings, Streets, Connectors, etc
            scope builder = GeometryBuilder!TUnit(GeoType.GeoObject, UnitToSpace!TUnit);
            builder.id(0);
            size_t idIndex = builder.geo.index.length-1;
            assert(builder.geo.index[idIndex].type == GeoType.Id);
            TAABB!TUnit bounds;
            builder.addGeometryWithBuildAndAssignBoundsRecursive(item.geo, bounds);
            auto key     = grid.key(bounds, layer);
            auto cell    = grid.getCell(key);
            auto id      = cell.getId(key, layer, item.id);
            builder.geo.index[idIndex].assign(id);
            auto geo = builder.build();
            cell.assign(id, geo);
            grid.addGlobalIdLookup(id, layer, item.id, bounds);
            auto props = item.buildObject(id, cell);
            cell.assign(id, props);
        }
    }
}
OmfPlace buildObject (Building a, FlexObjectId id, FlexCell cell) {
    return new OmfPlace(
        id,
        a.id,
        cell.getSourcesOmf(a.props["sources"]),
        cell.getAddressOmf(a.props["address"]),
    );
}
OmfAddress buildObject (Address a, FlexObjectId id, FlexCell cell) {
    return new OmfAddress(
        id,
        a.id,
        cell.getSourcesOmf(a.props["sources"]),
        cell.getAddressOmf(a.props["address"]),
    );
}
OmfAddress buildObject (Place a, FlexObjectId id, FlexCell cell) {
    return new OmfPlace(
        id,
        a.id,
        cell.getSourcesOmf(a.props["sources"]),
        cell.getAddressOmf(a.props["address"]),
    );
}
class OmfObject : FlexObject {
    UUID omfId;
    SourcesInfo sourcesInfo;
    this (FlexObjectId id, UUID omfId, SourcesInfo sourcesInfo) {
        super(id); this.omfId = omfId; this.sourcesInfo = sourcesInfo;
    }
}
class OmfAddressObject : OmfObject {
    FlexAddress address;
    this (FlexObjectId id, UUID omfId, SourcesInfo sourcesInfo, FlexAddress address) {
        super(id, omfId, sourcesInfo); this.address = address;
    }
}
class OmfBuilding : OmfAddressObject {
    this (FlexObjectId id, UUID omfId, SourcesInfo sourcesInfo, FlexAddress address) {
        super(id, omfId, sourcesInfo, address);
    }
}
class OmfAddress : FlexObject {
    this (FlexObjectId id, UUID omfId, SourcesInfo sourcesInfo, FlexAddress address) {
        super(id, omfId, sourcesInfo, address);
    }
}
class OmfPlace : FlexObject {
    this (FlexObjectId id, UUID omfId, SourcesInfo sourcesInfo, FlexAddress address) {
        super(id, omfId, sourcesInfo, address);
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

    writefln("load finished; dumping cells");
    size_t sz = 0, cellCount = 0;
    foreach (kv; grid.cells.byKeyValue) {
        auto key = kv.key, cell = kv.value;
        writef("key %s: ", key);
        import msgpack;
        ubyte[] data = pack(cell.data);
        writefln("%s bytes", data.length);
        sz += data.length;
        ++ cellCount;
        writefln("%s", data);
        writeln();

        // auto cell = new FlexCell();
        auto unpackedCell = data.unpack!(FlexCell.Data);
        writefln(" => %s", unpackedCell);

        auto packed2 = unpackedCell.pack();
        enforce(data == packed2, "%s\n\t!=\n%s".format(data, packed2));
    }
    writefln("%s bytes (%s cells, avg %s)",
        sz, cellCount, cast(double)sz / cellCount
    );
}
void load (FlexGrid grid, OmfCollection!BuildingPart buildings) {

}
void load (FlexGrid grid, OmfCollection!Place buildings) {

}
void load (FlexGrid grid, OmfCollection!(models.omf.Address) buildings) {

}
