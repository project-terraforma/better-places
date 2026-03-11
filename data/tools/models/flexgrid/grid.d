module models.flexgrid.grid;
import models.flexgrid.key;
import models.flexgrid.flexgeo;
import models.flexgrid.serio;
import models.flexgrid.flexobject;
import std;

struct FlexCellId {
    union {
        ulong[2]        value = 0;
        struct {
            FlexCell    cell;
            uint        id;
            GeoType     geoType;
        }
    }
    @property FlexCellKey  key () { return cell.cellKey; }
    @property UUID        uuid () { return cell.getUUID(id); }
    @property AABB      bounds () { return cell.getBounds(id); }
    @property bool   hasBounds () { return cell.hasBounds(id); }

    this (FlexCell cell, uint cellLocalId, GeoType geoType) {
        this.cell    = cell;
        this.id      = cellLocalId;
        this.geoType = geoType;
    }
}

class FlexCell {
public:
    struct Data {
        FlexGrid                    grid;
        FlexCellKey                 cellKey;
        uint                        layer;

        UUID[uint]                  ids;
        uint[UUID]                  idsByUUID;
        TAABB!(PolarNorm)[uint]     geoBounds;
        FlexGeo[uint]               geo;
        TPoint!(PolarNorm)[uint]    points;

        CellObjectStore             objects;

        // nonzerialized
        JSONValue[uint]             decodedProps;
        string[uint]                rawProps;

        // optional
        FlexGeo                     mergedGeometry;
        FlexGeo                     mergedPoints;

        // nonserialized
        uint                        nextIndex = 0;

        AABB                        bounds;
        bool                        dirtyBounds = true;
    }
    struct Value {
        FlexCellId                  cellId; alias cellId this;
        @property FlexGeo* geometry () { return id in cell.geo; }
        @property Point*      point () { return id in cell.points; }
        FlexObject object (TObject = FlexObject)()
            if (is(TObject == class) && is(TObject : FlexObject))
        {
            FlexObject* o = id in cell.objects;
            return o ? cast(TObject)(*o) : null;
        }
        @property JSONValue* props () { return cell.tryGetProps(id); }
    }

    Data data; alias data this;
    this (FlexGrid intoGrid, FlexCellKey key, uint layer) {
        this.grid = intoGrid;
        this.cellKey = key; this.layer = layer;
        auto b = key.bounds;
        this.bounds = AABB(key.bounds.minv,key.bounds.minv);
    }

    // @property AABB bounds () const { return cellKey.bounds; }
    @property auto level () const { return cellKey.level; }

    @property AABB boundsPolarNorm () const { return cellKey.boundsPolarNorm; }
    @property AABB boundsPolarDeg () const { return cellKey.boundsPolarDeg; }

    UUID getUUID (uint localId) {
        auto existing = localId in this.ids;
        enforce(existing, "no id corresponding to '%s'".format(localId));
        return *existing;
    }
    bool hasBounds (uint id) {
        return (id in geoBounds) !is null || (id in geo) !is null;
    }

    auto getId (uint localId) {
        auto id = localId in this.ids;
        auto g = localId in this.geo;
        auto p = g ? null : localId in this.points;
        enforce(id !is null || g !is null, "invalid id '%s'".format(localId));
        auto geoType = g ? g.getType : p ? GeoType.Point : GeoType.None;
        return FlexCellId(this, localId, geoType);
    }

    AABB getBounds (uint id) {
        auto existing = id in geoBounds;
        if (existing) return *existing;

        auto geo = id in geo;
        enforce(geo, "No geometry found for id %s in %s!".format(id, cellKey));
        return geo.bounds;
    }
    JSONValue* tryGetProps (uint id) {
        auto existing = id in decodedProps;
        if (existing) return existing;
        auto raw = id in rawProps;
        if (raw) {
            import std.json;
            auto decodedJson = (*raw).parseJSON;
            decodedProps[id] = decodedJson;
            return id in decodedProps;
        }
        return null;
    }
    uint getOrInsertId (UUID uuid) {
        auto existing = uuid in idsByUUID;
        if (existing) {
            assert(*existing in ids);
            assert(ids[*existing] == uuid);
            return *existing;
        } else {
            auto next = nextIndex++;
            idsByUUID[uuid] = next;
            ids[next] = uuid;
            return next;
        }
    }
    void addPoint (UUID uuid, Point p) {
        auto id = getOrInsertId(uuid);
        points[id] = p;
        data.bounds.grow(p);
    }
    void addGeometry (UUID uuid, FlexGeo g) {
        auto id = getOrInsertId(uuid);
        geo[id] = g;
        data.bounds.grow(g.bounds);
    }
    void addGeometry (TGeometry)(UUID uuid, TGeometry g) {
        addGeometry(uuid, g.toFlexGeo());
    }

    // void insert (UUID uuid, FlexObject object) {
    //     auto id = getOrInsertId(uuid);
    //     objects[id] = object;
    // }
    // void insert (TObject)(UUID uuid, TObject object)
    //     if (is(TObject : FlexObject))
    // {
    //     insert(uuid, cast(FlexObject)object);
    // }
}
interface IFlexCellFactory {
    FlexCell create (FlexGrid grid, FlexCellKey key, uint layer);
}
class BasicCellFactory : IFlexCellFactory{
public:
    override FlexCell create (FlexGrid grid, FlexCellKey key, uint layer) {
        return new FlexCell(grid, key, layer);
    }
}

class FlexGrid {
    struct Layer {
        FlexCell[FlexCellKey]   cells;
        FlexIndex[FlexCellKey]  cellIndexes;
        uint   id;
        string name;

        this (uint id, string name) {
            this.id = id; this.name = name;
        }

        FlexCell getOrCreateCell(FlexGrid grid, FlexCellKey key, uint layer) {
            auto cell = key in this.cells;
            if (cell) return *cell;
            FlexCell newCell = grid.cellFactory.create(grid, key, layer);
            cells[key] = newCell;
            cellIndexes.updateCellCreated(key);
            return newCell;
        }
    }
    Layer[uint]                 layers;
    uint[string]                layersByName;
    uint                        nextLayerId = 0;

    import msgpack: serializedAs;
    @serializedAs!NotSerialized
    FlexObject[UUID]            allObjectsCache;

    // FlexCell[FlexCellKey]  cells;
    // FlexIndex[FlexCellKey] cellIndexes;
    IFlexCellFactory       cellFactory;

    GlobalObjectCache       globalObjectCache;
public:
    this () { this.cellFactory = new BasicCellFactory(); }
    this (IFlexCellFactory factory) { this.cellFactory = factory; }

    void loadLayers (uint[string] newLayers) {
        writefln("inserting %s layers", newLayers.length);
        foreach (kv; newLayers.byKeyValue) {
            if (kv.value !in layers) {
                writefln("inserting layer '%s' = %s", kv.key, kv.value);
                layers[kv.value] = Layer(kv.value, kv.key);
            }
            if (kv.key !in layersByName) {
                writefln("setting layer name '%s' => %s", kv.key, kv.value);
                layersByName[kv.key] = kv.value;
            }
            if (kv.value >= nextLayerId) {
                nextLayerId = kv.value = + 1;
            }
        }
    }
    void preload (FlexCellKey key, uint layer) {
        getOrCreateCell(key, layer);
    }
    void load (FlexCellKey key, uint layer, ubyte[] data) {
        getOrCreateCell(key, layer).load(data);
    }

    uint createNewLayer (string layerName) {
        if (layerName in layersByName) return layersByName[layerName];
        auto newLayer = nextLayerId++;
        while (newLayer in layers) {
            newLayer = nextLayerId++;
        }
        layers[newLayer] = Layer(newLayer, layerName);
        layersByName[layerName] = newLayer;
        return newLayer;
    }

    Layer* tryGetLayer(uint layer) {
        return layer in this.layers;
    }
    Layer* tryGetLayer(string layerName) {
        auto layerId = layerName in layersByName;
        return layerId ? tryGetLayer(*layerId) : null;
    }
    ref Layer getOrCreateLayer(string layerName) {
        auto layerId = layerName in layersByName;
        if (layerId !is null) return layers[*layerId];
        auto newId = createNewLayer(layerName);
        return layers[newId];
    }
    FlexCell getOrCreateCell(FlexCellKey key, uint layer) {
        auto l = layer in this.layers;
        enforce(l, "unknown layer '%s'".format(layer));
        return l.getOrCreateCell(this, key, layer);
    }
    void visitInsert (alias visitorDg)(FlexCellKey key) {
        visitorDg(getOrCreateCell(key));
    }
    void visitCells (alias visitorDg, bool parallel = true)(AABB bounds) {
        FlexVisitKey visitKey = FlexVisitKey(bounds);
        foreach (levelVisitor; visitKey.byLevel) {
            foreach (indexKey; levelVisitor.byIndex) {
                auto index = indexKey.key in this.cellIndexes;
                if (index is null) continue;
                foreach (cellKey; indexKey.byCells(*index)) {
                    auto cell = cellKey in this.cells;
                    if (cell) { visitorDg(*cell); }
                }
            }
        }
    }
    void visitCells (AABB bounds, void delegate(FlexCell) visitorDg) {
        auto key = FlexCellKey.from(bounds);
        // writefln("want to visit %s\n\t=> %s", bounds, key);
        // FlexVisitKey visitKey = FlexVisitKey(bounds);
        // foreach (levelVisitor; visitKey.byLevel) {
        //     foreach (indexKey; levelVisitor.byIndex) {
        //         auto index = indexKey.key in this.cellIndexes;
        //         if (index is null) continue;
        //         foreach (cellKey; indexKey.byCells(*index)) {
        //             auto cell = cellKey in this.cells;
        //             if (cell) { visitorDg(*cell); }
        //         }
        //     }
        // }
    }
    auto findObject (UUID uuid) { return globalObjectCache.findObject(uuid); }
}
struct FlexPoint {
    FlexCellKey key;
    float       relX, relY;
}


// class FlexView : FlexObject {
//     string              name;
//     string              description;
//     FlexObject[UUID]    items;
// }
struct FlexIndex {}
void updateCellCreated(ref FlexIndex[FlexCellKey] index, FlexCellKey key) {

}

struct Reference(T) if (is(T : FlexObject)) {
    UUID        uuid;
    T           directReference;
    bool        loaded = false;

    this (T obj)
        in { assert(obj !is null); }
        do { uuid = obj.uuid; directReference = obj; }

    T get (FlexGrid grid)
        in { assert(grid !is null); }
        do {
            if (directReference is null) {
                directReference = grid.findObject(uuid).asObjectType!T;
            }
            return directReference;
        }

    @property bool isLoaded () { return directReference !is null; }
}
Reference!T refOf (T)(T obj)
    if (is(T : FlexObject))
    in { assert(obj !is null); }
    do {
        return Reference!T(obj);
    }

struct ReferenceSet(T) if (is(T : FlexObject)) {
    alias This = ReferenceSet!(T);
    alias HashMap = T[UUID];
    HashMap                         store;

    T tryGet (UUID uuid, FlexGrid grid) {
        T* ptr = uuid in store;
        if (!ptr) return null;
        if (*ptr is null) {
            T found = grid.findObject(uuid).asObjectType!T;
            *ptr = found;
            return found;
        }
        return *ptr;
    }
    FwdRange iter (FlexGrid grid) { return FwdRange(this, grid); }
    size_t length () { return store.length; }

    struct FwdRange {
        alias Iter = typeof(HashMap.init.byKeyValue);
        private This* set;
        private Iter iter;
        FlexGrid grid;

        this(ref This set, FlexGrid grid) { this.set = &set; this.iter = set.store.byKeyValue; advanceToNextValid(); }
        private void advanceToNextValid() {
            for (; !iter.empty; iter.popFront) {
                if (iter.front.value is null) {
                    auto found = grid.findObject(iter.front.key).asObjectType!T;
                    if (!found) continue; // skip missing
                    else {
                        set.store[iter.front.key] = found;
                        iter.front.value = found;
                        break;
                    }
                } else break;
            }
        }
        auto front () { return iter.front; }
        auto empty () { return iter.empty; }
        void popFront ()
            in { assert(!empty); }
            do {
                iter.popFront();
                advanceToNextValid();
            }
        auto save () { return this; }
    }
}
