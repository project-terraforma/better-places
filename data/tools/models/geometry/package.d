module models.geometry;
import models.utils;
public import std.variant;
import std.math: isNaN;
import std.format: format;
import std.exception: enforce;

struct Point { float x = 0, y = 0; }
struct Ring  { Point[] points; }
struct Polygon { Ring[] rings; }
struct MultiPolygon { Polygon[] polygons; }
alias Geometry = Algebraic!(Point, Polygon, MultiPolygon);

struct AABB {
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
}
bool contains (AABB bounds, Point p) {
    return !(
        p.x < bounds.minv.x || p.x > bounds.maxv.x ||
        p.y < bounds.minv.y || p.y > bounds.maxv.y
    );
}
bool contains (Ring r, Point p) {
    // TODO: raycast algorithm
    return false;
}
bool contains (Polygon r, Point p) {
    assert(r.rings.length >= 1);
    assert(r.rings.length == 1, "'ve have found 'ze ring edgecase! %s".format(r));

    // outer is ring 0
    if (!r.rings[0].contains(p)) return false;

    // all other rings are inner??
    foreach (inner; r.rings[1..$]) {
        if (inner.contains(p)) return false;
    }
    return true;
}
bool contains (MultiPolygon r, Point p) {
    foreach (poly; r.polygons) {
        if (poly.contains(p)) return true;
    }
    return false;
}
bool contains (Geometry g, Point p) {
    return g.visit!(
        (Point _) { assert(false, "invalid cannot do Point/Point contains() operation"); assert(0); return false; },
        (Polygon r) => r.contains(p),
        (MultiPolygon r) => r.contains(p)
    );
}
bool contains (TGeometry)(AABB bounds, TGeometry geometry, Point p) {
    return bounds.contains(p) && geometry.contains(p);
}
