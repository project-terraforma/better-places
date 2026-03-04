module models.flexgrid.key;
public import models.flexgrid.common;
import std;

enum MAX_LEVEL = 14;

struct FlexCellKey {
    alias This = FlexCellKey;
    union {
        ulong value;
        Fields fields;
    }
    alias fields this;
    struct Fields {
        mixin(bitfields!(
            uint, "x", 30,
            uint, "y", 30,
            ubyte, "level", 4,
        ));
    }
    private this (uint x, uint y, ubyte level)
        in { assert(level <= MAX_LEVEL, "invalid level %s (max %s)".format(level, MAX_LEVEL)); }
        do {
            uint LEVEL_MASK = (1U << cast(uint)(level+level)) -1U;
            this.x = x & LEVEL_MASK;
            this.y = y & LEVEL_MASK;
            this.level = level;
        }

    ulong opHash () {
        return value;
    }
    void toString (scope void delegate(scope const(char)[]) sink) {
        char[512] buf;
        auto b = bounds;
        sink(buf.sformat("FlexCellKey(\n\tid=0x%x, \n\tlevel=%s, x=%s, y=%s, \n\tbounds=\n\t\t%s, \n\t\t%s, \n\t\t%s)"
            , value
            , level, x, y
            , b
            , b.to!PolarDeg
            , b.to!Meters
        ));
    }
    static ubyte getLevel (TAABB!PolarNorm bounds) {
        // auto maxSpan = bounds.size();
        auto maxSpan = max(
            bounds.maxv.x - bounds.minv.x,
            bounds.maxv.y - bounds.minv.y
        );// * (1/360.0);
        uint level = MAX_LEVEL;
        enum MAX_DIV = 1.0/(1U << (MAX_LEVEL*2));
        enum NDIVS   = 1LU << (MAX_LEVEL*2);
        ulong dspan = cast(ulong)(maxSpan * NDIVS);
        ulong divsz = 1;

        // writefln("GET_LEVEL(%s => %s) (%s, %s)", bounds.size, maxSpan, bounds.size.to!Meters, bounds.size.to!PolarDeg);
        // writefln("MAX_DIV = %s, NDIVS = %s", MAX_DIV, NDIVS);
        // writefln("dspan = %s", dspan);
        while (level && dspan > divsz) {
            --level; divsz *= 4;
        }
        // writefln("found threshold at level = %s, divsz = %s", level, divsz);
        // double div = MAX_DIV;
        // while (level && maxSpan > div) {
        //     ++level; div *= 4;
        // }
        return cast(ubyte)level;
    }
    static FlexCellKey from (TPoint!PolarNorm point, ubyte level) {
        // normalize point from polar degrees to polar norm [0,1]
        // point.x *= (1/360.0);
        // point.y *= (1/360.0);
        uint ndivs = (1<<cast(uint)(level+level));
        uint mask  = ndivs-1;
        double fmult = cast(double)ndivs;

        if (point.x < 1) point.x += 0.5;
        if (point.y < 1) point.y += 0.5;

        // writefln("FLEXCELLKEY %s * %s => %s", fmult, point, point * fmult);
        uint x = cast(uint)(point.x * fmult) & mask;
        uint y = cast(uint)(point.y * fmult) & mask;
        // writefln(" =>&(%s) => %s, %s", mask, x, y);
        return This(x, y, level);
    }
    static FlexCellKey from (TPoint!PolarNorm point) { return from(point, MAX_LEVEL); }
    static FlexCellKey from (TAABB!PolarNorm bounds) { return from(bounds.minv, getLevel(bounds)); }

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
    @property AABB boundsPolarDeg  () const { return (boundsPolarNorm() - 0.5) * 360.0; }
    @property AABB bounds () const { return boundsPolarNorm(); }
}
