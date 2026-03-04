module models.geometry.bounds;
public import models.geometry.point;
public import models.geometry.units;
import models.geometry.polygons;
import std;

struct TAABB(U=DefaultUnit) {
    alias Point = TPoint!U;
    alias Ring = TRing!U;
    alias Polygon = TPolygon!U;
    alias MultiPolygon = TMultiPolygon!U;
    alias AABB = TAABB!U;
    alias This = AABB;
    alias Unit = U;

    Point minv, maxv;
    this (Point p1, Point p2)
        in {
            assert(!(p1.x.isNaN || p1.y.isNaN
                || p2.x.isNaN || p2.y.isNaN));
        } do {
            // guess, and attempt to assign these optimally
            // with what should be cmov etc
            auto minx = p1.x, miny = p1.y;
            auto maxx = p2.x, maxy = p2.y;

            if (p2.x < minx) minx = p2.x;
            if (p2.y < miny) miny = p2.y;
            if (p1.x > maxx) maxx = p1.x;
            if (p1.y > maxy) maxy = p1.y;
            // this.minv = Point(min(p1.x, p2.x), min(p1.x, p2.x));

            this.minv = Point(minx, miny);
            this.maxv = Point(maxx, maxy);
        }

    this (Point p) {
        this.minv = this.maxv = p;
    }
    void toString (scope void delegate(scope const(char)[]) sink) {
        char[256] buf = void;
        sink(buf.sformat("AABB(%s)(", U.stringof));
        sink(buf.sformat("min=(%s,%s)", minv.x, minv.y));
        sink(buf.sformat(", max=(%s,%s)", maxv.x, maxv.y));
        auto c = this.center;
        sink(buf.sformat(", center=(%s,%s)", c.x, c.y));
        auto s = this.size;
        sink(buf.sformat(", size=(%s,%s))", s.x, s.y));
    }

    @property Point size () const { return maxv - minv; }
    Point center () const { return (maxv + minv) * 0.5; }

    This opBinary (string op,U2)(const TPoint!(U2) rhs) const {
        static if (op == "+" || op == "-" || op == "*" || op == "/") {
            return This(
                mixin("minv"~op~"rhs"),
                mixin("maxv"~op~"rhs")
            );
        } else static assert(false, "invalid operator "~s);
    }
    This opBinary (string op)(Point.T scalar) const {
        static if (op == "+" || op == "-" || op == "*" || op == "/") {
            return This(
                mixin("minv"~op~"scalar"),
                mixin("maxv"~op~"scalar")
            );
        } else static assert(false, "invalid operator "~s);
    }

    this (Ring r) { assign(r); }
    this (Polygon r) { assign(r); }
    this (MultiPolygon r) { assign(r); }

    void grow (Point p) {
        if (p.x < minv.x) minv.x = p.x;
        else if (p.x > maxv.x) maxv.x = p.x;

        if (p.y < minv.y) minv.y = p.y;
        else if (p.y > maxv.y) maxv.y = p.y;
    }
    void grow (Point[] r) { foreach (p; r) { grow(p); } }
    void grow (Ring r)    { grow(r.points); }
    void grow (Polygon p) { foreach (r; p.rings) { grow(r); } }
    void grow (MultiPolygon mp) { foreach (p; mp.polygons) { grow(p); } }

    void assign (Ring r)
        in { assert(r.points.length > 0); }
        do {
            this.minv = this.maxv = r.points[0];
            grow(r.points[1..$]);
        }
    void assign (Polygon p)
        in { assert(p.rings.length >= 1); assert(p.rings[0].points.length >= 1); }
        do {
            assign(p.rings[0]);
            if (p.rings.length > 1) foreach (r; p.rings[1..$]) grow(r);
        }
    void assign (MultiPolygon mp)
        in { assert(mp.polygons.length >= 1); assert(mp.polygons[0].rings.length >= 1); }
        do {
            assign(mp.polygons[0]);
            if (mp.polygons.length > 1) foreach (p; mp.polygons[1..$]) grow(p);
        }
    This scaledAroundCenter (double scaleX, double scaleY) const {
        auto s = size();
        auto c = center();
        s.x *= scaleX;
        s.y *= scaleY;
        return AABB(
            Point(c.x - s.x * 0.5, c.y - s.y * 0.5),
            Point(c.x + s.x * 0.5, c.y + s.y * 0.5),
        );
    }
    This scaledAroundCenter(Point scale) const {
        return scaledAroundCenter(scale.x, scale.y);
    }
    This scaledAroundCenter(double scale) const {
        return scaledAroundCenter(scale, scale);
    }
    This boundsShapeIntersect (This other) const {
        return This(
            Point(
                max(minv.x, other.minv.x),
                max(minv.y, other.minv.y)
            ),
            Point(
                min(maxv.x, other.maxv.x),
                min(maxv.y, other.maxv.y)
            )
        );
    }
    This clip (This other) const { return this.boundsShapeIntersect(other); }

    auto to (U2)() {
        static if (is(U == U2) || is(U2 == This)) { return this; }
        else static if (__traits(compiles, TAABB!(U2.Unit))) {
            return TAABB!(U2.Unit)(
                this.minv.to!(U2.Unit),
                this.maxv.to!(U2.Unit)
            );
        } else {
            return TAABB!U2(this.minv.to!U2, this.maxv.to!U2);
        }
    }
}
