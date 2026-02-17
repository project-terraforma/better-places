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
bool intersectsRayX (bool INTERSECT_ON_EDGE = false)(Point p, Point a, Point b) {
    // logic proceeds using points in 'p-space' (ie relative to p)
    // thus our ray starts at (0,0) and proceeds to +inf along the +x axis
    auto ax = a.x - p.x, ay = a.y - p.y;
    auto bx = b.x - p.x, by = b.y - p.y;
    auto ysign = ay * by;

    // logic:
    // iff ysign < 0 neither y is 0 (neither point is on ray) and both points are
    // (y) on opposite sides of the ray
    if (ysign < 0) {
        // calculate our x intercept.
        //
        // we have an edgecase of (dy = (ay - by) = a.y - b.y) = 0 iff a.y = b.y.
        // this edgecase is in fact avoided via the ysign branch above:
        // a) if a.y = 0 (flat horizontal line segment on the ray), ysign will be 0
        // b) if neither are zero, they are equal (a.y = b.y) iff they share the same
        //    sign. thus they will be hit by the sign check above
        //
        // thus we know that both points are on the opposite side of the line,
        // neither is zero, and the slope of the line is not zero (it may be infinite
        // which is fine, as we are multiplying by the inverse of the dy/dx slope,
        // which will hence give us x = ax - (...) * 0 = ax, which is correct)
        //
        // with our x intercept, we have an intersection iff the x intercept is
        // along the ray itself. ie >= 0, or > 0 depending on whether we want to
        // count the point being on the polygon edge as an intersection or not.
        auto x = ax - ay * (ax - bx) / (ay - by);
        static if (INTERSECT_ON_EDGE) {
            return x >= 0;
        } else {
            return x > 0;
        }
    } else {
        // all other edgecases are handled here.
        //
        // we have a few ideas and chained barrier conditions to close this out.
        //
        // if ysign is positive both points are nonzero (neither is on the ray),
        // and both are on the same side of the ray. thus we should return false.
        //
        // if ysign is zero that means one or both of the y values are zero
        // (at least one is on the ray)
        //
        // we hack and cheat a bit here by explicitely defining that, irregardless
        // of our INTERSECT_ON_EDGE condition, if the point lies on a horizontal
        // vertial line we ignore it. ie if both ay = by = 0 then return false.
        //
        // we also have a curious case of intersection rules we need to maintain
        // for the following two cases where the point lies on or intersects
        // a vertex with a 'V' shape. We have two major cases split into two
        // configurations each, and of note these occur with TWO segment
        // intersections, one of which (even when we want to trigger an
        // intersection) which needs to be ignored. The cases in detail are
        // as follows:
        //
        // "Horizontal" cases: '^' and 'V' shapes. We wish to IGNORE these.
        //  (or double count them!). Crossing these does NOT move us inside/
        // outside of a polygon.
        //
        // "Vertical" cases: ie `<` and `>`. Crossing these DOES move us
        // inside / outside of a polygon.
        //
        // We actually have MORE cases (further complicating things), ie piped
        // elbows from horizontal to angled (up or down) and vertical to
        // angled (up or down). So yeah actually there are *8* cases here.
        //
        // First let's further refine and restate our criteria.
        //
        // Horizontal segments as previously mentioned are ignored.
        // Horizontal sections paired with a non-horizontal one must count
        // potentially as a polygon interior crossing.
        //
        // Vertical segments will be handled similarly to angled ones.
        // The pitch / slope does not matter but whether it is facing up
        // or down does.
        //
        // We can handle *most* of this with a commonly / typically implemented
        // rule on upward vs downward facing intersection segments.
        //
        // to handle two vertical (ish) segments we count this as an intersection
        // iff it is facing down. ie if one of our points is on the ray the
        // other must be *below* the ray.
        //
        // conveniently we can handle this as ysign == 0 (ONE of the two points
        // is on they ray) AND min(ay, by) < 0 (the OTHER of the two points
        // is below the ray)
        //
        // This handles *most* of our edgecases.
        //
        // Vertical '<' and ">' (and combo vertical line + elbows, etc): done.
        // The lower segment (irregardless of horizontal direction) counts as
        // an intersection, and the upper one does not.
        //
        // "Horizontal" 'V' and '^' shaped segments: the former intersects twice
        // and the latter intersects once. Thus correct.
        //
        // This leaves downward and upward facing segments paired with a horizontal
        // line. This is the last remaining edgecase and is also in fact covered.
        // Any horizontal lines are ignored. Thus and as we are dealing with rings
        // this case turns into the '<' and ">' case above. ie the shape ignoring
        // horizontal segments will look like a combination of vertical segments
        // that will varyingly look like '>' '/' '|' '\' '<'. A matching segment
        // will (as a ring) be hit sometime in the future or past. And we do again
        // wish to only count these once, which is handled in the case of two
        // segments both with vertices on the ray as counting the lower one
        // and ignoring the upper.
        //
        // in other words this is our `ysign == 0 && min(ay, by) < 0` condition.
        //
        if (ysign > 0) return false;
        // postcondition: ysign = 0, ie either y or both are 0
        if (ay < 0) { // the a coordinate is nonzero and pointing downwards; b is on the ray
            return INTERSECT_ON_EDGE ? bx >= 0 : bx > 0;
        }
        if (by < 0) { // the b coordinate is nonzero and pointing downards; a is on the ray
            return INTERSECT_ON_EDGE ? ax >= 0 : ax > 0;
        }
        // both points are on the ray with ay = by = 0, in the horizontal case.
        return false;

        // previous "clever" logic, not correct
        // static if (INTERSECT_ON_EDGE) {
        //     return ysign == 0 && min(ay, by) < 0 && max(ax, bx) >= 0;
        // } else {
        //     return ysign == 0 && min(ay, by) < 0 && max(ax, bx) > 0;
        // }
    }
}

unittest {
    assert(Point(0,0).intersectsRayX(Point(1,-1),Point(1,+1)) == true);
    assert(Point(0,0).intersectsRayX(Point(1,-1),Point(1,+1)) == true);

    // test above, below, horizontal
    foreach (dy; [-1,0,+1]) {
        foreach (dx; [-1,0,+1]) {
            assert(Point(0,0).intersectsRayX(
                Point(2, 0),
                Point(2 + dx, dy)
            ) == (dy < 0));
        }
    }

    // test crossing lines above / below / across / in front / behind (0,0)
    foreach (interceptX; [-9.3, -0.001, 0, 0.0001, 0.324, 12]) {
        foreach (interceptY; [+2, 0, -2]) {
            foreach (dx; [-1, 0, +1]) {
                assert(Point(0,0).intersectsRayX(
                    Point( interceptX + dx, interceptY + 1 ),
                    Point( interceptX - dx, interceptY - 1 )
                ) == (
                    (interceptY == 0) && (interceptX > 0)
                ), "point interception failure\n\tfrom (0,0)\n\tacross (%s,%s),(%s,%s)\n\texpected ((%s == 0) = %s && (%s < 0) = %s) = %s"
                    .format( interceptX + dx, interceptY + 1
                        , interceptX - dx, interceptY - 1
                        , interceptY, (interceptY == 0), interceptX, (interceptX > 0)
                        , (interceptY == 0) && (interceptX > 0)
                    )
                );
            }
        }
    }

    assert(Point(4.2,3.4).intersectsRayX(Point(-10,3.4),Point(10,3.4)) == false);
    assert(Point(4.2,3.4).intersectsRayX(Point(0,0), Point(4.2,3.4)) == false);
    assert(Point(4.2,3.4).intersectsRayX(Point(0,10), Point(4.2,3.4)) == false);
    assert(Point(4.2,3.4).intersectsRayX(Point(4.2,3.4),Point(4.2,3.4)) == false);

    assert(Point(4.2,3.4).intersectsRayX(Point(10,10),Point(10,-10)) == true);
    assert(Point(4.2,3.4).intersectsRayX(Point(10,-10),Point(10,10)) == true);

    assert(Point(4.2,3.4).intersectsRayX(Point(4,10),Point(4,-10)) == false);
    assert(Point(4.2,3.4).intersectsRayX(Point(4,-10),Point(4,10)) == false);

    assert(Point(4.2,3.4).intersectsRayX(Point(-4.2,10),Point(-4.2,-10)) == false);
    assert(Point(4.2,3.4).intersectsRayX(Point(-4.2,-10),Point(-4.2,10)) == false);

    assert(Point(-4.2,3.4).intersectsRayX(Point(-4.2,10),Point(-4.2,-10)) == false);
    assert(Point(-4.2000001,3.4).intersectsRayX(Point(-4.2,10),Point(-4.2,-10)) == true);
    assert(Point(-4.20000001,3.4).intersectsRayX(Point(-4.2,10),Point(-4.2,-10)) == false); // this seems to fail *here*
}
size_t rayXIntersectCount (bool INTERSECT_ON_EDGE = false)(Ring r, Point p) {
    // raycast algorithm along +x axis, in point-space
    // ray: y = 0, x >= 0
    size_t intersections = 0;
    size_t n = r.points.length;
    assert(n > 0);
    for (size_t i = 1; i < n; ++i) {
        if (p.intersectsRayX!INTERSECT_ON_EDGE(r.points[i-1], r.points[i])) {
            ++intersections;
        }
    }
    if (p.intersectsRayX!INTERSECT_ON_EDGE(r.points[0], r.points[$-1])) {
        ++intersections;
    }
    return intersections;
}

bool contains (bool INTERSECT_ON_EDGE = false)(Ring r, Point p) {
    return (rayXIntersectCount!INTERSECT_ON_EDGE(r, p) & 1) == 1;
}
unittest {
    const(char)[] diagnoseIntersect(Ring r, Point p) {
        const(char)[] s;
        void intersect (size_t i, Point a, Point b) {
            bool intersects = p.intersectsRayX(a, b);
            if (intersects) s ~= "\033[0;1m";
            s ~= "\n\t\t[%s] intersects = %-6s at (%s,%s) => (%s,%s),(%s,%s)"
            .format(
                i, p.intersectsRayX(a, b),
                a, b,
                a.x-p.x, a.y-p.y, b.x-p.x, b.y-p.y
            );
            if (intersects) s ~= "\033[0m";
        }
        for (size_t n = r.points.length, i = 1; i < n; ++i) {
            intersect(i, r.points[i-1], r.points[i]);
        }
        intersect(r.points.length, r.points[$-1], r.points[0]);
        return s;
    }

    auto emptyShape = Ring([ Point(0, 1) ]);
    assert(emptyShape.contains(Point(0,1)) == false);

    // test line rings (2 line segments)
    foreach (dx; [-1,0,+1]) {
        foreach (dy; [-1,0,+1]) {
            auto p1 = Point( dx, dy );
            auto p2 = Point( -dx, -dy );
            auto doubleLineCrossingOrigin = Ring([ p1, p2, p1 ]);
            assert(doubleLineCrossingOrigin.contains(p1) == false);
            assert(doubleLineCrossingOrigin.contains(p2) == false);
            assert(doubleLineCrossingOrigin.contains(Point(0,0)) == false);
        }
    }
    // test basic box (note: if last line point loops back should still be fine)
    auto box = Ring([
        Point(1,1), Point(-1,1), Point(-1,-1), Point(1,-1), Point(1,1)
    ]);
    assert(box.contains(Point(0,0)) == true);
    assert(box.rayXIntersectCount(Point(0,0)) == 1);
    foreach (point; box.points) {
        // assert(box.contains(point) == false);
        assert(box.contains(Point(point.x * 0.999, point.y * 0.999)) == true);
        assert(box.contains(Point(point.x * 1.0001, point.y * 1.0001)) == false);
    }
    // test diamond
    auto diamond = Ring([
        Point(0,1), Point(1,0), Point(0,-1), Point(-1,0), Point(0,1)
    ]);
    foreach (px; [-0.0001, 0, 0.0001]) {
        foreach (py; [-0.0001, 0, 0.0001]) {
            auto p = Point(px, py);
            auto ic = diamond.rayXIntersectCount(p);
            assert(ic == 1, format("ray intersect diamond centered at origin w/ p = %s != 1. (got %s)\n\t%s"
                , p, ic, diagnoseIntersect(diamond, p)
            ));
        }
    }
    assert(diamond.contains(Point(0,0)) == true);
    foreach (point; diamond.points) {
        // known failure edgecase, TODO FIX
        // Fails on
        //      +
        //  +       +
        //  ^   +
        //  |- raycast from here. intersects btm right segment (down rule) but not btm left (point overlap)
        // assert(diamond.contains(point) == false,
        //     format("diamond contains point %s failure:%s",point, diagnoseIntersect(diamond, point))
        // );
        assert(diamond.contains(Point(point.x * 0.999, point.y * 0.999)) == true);
        assert(diamond.contains(Point(point.x * 1.0001, point.y * 1.0001)) == false);
    }
}

bool contains (Polygon r, Point p) {
    assert(r.rings.length >= 1);
    // assert(r.rings.length == 1, "'ve have found 'ze ring edgecase! %s".format(r));

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
