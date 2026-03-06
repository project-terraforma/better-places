module models.flexgrid.flexstore;
import models.flexgrid;
import core.sync: Mutex;
import d2sqlite3;
import std;

class FlexStore (TFlexStoreIO = FlexStoreSqlite3Storage) {
    string          path;
    FlexGrid        grid;
    TFlexStoreIO    io;

    this (string path, FlexGrid grid) {
        this.path = path;
        this.grid = grid;
    }

    // ~this() { save(); }
    // this(this) = delete;

    void load () { io.load(path, grid); }
    void save () { io.save(path, grid); }
    // bool load (FlexCellKey key) { return io.tryLoad(key); }
    // bool save (FlexCellKey key) { return io.trySave(key); }
}

struct FlexStoreSqlite3Storage {
    string          path;
    Database        db;
    FlexGrid        grid;
    bool            open = false;
    bool            loadedGrid = false;
    Mutex           mutex;

    private void lazyConnectDb () {
        if (!mutex) mutex = new Mutex();
        synchronized(mutex) {
            if (open) return;
            open = true;
            this.db = Database(path);
            db.run(q{
                CREATE TABLE IF NOT EXISTS flexgrid (
                    key     INTEGER,
                    layer   INTEGER,
                    level   INTEGER,
                    x       INTEGER,
                    y       INTEGER,
                    data    BLOB,
                    PRIMARY KEY(key, layer)
                );
                CREATE TABLE IF NOT EXISTS layers (
                    id      INTEGER PRIMARY KEY AUTOINCREMENT,
                    name    TEXT
                );
            });
        }
    }
    private void loadLayers () {
        uint[string] layers;
        ResultRange results = db.execute(q{SELECT id,name from layers});
        foreach (row; results) {
            auto id = row.peek!long(0);
            auto name = row.peek!string(1);
            writefln("found layer %s = '%s'", id, name);
            assert(id >= 0 && id <= uint.max, "invalid layer id %s".format(id));
            assert(name !in layers, "duplicate layer name '%s'!".format(name));
            layers[name] = cast(uint)id;
        }
        grid.loadLayers(layers);
    }
    private void preloadGrid () {
        ResultRange results = db.execute(q{SELECT key,layer from flexgrid});
        foreach (row; results) {
            auto key = row.peek!ulong(0);
            auto layer = row.peek!uint(1);
            assert(key >= 0 && key <= ulong.max);
            assert(layer >= 0 && layer <= uint.max, "invalid layer %s".format(layer));
            grid.preload(FlexCellKey.ValidatedFromRaw(key), layer);
        }
    }
    void lazyPreloadGrid () {
        assert(mutex);
        assert(open);
        synchronized(mutex){
            if (loadedGrid) return;
            loadedGrid = true;
        }
        loadLayers();
        preloadGrid();
        loadAll();
    }
    void load (string path, FlexGrid grid) {
        this.path = path;
        this.grid = grid;
        lazyConnectDb();
        if (!loadedGrid) lazyPreloadGrid();
    }
    void load (FlexCellKey key) {
        enforce(open && loadedGrid);
        auto result = db.execute("SELECT key,layer,data from flexgrid where key == %d".format(key.value));
        foreach (row; result) {
            grid.load(FlexCellKey.ValidatedFromRaw(row.peek!ulong(0)), row.peek!uint(1), row.peek!(ubyte[])(2));
        }
    }
    void loadAll () {
        enforce(open && loadedGrid);
        auto result = db.execute("SELECT key,layer,data from flexgrid");
        foreach (row; result) {
            grid.load(FlexCellKey.ValidatedFromRaw(row.peek!ulong(0)), row.peek!uint(1), row.peek!(ubyte[])(2));
        }
    }

    void save (string path, FlexGrid grid) {
        writefln("save => %s", path);
        this.grid = grid;
        this.path = path;
        if (!open) lazyConnectDb();
        saveLayers();
        saveGrid();
    }
    private void saveLayers () {
        writefln("save layers (layers = %s)", grid.layers.length);
        Statement stmt = db.prepare(
            "INSERT OR REPLACE INTO layers (id, name) VALUES (:id, :name)"
        );
        foreach (layer; grid.layers.byValue) {
            writefln("saving layer %s", layer.name);
            stmt.bind(1, layer.id);
            stmt.bind(2, layer.name);
            // writefln("%s", stmt);
            stmt.execute();
            stmt.reset();
        }
    }
    private void saveGrid () {
        writefln("save grid");
        Statement stmt = db.prepare(
            "INSERT OR REPLACE INTO flexgrid (key, layer, level, x, y, data) VALUES (:key, :layer, :level, :x, :y, :data)"
        );
        foreach (layer; grid.layers.byValue) {
            writefln("saving layer '%s'", layer.name);
            foreach (cell; layer.cells.byValue) {
                writefln("saving cell '%s'/'%s'", layer.name, cell.cellKey.value);
                stmt.bind(1, cell.cellKey.value.reinterpLong);
                stmt.bind(2, layer.id);
                stmt.bind(3, cell.cellKey.level);
                stmt.bind(4, cell.cellKey.x);
                stmt.bind(5, cell.cellKey.y);
                ubyte[] blob = cell.serializeBlob();
                stmt.bind(6, blob);
                stmt.execute();
                stmt.reset();
            }
        }
    }
}

long reinterpLong (ref ulong v) {
    auto ptr = &v;
    return *(cast(long*)ptr);
}
