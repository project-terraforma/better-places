module controllers.map_loader;
import base;
import std;
import models.flexgrid.flexstore; // sql loading
import models.omf; // geojson loading
import models.geojson;
// import std.concurrency: Tid, spawn;
import core.thread: Thread;

alias AABB = base.AABB;
alias Point = base.Point;

// hack: avoid D 'shared' safety bullshit
private struct LoadThreadHandle {
    Thread thread = null;
    ~this () {
        if (thread) {
            writefln("terminating in progress map load");
            thread.join();
        }
        thread = null;
    }
}
void start (ref LoadThreadHandle h, void delegate() dg) {
    h.thread = new Thread(dg);
    h.thread.start();
}

struct MapLoader {
    FlexGrid grid;
    string dataset;
    string datasetPath;
    bool isLoading = false;
    // Tid asyncLoadingThread;
    LoadThreadHandle asyncLoadingThread;

    alias OnLoadDg = void delegate(ref MapLoader,FlexGrid,AABB);
    OnLoadDg onLoadDg;

    alias OnErrDg = void delegate(Throwable);
    OnErrDg onErrDg;

    void load (FlexGrid grid, string dataset, OnLoadDg onLoadDg, OnErrDg onErrDg) {
        assert(!isLoading);
        this.grid = grid;
        this.dataset = dataset;
        this.onLoadDg = onLoadDg;
        this.onErrDg = onErrDg;
        this.isLoading = true;
        this.asyncLoadingThread.start(&doLoad);
        // this.asyncLoadingThread = spawn(&doLoadAsync, &this);
    }
    this(this){
        assert(asyncLoadingThread.thread is null,
            "critical usage error: CANNOT COPY / PASS MAPLOADER BY VALUE"~
            " DUE TO HOLDING RTTI THREAD HANDLE FOR JOIN!");
    }
private:
    void doLoad () {
        assert(isLoading);
        scope(exit) this.isLoading = false;
        try {
            AABB bounds = doLoadImpl();
            writefln("finished load: '%s', %s", dataset, bounds.to!PolarDeg);
            onLoadDg(this, grid, bounds);
        } catch (Throwable err) {
            writefln("load error: '%s'\n\t%s", dataset, err);
            onErrDg(err);
        }
    }
    AABB doLoadImpl () {
        auto datasetName = dataset;
        auto dataPath = "../data/omf".buildPath(datasetName);
        writefln("using data path %s", dataPath);
        auto bounds = dataPath.buildPath(".bounds.txt").readText;
        writefln("use bounds '%s'", bounds);
        auto bnds = bounds.strip().split(',').map!(x => x.to!double).array;
        enforce(bnds.length == 4, "invalid bounds! %s".format(bounds));
        writefln("bounds (raw) = %s", bnds);
        auto viewBoundsPolarDeg = TAABB!PolarDeg(
            TPoint!PolarDeg(bnds[0], bnds[1]),
            TPoint!PolarDeg(bnds[2], bnds[3])
        );
        writefln("=> %s", viewBoundsPolarDeg);
        auto viewBounds = viewBoundsPolarDeg.to!PolarNorm;
        writefln("set bounds for dataset %s: %s", dataPath, viewBounds.to!PolarDeg);

        // try load sql

        auto dbPath = buildPath("..", "data", "flexgrid", datasetName~".db");
        if (dbPath.exists) {
            writefln("loading from sqlite '%s'", dbPath);
            scope store = new FlexStore!FlexStoreSqlite3Storage(dbPath, grid);
            store.load();
            return viewBounds;
        }

        // else load geojson

        writefln("loading dataset '%s'", dataPath);
        enforce(dataPath.exists, "can't locate dataset directory '%s'".format(dataPath));
        foreach (file; [".bounds.txt"] ~ ["address", "building", "building_part", "place"]
            .map!(part => part ~ ".geojson").array
        ) {
            auto path = dataPath.buildPath(file);
            enforce(path.exists, "missing file '%s'".format(path));
        }
        scope dataset = new OmfDataset().loadGeoJson(dataPath);
        static foreach (PART; OmfDataset.PARTS) {
            load(grid, mixin("dataset." ~ PART), PART);
        }
        return viewBounds;
    }
    // Load a single OMF collection into the grid as a named layer.
    // Mirrors the equivalent function in pipeline/source/app.d.
    void load (TPart)(FlexGrid grid, OmfCollection!TPart collection, string name) {
        auto layerName = "omf.%s".format(name);
        auto layerId   = grid.getOrCreateLayer(layerName).id;
        writefln("loading layer %s", layerName);
        foreach (item; collection.items) {
            static if (__traits(compiles, item.pos)) {
                auto point = item.pos.to!PolarNorm;
                auto key   = FlexCellKey.from(point);
                auto cell  = grid.getOrCreateCell(key, layerId);
                cell.addPoint(item.id, point);
                auto id    = cell.getOrInsertId(item.id);
                cell.decodedProps[id] = item.props;
            } else {
                auto geo  = toFlexGeo(item.geo);
                auto key  = FlexCellKey.from(geo.bounds);
                auto cell = grid.getOrCreateCell(key, layerId);
                cell.addGeometry(item.id, geo);
                auto id   = cell.getOrInsertId(item.id);
                cell.decodedProps[id] = item.props;
            }
        }
        writefln("loaded %s cells into layer %s"
            , grid.layers[layerId].cells.length
            , layerName);
    }

}
// private void doLoadAsync (MapLoader* loader) {
//     loader.doLoad();
// }
