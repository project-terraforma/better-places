module models.flexgrid;
import models.geometry;
import std;

enum MAX_LEVEL = 14;

struct FlexCellKey {
    alias This = FlexCellKey;
    union {
        ulong value;
        Fields fields;
    }
    struct Fields {
        mixin(bitfields!(
            uint, "x", 30,
            uint, "y", 30,
            ubyte, "level", 4,
        ));
    }
    private this (uint x, uint y, ubyte level)
        in { assert(level <= MAX_LEVEL); }
        do {
            uint LEVEL_MASK = (1U << cast(uint)(level+level)) -1U;
            this.x = x &= LEVEL_MASK;
            this.y = y &= LEVEL_MASK;
            this.level = level;
        }

    static ubyte getLevel (AABB bounds) {
        auto maxSpan = max(
            bounds.maxv.x - bounds.minv.x,
            bounds.maxv.y - bounds.minv.y
        ) * (1/360.0);
        uint level = MAX_LEVEL;
        enum MAX_DIV = 1.0/(1U << (MAX_LEVEL*2));
        enum NDIVS   = 1LU << (MAX_LEVEL*2);
        ulong dspan = cast(ulong)(maxSpan * NDIVS);
        ulong divsz = 1;
        while (level && dspan > divsz) {
            ++level; divsz *= 4;
        }
        // double div = MAX_DIV;
        // while (level && maxSpan > div) {
        //     ++level; div *= 4;
        // }
        return level;
    }
    static FlexCellKey from (Point point, ubyte level) {
        // normalize point from polar degrees to polar norm [0,1]
        point.x *= (1/360.0);
        point.y *= (1/360.0);
        uint ndivs = (1<<cast(uint)(level+level));
        uint mask  = ndivs-1;
        double fmult = (1.0/cast(double)ndivs);

        if (point.x < 1) point.x += 0.5;
        if (point.y < 1) point.y += 0.5;

        uint x = cast(uint)(point.x) & mask;
        uint y = cast(uint)(point.y) & mask;
        return This(x, y, level);
    }
    FlexCellKey from (Point point) { return from(point, MAX_LEVEL); }
    FlexCellKey from (AABB bounds) { return from(bounds.minv, getLevel(bounds)); }

    @property Point minCoordPolarNorm () const {
        auto l = cast(ulong)(level);
        auto frac = 1.0 / cast(double)(1U << (l+l));
        return Point( x * frac, y * frac );
    }
    @property double sizePolarNorm () const {
        auto l = cast(ulong)(level);
        return cast(double)(1LU << (l+l));
    }
    @property AABB boundsPolarNorm () const {
        auto minv = minCoordPolarNorm();
        auto sz = sizePolarNorm();
        return AABB(minv, Point(minv.x + sz, minv.y + sz));
    }

    @property Point minCoordPolarDeg () const { return (minCoordPolarNorm() - 0.5) * 360.0; }
    @property AABB  boundsPolarNorm  () const { return (boundsPolarNorm() - 0.5) * 360.0; }
}

class FlexCell {
    FlexCellKey         cellKey;
    FlexGeo[UUID]       geometry;
    FlexPoint[UUID]     points;
    FlexObject[UUID]    objects;
    FlexView[UUID]      views;
    FlexView[string]    viewsByName;
public:
    @property AABB boundsPolarNorm () const { return cellKey.boundsPolarNorm; }
    @property AABB boundsPolarDeg () const { return cellKey.boundsPolarDeg; }
    this (FlexCellKey key) { this.key = cellKey; }
}
interface IFlexCellFactory {
    FlexCell create (FlexGrid grid, FlexCellKey key);
}
class FlexGrid {
    FlexCell!ulong  cells;
    FlexIndex!ulong cellIndexes;
    IFlexCellFactory cellFactory;
public:
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
