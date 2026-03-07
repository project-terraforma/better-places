import models.flexgrid;
import models.flexgrid.flexgeo;
import models.omf;
import std;
import models.flexgrid.flexstore;

struct BenchInfo {
    import std.datetime.stopwatch;
    StopWatch[string] sw;
    string[] runs;

    void start(string name) { sw[name] = StopWatch(); sw[name].start(); runs ~= name; }
    void stop(string name)  { sw[name].stop(); }
    void summary() {
        writefln("\n");
        foreach (key; runs) {
            writefln("\t%s: %s", key, sw[key].peek());
        }
    }
}

void loadGeoJson(ref BenchInfo bench, ref FlexGrid grid, string dataPath) {
    enforce(dataPath.exists, "could not open %s", dataPath);
    writefln("loading %s", dataPath);

    bench.start("load geojson");
    scope dataset = new OmfDataset().loadGeoJson(dataPath);
    bench.stop("load geojson");

    writefln("loaded / done");
    grid = new FlexGrid();

    bench.start("load geojson => grid");
    static foreach (PART; dataset.PARTS) {
        load(grid, dataset, mixin("dataset."~PART), PART);
    }
    bench.stop("load geojson => grid");
}

void summarizeStats(ref BenchInfo bench, ref FlexGrid grid) {
    struct CellGridStats {
        uint layerCount;
        uint points;
        uint geo;
        string[] layers;
    }
    bench.start("collect grid stats");
    CellGridStats[FlexCellKey] stats;
    foreach (layer; grid.layers.byValue) {
        foreach (cell; layer.cells.byValue) {
            auto key = cell.cellKey;
            auto existing = key in stats;
            if (key !in stats) {
                stats[key] = CellGridStats();
                existing = key in stats;
                assert(existing);
            }
            existing.layerCount++;
            existing.layers ~= layer.name;
            existing.geo += cell.geo.length;
            existing.points += cell.points.length;
        }
    }
    foreach (kv; stats.byKeyValue) {
        auto s = kv.value;
        writefln("cell %x : %s points, %s geo, %s layers (%s)",
            kv.key.value, s.points, s.geo, s.layerCount, s.layers
        );
        foreach (ref layer; grid.layers.byValue) {
            auto cell = kv.key in layer.cells;
            if (cell) {
                auto key = cell.cellKey;
                writefln("\tlayer '%s' (%s); %s points, %s geo, bounds %s"
                    , layer.name, layer.id, cell.points.length,
                    cell.geo.length, cell.bounds.size.to!Meters
                );
                // auto serialized = (*cell).serializeBlob();
                // writefln("\tCell storage: %s", serialized.length);
                // writefln("\t\t%s", cast(string)serialized);

                // writefln("\t\tkey bounds = %s, %s   (%s)  => %s",
                //     key.bounds.minv, key.bounds.maxv, key.bounds.size, key.bounds.size.to!Meters
                // );
                // writefln("\t\tcell bounds = %s, %s   (%s)  => %s",
                //     cell.bounds.minv, cell.bounds.maxv, cell.bounds.size, cell.bounds.size.to!Meters
                // );
            }
        }
    }
    bench.stop("collect grid stats");

    bench.start("serialize cells");
    size_t nCells = 0, totalPoints = 0, totalGeometry = 0;
    size_t totalGeometryBytes = 0, totalPointsBytes = 0, totalGeoIndexBytes;
    size_t totalSerializedBytes = 0;
    size_t maxSerializedBytes = 0, minSerializedBytes = size_t.max;
    double maxBytesPerObj = 0, minBytesPerObj = cast(double)u32.max;

    foreach (kv; stats.byKeyValue) {
        foreach (ref layer; grid.layers.byValue) {
            auto cell = kv.key in layer.cells;
            if (cell) {
                nCells += 1;
                totalPoints += cell.points.length;
                totalGeometry += cell.geo.length;

                totalPointsBytes += cell.points.length * Point.sizeof;
                foreach (geo; cell.geo.byValue) {
                    totalGeometryBytes += geo.points.length * Point.sizeof;
                    totalGeoIndexBytes += geo.entities.length * uint.sizeof;
                }

                ubyte[] serialized = (*cell).serializeBlob();
                // writefln("\tCell storage: %s", serialized.length);
                size_t sb = serialized.length;
                totalSerializedBytes += serialized.length;
                maxSerializedBytes = max(maxSerializedBytes, sb);
                minSerializedBytes = min(minSerializedBytes, sb);
                if (sb) maxBytesPerObj = max(maxBytesPerObj, cast(double)sb / cell.geo.length);
                if (sb) minBytesPerObj = min(minBytesPerObj, cast(double)sb / cell.geo.length);
            }
        }
    }
    bench.stop("serialize cells");

    double n = cast(double)nCells;
    writeln();
    writefln("%s cells", stats.length);
    writeln();
    writefln("avg points per cell = %s, geometry per cell = %s",
        totalPoints / n, totalGeometry / n);
    writefln("min, max, avg serialized bytes = %s, %s, %s", minSerializedBytes, maxSerializedBytes, totalSerializedBytes / n);
    n = totalGeometry;
    writefln("min, max, avg serialized bytes = %s, %s, %s", minBytesPerObj, maxBytesPerObj, totalSerializedBytes / n);
    writefln("total data");
    writefln("\tgeometry    (raw): %s mb", totalGeometryBytes  * 1e-6);
    writefln("\tgeo indices (raw): %s mb", totalGeoIndexBytes * 1e-6);
    writefln("\tpoints      (raw): %s mb", totalPointsBytes  * 1e-6);
    writefln("\tcombined    (raw): %s mb", (totalGeometryBytes + totalGeoIndexBytes + totalPointsBytes) * 1e-6);
    writefln("\tserialized cells : %s mb", totalSerializedBytes * 1e-6);

    bench.start("serialize geometry (only), FLX1");
    size_t totalBytes = 0;
    foreach (kv; stats.byKeyValue) {
        foreach (ref layer; grid.layers.byValue) {
            auto cell = kv.key in layer.cells;
            if (cell) {
                foreach (geo; cell.geo.byValue) {
                    totalBytes += geo.serialize(FlexGeoFmt.FLX1).length;
                }
            }
        }
    }
    bench.stop("serialize geometry (only), FLX1");
    writefln("\tserialized geometry (only), FLX1: %s mb", totalBytes * 1e-6);

    bench.start("serialize geometry (only), FLX2");
    totalBytes = 0;
    foreach (kv; stats.byKeyValue) {
        foreach (ref layer; grid.layers.byValue) {
            auto cell = kv.key in layer.cells;
            if (cell) {
                foreach (geo; cell.geo.byValue) {
                    totalBytes += geo.serialize(FlexGeoFmt.FLX2).length;
                }
            }
        }
    }
    bench.stop("serialize geometry (only), FLX2");
    writefln("\tserialized geometry (only), FLX2: %s mb", totalBytes * 1e-6);
}

void loadSql(ref BenchInfo bench, FlexGrid grid, string dbFile) {
    scope store = new FlexStore!FlexStoreSqlite3Storage(dbFile, grid);
    bench.start("load sql");
    store.load();
    bench.stop("load sql");
}
void main(string[] args) {
    enum DATASET_DIR = "../data/omf";
    bool doLoadSql = false;
    string dataset = "santa_cruz";
    if (args.length > 1) {
        foreach (arg; args[1..$]) {
            if (arg == "sql") { doLoadSql = true; }
            else dataset = arg;
        }
    }
    auto dataPath = DATASET_DIR.buildPath(dataset);
    writefln("loading %s", dataPath);
    auto dir = DATASET_DIR.buildPath("..", "flexgrid");
    if (!dir.exists) dir.mkdirRecurse;
    auto dbFile = dir.buildPath(dataset~".db");

    BenchInfo bench;
    scope grid = new FlexGrid();

    if (doLoadSql) {
        loadSql(bench, grid, dbFile);
    } else {
        loadGeoJson(bench, grid, dataPath);
    }
    summarizeStats(bench, grid);
    bench.summary();

    BenchInfo b2;
    scope store = new FlexStore!FlexStoreSqlite3Storage(dbFile, grid);
    if (!doLoadSql) {
        b2.start("save to sql");
        store.save();
        b2.stop("save to sql");
    }

    b2.summary();
}
void load (TPart)(FlexGrid grid, OmfDataset dataset, OmfCollection!TPart collection, string name) {
    writefln("loading layer %s", name);
    auto layerName = "omf.%s".format(name);
    auto layerId = grid.getOrCreateLayer(layerName).id;
    writefln("layer %s => %s, %s", layerName, layerId, grid.getOrCreateLayer(layerName).name);
    foreach (item; collection.items) {
        static if (__traits(compiles, item.pos)) {
            auto point = item.pos.to!PolarNorm;
            auto key = FlexCellKey.from(point);
            auto cell = grid.getOrCreateCell(key, layerId);
            auto id = cell.getOrInsertId(item.id);

            auto keyBounds = key.bounds;
            enforce(keyBounds.contains(point),
                "bounds %s\n\t%s\n\n\tdoes not contain %s (%s)!\n\t(original: %s)"
                .format(keyBounds,
                    keyBounds.to!PolarDeg,
                    point, point.to!PolarDeg,
                    item.pos));

            cell.addPoint(item.id, point);
            cell.decodedProps[id] = item.props;
            // writefln("point %x (cell bounds %s)", key.value, cell.bounds.size.to!Meters);
            // writefln("%s, %s, (%s) %s", key.bounds.minv, key.bounds.maxv, key.bounds.size.to!Meters, point);
        } else {
            auto geo = toFlexGeo(item.geo);
            auto key = FlexCellKey.from(geo.bounds);
            auto cell = grid.getOrCreateCell(key, layerId);
            cell.addGeometry(item.id, geo);
            auto id = cell.getOrInsertId(item.id);
            cell.decodedProps[id] = item.props;

            // writefln("bounds %x (%s) (cell bounds %s)", key.value
            //     , geo.bounds.size.to!Meters, cell.bounds.size.to!Meters);
            // writefln("%s, %s, (%s) %s", key.bounds.minv, key.bounds.maxv, key.bounds.size.to!Meters, geo.bounds.minv);
        }
    }
}
