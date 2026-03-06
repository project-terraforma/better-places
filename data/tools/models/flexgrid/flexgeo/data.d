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


bool isData      (GeoType g) { return g >= GeoType.RingOuter && g <= GeoType.Point; }
bool isContainer (GeoType g) { return g >= GeoType.Polygon; }

enum PrimType { RingPoints, LinePoints, PointCloudPoints }
struct Prim {
    PrimType type;
    Point[] points;
}
struct TaggedPrim {
    Prim prim; alias prim this;
    long _index = -1;
    long _tag = -1;
    FlexGeo* geo;
    FlexCell cell;

    @property bool hasId () { return _index >= 0; }
    @property auto id ()
        in { assert(hasId); assert(cell); }
        do { return cell.getId(cast(uint)_index); }
    // @property auto id () { return _index >= 0 && cell !is null ? cell.getId(cast(uint)_index) : null; }
    // @property string* tag () { return _tag >= 0 && geo !is null ? geo.getTag(cast(uint)_tag) : null; }
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
