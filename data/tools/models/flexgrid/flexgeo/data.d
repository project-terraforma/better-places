module models.flexgrid.flexgeo.data;
import models.geometry.units;
import models.geometry.point;
import models.geometry.bounds;
import models.geometry.polygons;
import models.flexgrid.grid;
import std.bitmanip : bitfields;
import std;

// ─── Type tags ────────────────────────────────────────────────────────────────
alias Point = TPoint!PolarNorm;
alias AABB = TAABB!PolarNorm;

/// Geometry type tag. Fits in 4 bits (0–15).
enum GeoType : ubyte {
    None        = 0,
    Id          = 1,
    Tag         = 2,
    Bounds      = 3,

    RingOuter   = 0x8,
    RingInner   = 0x9,
    Points      = 0xA,
    Point       = 0xB,

    Polygon     = 0xC,
    Line        = 0xD,
    PointCloud  = 0xE,
}
enum GeoMetaType : ubyte {
    Tag = 0, Metadata = 1, Geometry = 2, Structural = 3
}
GeoMetaType metaType (GeoType t) { return cast(GeoMetaType)((cast(size_t)t) >> 2); }
GeoMetaType metaType (Entity e) { return e.type.metaType; }

bool isData      (GeoType g) { return g >= GeoType.RingOuter && g <= GeoType.Point; }
bool isContainer (GeoType g) { return g >= GeoType.Polygon; }

enum PrimType { RingPoints, LinePoints, PointCloudPoints }

PrimType primType (GeoType type) {
    switch (type) {
        case GeoType.RingOuter: case GeoType.RingInner: return PrimType.RingPoints;
        case GeoType.Points: return PrimType.LinePoints;
        case GeoType.Point: return PrimType.PointCloudPoints;
        default: assert(false, "invalid type %s".format(type)); assert(0);
    }
}

struct Prim {
    Point[] points;
    GeoType  type;
}
struct TaggedPrim {
    private Point* _bounds = null;
    private long _index = -1;
    Prim prim; alias prim this;

    this (GeoType geoType, Point[] points, Point* optBounds, long optId) {
        this.prim = Prim(points, geoType);
        this._bounds = optBounds;
        this._index = optId;
    }
    @property bool hasId () { return _index >= 0; }
    @property auto id ()
        in { assert(hasId); }
        do { return cast(uint)_index; }

    @property bool hasBounds () { return _bounds !is null; }
    @property AABB bounds ()
        in { assert(hasBounds); }
        do { return AABB(_bounds[0], _bounds[1]); }
}

struct Entity {
    union { uint value = 0; Fields fields; }
    alias fields this;
    struct Fields {
        mixin(bitfields!(
            GeoType,  "type",      5,
            uint,     "payload",   26,
            bool,     "isCont",    1,
        ));
    }
    this (GeoType t, uint n = 0) {
        this.type = t;
        this.payload = n;
    }
    void toString (scope void delegate(scope const(char)[]) sink) {
        char[512] buf;
        sink(buf.sformat("Entity.%s(%s)", type, payload));
    }
}
struct FlexGeo {
    Entity[]        entities;
    Point[]         points;
    AABB            bounds;
    string[uint]    tags;
    uint            nextTag;

    // PolyFwdRange        polygons    () { return PolyFwdRange(this); }
    // LineFwdRange        lines       () { return LineFwdRange(this); }
    // PointCloudFwdRange  pointClouds () { return PointCloudFwdRange(this); }

    uint newTag (string tag) {
        auto nextId = nextTag++;
        tags[nextId] = tag;
        return nextId;
    }
    // string  getTag (uint tag) {}
    GeoType getType () {
        foreach (ent; entities) {
            if (ent.type > GeoType.Bounds) {
                return ent.type;
            }
        }
        return GeoType.None;
    }
}
