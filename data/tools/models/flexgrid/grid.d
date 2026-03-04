module models.flexgrid.grid;
import models.flexgrid.key;
import std;

class FlexCell {
    FlexCellKey         cellKey;
    FlexGeo[UUID]       geometry;
    FlexPoint[UUID]     points;
    FlexObject[UUID]    objects;
    FlexView[UUID]      views;
    FlexView[string]    viewsByName;
public:
    this (FlexGrid intoGrid, FlexCellKey key) { this.cellKey = key; }

    @property AABB bounds () const { return cellKey.bounds; }
    @property auto level () const { return cellKey.level; }

    @property AABB boundsPolarNorm () const { return cellKey.boundsPolarNorm; }
    @property AABB boundsPolarDeg () const { return cellKey.boundsPolarDeg; }
    this (FlexCellKey key) { this.cellKey = key; }
}
interface IFlexCellFactory {
    FlexCell create (FlexGrid grid, FlexCellKey key);
}
class BasicCellFactory : IFlexCellFactory{
public:
    override FlexCell create (FlexGrid grid, FlexCellKey key) {
        return new FlexCell(grid, key);
    }
}

class FlexGrid {
    FlexCell[FlexCellKey]  cells;
    FlexIndex[FlexCellKey] cellIndexes;
    IFlexCellFactory cellFactory;
public:
    this () { this.cellFactory = new BasicCellFactory(); }
    this (IFlexCellFactory factory) { this.cellFactory = factory; }

    FlexCell getOrCreateCell(FlexCellKey key) {
        auto cell = key in this.cells;
        if (cell) return *cell;
        FlexCell newCell = cellFactory.create(this, key);
        cells[key] = newCell;
        cellIndexes.updateCellCreated(key);
        return newCell;
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
}


struct FlexPoint {
    FlexCellKey key;
    float       relX, relY;
}
struct FlexGeo {
    FlexCellKey key;
    float[]     relPoints;
    FlexPrim[]  flexPrims;

    struct FlexPrim {
        enum Type : ubyte {
            Bounds          = 0,
            NextPrimBounds  = 1,
            RingOuter       = 2,
            RingInner       = 3,
            Line            = 4,
        }
        union {
            u32 packedValue;
            Fields fields;
        }
        struct Fields {
            mixin(bitfields!(
                u32,  "count",  28,
                Type, "type",   4,
            ));
        }
    }
}
class FlexObject {}

class FlexView : FlexObject {
    string              name;
    string              description;
    FlexObject[UUID]    items;
}
struct FlexIndex {}
void updateCellCreated(ref FlexIndex[FlexCellKey] index, FlexCellKey key) {

}
