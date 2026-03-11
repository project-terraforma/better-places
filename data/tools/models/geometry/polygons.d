module models.geometry.polygons;
import models.geometry.point;
public import std.variant;
import std;

struct TRing    (U=DefaultUnit) { TPoint!U[] points; }
struct TPolygon (U=DefaultUnit) { TRing!U[] rings; }
struct TMultiPolygon (U=DefaultUnit) { TPolygon!U[] polygons; }
struct TLineString    (U=DefaultUnit) { TPoint!U[] points; }

struct TGeometry (U=DefaultUnit) {
    import models.geometry.bounds: TAABB;
    alias Point = TPoint!U;
    alias AABB = TAABB!U;
    alias Ring = TRing!U;
    alias Polygon = TPolygon!U;
    alias MultiPolygon = TMultiPolygon!U;
    // alias Line = TLine!U;
    alias LineString = TLineString!U;
    alias Geometry = Algebraic!(
        Point, Polygon, MultiPolygon, LineString
    );
    Geometry geometry;
    alias geometry this;

    this (Point p) { this.geometry = Geometry(p); }
    this (Polygon p) { this.geometry = Geometry(p); }
    this (MultiPolygon p) { this.geometry = Geometry(p); }
    // this (Line p) { this.geometry = Geometry(p); }
    this (LineString p) { this.geometry = Geometry(p); }

    @property auto ref value () { return geometry; }
}
