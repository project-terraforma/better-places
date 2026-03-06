module models.flexgrid.flexgeo.conv;
import models.flexgrid.flexgeo.data;
import models.geometry.units;
import models.geometry.polygons;
import models.geometry.bounds;

alias Point = models.flexgrid.flexgeo.data.Point;
alias AABB = models.flexgrid.flexgeo.data.AABB;

FlexGeo toFlexGeo (U)(TMultiPolygon!U p, uint* optId = null, string tag = null) {
    FlexGeoBuilder b;
    if (optId) b.annotateId(*optId);
    if (tag) b.annotateTag(tag);
    b.add(p, true);
    return b.build();
}
FlexGeo toFlexGeo (U)(TPolygon!U p, uint* optId = null, string tag = null) {
    FlexGeoBuilder b;
    if (optId) b.annotateId(*optId);
    if (tag) b.annotateTag(tag);
    b.add(p, true);
    return b.build();
}
FlexGeo toFlexGeo (U)(TGeometry!U g, uint* optId = null, string tag = null) {
    FlexGeoBuilder b;
    if (optId) b.annotateId(*optId);
    if (tag) b.annotateTag(tag);
    g.tryVisit(
        (TPolygon!U p) => b.add(p),
        (TMultiPolygon!U p) => b.add(p),
        (_) { assert(false, "unsupported!"); }
    );
    return b.build();
}
struct FlexGeoBuilder {
    FlexGeo g;
    struct EntityBuildInfo {
        uint    entity;
        uint    boundsIndex = uint.max;
        AABB    bounds;
        bool    hasSetBounds = false;
    }
    EntityBuildInfo[] stack;

    FlexGeo build () { finalize(); return g; }
    void finalize () {
        assert(stack.length == 0);
    }
    void annotateId(uint id) { g.entities ~= Entity(GeoType.Id, id); }
    void annotateTag(string tag) { g.entities ~= Entity(GeoType.Tag, g.newTag(tag)); }

    void begin (GeoType t, bool addBounds) {
        uint bounds = addBounds ? createBounds() : uint.max;
        g.entities ~= Entity(t);
        auto ent = g.entities.length - 1;
        stack ~= EntityBuildInfo(cast(uint)ent, bounds);
    }
    void end () {
        assert(stack.length);
        auto currentPos = g.entities.length - 1;
        auto tos = stack[$-1];
        assert(currentPos >= tos.entity);
        g.entities[tos.entity].payload = cast(uint)(currentPos - tos.entity);
        if (stack.length > 1) {
            if (stack[$-2].hasSetBounds) {
                stack[$-2].bounds.grow(tos.bounds);
            } else {
                stack[$-2].bounds = tos.bounds;
            }
        } else {
            g.bounds = stack[$-1].bounds;
        }
        stack.length -= 1;
    }
    uint createBounds () {
        auto b = g.entities.length;
        g.points ~= Point(0,0); g.points ~= Point(0,0);
        g.entities ~= Entity(GeoType.Bounds);
        return cast(uint)(g.entities.length - 1);
    }
    void add (U)(TMultiPolygon!U p, bool addBounds, bool addChildBounds = true) {
        if (p.polygons.length <= 1) {
            assert(p.polygons.length > 0);
            add(p.polygons[0], addBounds, addChildBounds);
        } else {
            begin(GeoType.Polygon, addBounds);
            foreach (poly; p.polygons) {
                add(poly, true, addChildBounds);
            }
            end();
        }
    }
    void add (U)(TPolygon!U p, bool addBounds, bool addChildBounds = true) {
        begin(GeoType.Polygon, addBounds);
        foreach (i, ring; p.rings) {
            assert(ring.points.length >= 1);
            if (i == 0) {
                begin(GeoType.RingOuter, addChildBounds);
            } else {
                begin(GeoType.RingInner, addChildBounds);
            }
            auto bounds = stack[$-1].bounds;
            foreach (k, point; ring.points) {
                Point pt = point.to!PolarNorm;
                g.points ~= pt;
                if (k > 0) {
                    bounds.grow(pt);
                } else {
                    bounds.minv = bounds.maxv = pt;
                }
            }
            stack[$-1].bounds = bounds;
            stack[$-1].hasSetBounds = true;
            end();
        }
        end();
    }
}
