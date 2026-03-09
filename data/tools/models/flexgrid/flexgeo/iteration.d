module models.flexgrid.flexgeo.iteration;
import models.flexgrid.flexgeo.data;
import models.geometry;
import models.geometry.algorithms;
import models.flexgrid.grid;
import std;

// iterates exclusively over primitive geometry types
struct GeoPrimIterator {
private:
    FlexGeo geo;
    size_t i = 0, gi = 0, n;
    long id = -1;
    Point* bounds = null;
public:
    this (FlexGeo g) {
        this.geo = g;
        this.n = g.entities.length;
        skipToNextPrim();
    }
    private void skipToNextPrim() {
        id = -1; bounds = null;
        for (; i < n; ++i) {
            auto t = geo.entities[i].type;
            if (t <= GeoType.Bounds) {
                switch (t) {
                    case GeoType.Bounds: bounds = geo.points.ptr + gi; gi += 2; break;
                    case GeoType.Id: id = cast(long)geo.entities[i].payload; break;
                    default:
                }
            } else {
                if (t >= GeoType.Polygon) {
                    // applies to a container object so ignore
                    id = -1; bounds = null;
                } else {
                    // RingOuter, RingInner, Points, Point
                    break;
                }
            }
        }
    }
    void popFront ()
        in { assert(!empty); assert(geo.entities[i].metaType == GeoMetaType.Geometry); }
        do { gi += geo.entities[i].payload; ++i; skipToNextPrim(); }
    bool empty () const { return i >= n; }
    TaggedPrim front () {
        auto entity = geo.entities[i];
        assert(entity.payload > 0, "zero length payload for entity %s (%s) in geometry\n\t%s\n\t%s"
            .format(entity.type, entity.payload, geo.points, geo.entities)
        );
        return TaggedPrim(
            entity.type,
            geo.points[gi .. gi + entity.payload],
            bounds,
            id);
    }
    auto save () { return this; }
}
GeoPrimIterator allGeoPrims (FlexGeo g) {
    return GeoPrimIterator(g);
}

bool rectContainsPoint (U)(TAABB!U rect, TPoint!U point) {
    return models.geometry.algorithms.contains(rect, point);
}
bool ringContainsPoint(U)(TPoint!U[] ringPoints, TPoint!U point) {
    return models.geometry.algorithms.contains(TRing!U(ringPoints), point);
}
alias pointWithinRadiusOf = models.geometry.algorithms.withinRadiusOf;

bool containsOrNearPoint (U=Meters)(FlexGeo g, Point p, TScalar!U nearPointOrLineThreshold) {
    bool containedInOuterRing = false;
    // rings: true iff hits outer ring AND NOT inner ring
    foreach (prim; GeoPrimIterator(g)) {
        switch (prim.type) {
            case GeoType.RingOuter:
                // any outer ring hit = can skip other outer rings, but need to check if any inner ring hit
                if (containedInOuterRing) continue;
                if (!prim.hasBounds || prim.bounds.rectContainsPoint(p)) {
                    containedInOuterRing = ringContainsPoint(prim.points, p);
                }
                break;
            case GeoType.RingInner:
                // any inner ring hit = false
                if (!prim.hasBounds || prim.bounds.rectContainsPoint(p)) {
                    if (ringContainsPoint(prim.points, p)) {
                        return false;
                    }
                }
                break;
            case GeoType.Line:
                if (!prim.hasBounds || prim.bounds.rectContainsPoint(p)) {
                    assert(false, "TODO!");
                }
                break;
            case GeoType.Point:
                foreach (point; prim.points) {
                    if (pointWithinRadiusOf(p, point, nearPointOrLineThreshold)) {
                        return true;
                    }
                }
                break;
            default: assert(0);
        }
    }
    return containedInOuterRing;
}




bool contains (AABB bounds, Point[] points) {
    foreach (pt; points) if (models.geometry.algorithms.contains(bounds, pt)) return true;
    return false;
}
bool contains (Prim prim, AABB bounds) {
    switch (prim.type) {
        case GeoType.RingOuter: case GeoType.RingInner: return bounds.contains(prim.points);
        case GeoType.Points: return bounds.contains(prim.points);
        case GeoType.Point: return bounds.contains(prim.points);
        default: assert(false, "invalid primitive for .contains(): %s".format(prim)); assert(0);
    }
}
struct ContainingBounds {
    AABB bounds;
    bool matches (AABB rect) { return models.geometry.algorithms.contains(rect, bounds); }
    bool matches (Prim prim) { return prim.contains(bounds); }
}
auto containingBounds (AABB bounds) { return ContainingBounds(bounds); }
// auto withinRadiusOf (TRadius = Scalar!Meters)(Point point, TRadius radius) {
//     return WithinRadiusOf!TRadius(point, radius);
// }
struct WithinRadiusOf (TRadius = Scalar!Meters) {
    Point   point;
    TRadius radius;
    bool matches (AABB rect) {
        writefln("check radius");
    return models.geometry.algorithms.withinRadiusOf(rect, point, radius); }
    bool matches (Prim prim) {
        foreach (pt; prim.points)
            if (models.geometry.algorithms.withinRadiusOf(pt, point, radius)) return true;
        return false;
    }
}
private bool matchesAnyPolygon (TQuery)(TQuery query, const(Entity)[] ents, ref const(Point)[] points) {
    const(Point)[] bounds = null;
    const(Point)[] geo = points;
    scope(exit) { points = geo; }

    bool hasOuterPolygonHit = false;
    size_t innerPolygonsCount = 0;

    enum INNER_POLYGONS_CACHED_MAX = 32;
    struct InnerPoly { const(Point)[] bounds, points; }
    InnerPoly[INNER_POLYGONS_CACHED_MAX] innerPolys = void;
    InnerPoly[] innerPolysOverflow;

    // pass 1: check for any positive nested polygon or outer rings matches, short circuiting
    for (uint i = 0, n = ents.length; i < n; ++i) {
        auto child = ents[i];
        switch (child.type) {
            case GeoType.Bounds: bounds = geo[0..2]; geo = geo[2..$]; break;
            case GeoType.RingInner: {
                auto ringPoints = geo[0..child.payload]; geo = geo[child.payload..$];
                if (innerPolygonsCount < INNER_POLYGONS_CACHED_MAX) {
                    innerPolys[innerPolygonsCount++] = InnerPoly(ringPoints, bounds);
                } else {
                    innerPolysOverflow ~= InnerPoly(ringPoints, bounds);
                }
                bounds = null;
                break;
            }
            case GeoType.RingOuter: {
                auto ringPoints = geo[0..child.payload]; geo = geo[child.payload..$];
                auto ringBounds = bounds; bounds = null;
                if (hasOuterPolygonHit) continue;
                if (bounds && !query.matches(AABB(ringBounds[0], ringBounds[1]))) continue;
                if (query.matches(Prim(PrimType.RingPoints, ringPoints))) {
                    hasOuterPolygonHit = true;
                }
                break;
            }
            // handle recursive polygons
            case GeoType.Polygon: {
                auto polyPoints = geo[0..child.payload]; geo = geo[child.payload..$];
                auto polyBounds = bounds; bounds = null;
                auto childEnts = ents[i+1..min(n, i+1+child.payload)];
                i += child.payload;
                if (bounds && !query.matches(AABB(polyBounds[0], polyBounds[1]))) continue;
                if (matchesAnyPolygon(query, childEnts, geo)) {
                    return true;
                }
                break;
            }
        }
    }
    // check if we can terminate
    if (!hasOuterPolygonHit) return false;    // if no hit on the outer ring
    if (innerPolygonsCount == 0) return true; // if no inner rings

    // pass 2: check inner polygons
    foreach (poly; innerPolys[0..innerPolygonsCount]) {
        if (query.matches(AABB(poly.bounds[0], poly.bounds[1]))) {
            if (query.matches(Prim(PrimType.RingPoints, poly.points))) {
                return false;
            }
        }
    }
    if (innerPolygonsCount >= INNER_POLYGONS_CACHED_MAX) {
        foreach (poly; innerPolysOverflow) {
            if (query.matches(AABB(poly.bounds[0], poly.bounds[1]))) {
                if (query.matches(Prim(PrimType.RingPoints, poly.points))) {
                    return false;
                }
            }
        }
    }
    // hit outer ring; inner ring(s) exist but did not hit any
    return true;
}

enum MatchType {
    MatchAny,
    VisitAnyMatching,
    VisitAllMatching,
}
struct FailedBoundsCheck (TChildren, TGeo=void) {
    FlexGeo*            flexGeo;
    AABB                bounds;
    GeoType             type;
    const(TChildren)[]  children;
    static if (!is(TGeo == void)) const(Point)[] geometry;
}
struct BoundsCheckResult (TChildren, TGeo=void) {
    FlexGeo*            flexGeo;
    AABB                bounds;
    GeoType             type;
    const(TChildren)[]  children;
    static if (!is(TGeo == void)) const(Point)[] geometry;
    bool inBounds;
}


// additional visit parameters
private struct VisitState {
    const(Point)[] bounds; long index = -1, tag = -1;
    void reset () { bounds = null; index = tag = -1; }
}

bool matchVisitImpl (TQuery, MatchType matchType, TVisitor, TDispatch=RootQueryDispatcher)(
    TQuery              query,
    ref const(FlexGeo)  g,
    TVisitor            visitor
) {
    auto ents = g.entities; auto geo = g.geometry;
    VisitState visitState;
    const(Point)[] bounds = null;
    long index = -1, tag = -1;
    bool hitAnything = false;

    for (size_t i = 0, n = ents.length; i < n; ++i) {
        auto ent = ents[i];
        if (ent.type < GeoType.RingOuter) {
            switch (ent.type) {
                case GeoType.Bounds: visitState.bounds = geo[0..2]; geo = geo[2..$]; break;
                case GeoType.Index:  visitState.index = cast(long)ent.payload; break;
                case GeoType.Tag:    visitState.tag = cast(ulong)ent.payload; break;
                case GeoType.None:   break;
                default: assert(false, "unimplemented type %s".format(ent.type));
            }
        } else if (ent.type >= GeoType.RingOuter) {
            auto childCount = ents[i].payload.clamp(0, n);
            auto children   = ents[i+1 .. i+1+childCount];

            bool skip = false;
            if (visitState.bounds) {
                auto bbox = AABB(bounds[0], bounds[1]);
                bool inBounds = query.matches(bbox);
                static if (__traits(compiles, visitor.on(
                    BoundsCheckResult(g, bbox, ent.type, children, geo, inBounds)
                    ))) {
                        visitor.on(BoundsCheckResult(g, bbox, ent.type, children, geo, inBounds));
                    }

                if (!inBounds) {
                    static if (matchType != MatchType.VisitAll) {
                        skip = true;
                        i += childCount; // skip to next entity
                        continue;
                    }
                }
            }
            bool hit = false;
            if (ent.type.isContainer) {
                auto children = ents[i+1 .. i+1+childCount];
                i += childCount;
                if (!skip) {
                    hit = TDispatch.dispatchVisit!(TQuery, MatchType, TVisitor)(
                        query, g, visitor, ent.type, children, geo, visitState
                    );
                }
            } else {
                auto children = geo[0 .. childCount]; geo = geo[childCount..$];
                if (!skip) {
                    hit = TDispatch.dispatchVisit!(TQuery, MatchType, TVisitor)(
                        query, g, visitor, ent.type, g, children, visitState
                    );
                }
            }
            static if (matchType == MatchType.MatchAny || matchType == MatchType.VisitAnyMatching) {
                if (hit) return true;
            } else {
                hitAnything = hit;
            }
            visitState.reset();
        }
    }
    return hitAnything;
}
struct RootQueryDispatcher {
    static bool dispatchVisit(TQuery, MatchType matchType, TVisitor)(
        TQuery query, ref const(FlexGeo) g, Visitor visitor,
        GeoType type, const(Entity)[] children, ref const(Point)[] geo, ref VisitState state
    ) {
        static if (__traits(compiles, visitor(type, children, state))) {
            visitor(type, children, state);
        }
        static if (__traits(compiles, visitor.shouldVisit(type))) {
            if (!visitor.shouldVisit(type)) return;
        }
        switch (type) {
            case GeoType.Polygon: return matchesPolygonImpl(query, children, geo, visitor);
            // return matchVisitImpl!(TQuery, matchType, TVisitor, PolygonVisitorDispatch)(query, g, visitor);
            default: assert(0, "invalid: %s".format(type));
        }
    }
    static void dispatchVisit(TQuery, MatchType matchType, TVisitor)(
        TQuery query, GeoType type, ref const(Point)[] geo, ref const(FlexGeo) g, ref VisitState state
    ) {

    }
}

struct PolygonVisitDispatcher {
    struct Visitor {
        bool outerRingHit = false;
        bool polygonHit = false;
    }
}
bool matchesAny (TQuery)(TQuery query, ref const(FlexGeo) g) {
    return matchVisitImpl!(TQuery, MatchType.MatchAny, uint)(
        query, g, 0
    );
}
bool visitMatchingAny (TQuery,TVisitor)(TQuery query, ref const(FlexGeo) g, TVisitor v) {
    return false; // TODO: matchVisitImpl has known bugs (see ISSUES.md), stubbed
}
bool visitMatchingAll (TQuery,TVisitor)(TQuery query, ref const(FlexGeo) g, TVisitor v) {
    return false; // TODO: matchVisitImpl has known bugs (see ISSUES.md), stubbed
}

// struct VisitBoth {
//     alias VisitObjectTypeDg = void delegate(scope FlexObject);
//     alias VisitPrimTypeDg   = void delegate(scope Prim);

//     VisitObjectTypeDg visitObjectDg;
//     VisitPrimTypeDg visitPrimDg;

//     void visit (scope FlexObject obj) { if (visitObjectDg) visitObjectDg(obj); }
//     void visit (scope Prim prim)  { if (visitPrimDg) visitPrimDg(prim); }
// }
// struct VisitBounds {
//     alias VisitObjectBoundsDg = void delegate( scope FlexObject, AABB bounds, bool boundsHit, bool objectHit );
//     alias VisitPrimBoundsDg   = void delegate( scope Prim,   AABB bounds, bool boundsHit, bool geoHit );
//     VisitObjectBoundsDg visitObjectBoundsDg;
//     VisitPrimBoundsDg visitPrimBoundsDg;

//     void visit( scope FlexObject obj, AABB bounds, bool boundsHit, bool objectHit ) {
//         if (visitObjectBoundsDg) visitObjectBoundsDg(obj, bounds, boundsHit, objectHit);
//     }
//     void visit( scope Prim prim,  AABB bounds, bool boundsHit, bool primHit ) {
//         if (visitPrimBoundsDg) visitPrimBoundsDg(prim, bounds, boundsHit, primHit);
//     }
// }
