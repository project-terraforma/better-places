module models.geometry.polygons;
import models.geometry.point;
public import std.variant;
import std;

struct TRing    (U=DefaultUnit) { TPoint!U[] points; }
struct TPolygon (U=DefaultUnit) { TRing!U[] rings; }
struct TMultiPolygon (U=DefaultUnit) { TPolygon!U[] polygons; }
struct TGeometry (U=DefaultUnit) {
    import models.geometry.bounds: TAABB;
    alias Point = TPoint!U;
    alias AABB = TAABB!U;
    alias Ring = TRing!U;
    alias Polygon = TPolygon!U;
    alias MultiPolygon = TMultiPolygon!U;
    alias Geometry = Algebraic!(
        Point, Polygon, MultiPolygon
    );
    Geometry geometry;
    alias geometry this;

    this (Point p) { this.geometry = Geometry(p); }
    this (Polygon p) { this.geometry = Geometry(p); }
    this (MultiPolygon p) { this.geometry = Geometry(p); }

    @property auto ref value () { return geometry; }
}
