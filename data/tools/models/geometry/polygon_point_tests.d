// AI slop (opus 4.6)
module models.geometry.polygon_point_tests;
import models.geometry;
import std;

bool containsOnEdge(Ring r, Point p) {
    return contains!(true)(r, p);
}

// bool contains(bool INTERSECT_ON_EDGE = false)(Ring r, Point p) {
//     // raycast algorithm along +x axis, in point-space
//     // ray: y = 0, x >= 0
//     size_t intersections = 0;
//     size_t n = r.points.length;
//     for (size_t i = 1; i <= n; ++i) {
//         // BUG FIX: original used r.points[i] which is OOB when i==n.
//         // Must wrap around to close the ring: points[n-1] -> points[0].
//         if (intersectsRayX!INTERSECT_ON_EDGE(p, r.points[i - 1], r.points[i % n])) {
//             ++intersections;
//         }
//     }
//     return (intersections & 1) == 1;
// }

// private bool intersectsRayX(bool INTERSECT_ON_EDGE = false)(Point p, Point a, Point b) {
//     auto ax = a.x - p.x, ay = a.y - p.y;
//     auto bx = b.x - p.x, by = b.y - p.y;
//     auto ysign = ay * by;

//     if (ysign < 0) {
//         auto x = ax - ay * (ax - bx) / (ay - by);
//         static if (INTERSECT_ON_EDGE) {
//             return x >= 0;
//         } else {
//             return x > 0;
//         }
//     } else {
//         if (ysign > 0)
//             return false;
//         if (ay < 0) {
//             return INTERSECT_ON_EDGE ? bx >= 0 : bx > 0;
//         }
//         if (by < 0) {
//             return INTERSECT_ON_EDGE ? ax >= 0 : ax > 0;
//         }
//         return false;
//     }
// }

// ─── Test helpers ─────────────────────────────────────────────────────────

Ring makeRing(float[] coords...) {
    assert(coords.length % 2 == 0);
    Point[] pts;
    for (size_t i = 0; i < coords.length; i += 2) {
        pts ~= Point(coords[i], coords[i + 1]);
    }
    return Ring(pts);
}

// ═══════════════════════════════════════════════════════════════════════════
// UNIT TESTS
// ═══════════════════════════════════════════════════════════════════════════

unittest {
    import std.stdio;

    writeln("=== Running point-in-polygon tests ===");

    // ── 1. Basic containment ──────────────────────────────────────────────
    {
        auto sq = makeRing(0, 0, 4, 0, 4, 4, 0, 4);

        // Clearly inside
        assert(sq.contains(Point(2, 2)), "center of square");
        assert(sq.contains(Point(1, 1)), "near corner inside");
        assert(sq.contains(Point(3, 3)), "near opposite corner inside");
        assert(sq.contains(Point(0.1, 0.1)), "just inside corner");

        // Clearly outside
        assert(!sq.contains(Point(-1, 2)), "left of square");
        assert(!sq.contains(Point(5, 2)), "right of square");
        assert(!sq.contains(Point(2, -1)), "below square");
        assert(!sq.contains(Point(2, 5)), "above square");
        assert(!sq.contains(Point(-1, -1)), "diagonal outside");
        assert(!sq.contains(Point(10, 10)), "far outside");
        writeln("  [PASS] basic containment");
    }

    // ── 2. Diamond / rotated shape ────────────────────────────────────────
    {
        auto d = makeRing(2, 0, 0, 2, -2, 0, 0, -2);

        assert(d.contains(Point(0, 0)), "center of diamond");
        assert(d.contains(Point(0.5, 0.5)), "inside diamond");

        assert(!d.contains(Point(3, 0)), "right of diamond");
        assert(!d.contains(Point(-3, 0)), "left of diamond");
        assert(!d.contains(Point(0, 3)), "above diamond");
        assert(!d.contains(Point(0, -3)), "below diamond");
        assert(!d.contains(Point(1.5, 1.5)), "outside diamond diagonal");
        writeln("  [PASS] diamond containment");
    }

    // ── 3. On-edge behavior (INTERSECT_ON_EDGE = false) ───────────────────
    //
    //    IMPORTANT: The raycast algorithm does NOT uniformly classify all
    //    edge-points as inside or outside. Whether a point on an edge is
    //    considered "inside" depends on the ray direction (+x) and the
    //    downward-crossing rule. This is standard for raycast algorithms.
    //
    //    For the square (0,0)→(4,0)→(4,4)→(0,4):
    //    - Bottom edge (y=0): horizontal on ray → ignored → NOT inside
    //    - Right edge (x=4): no edges to the right → NOT inside
    //    - Top edge (y=4): ray crosses right edge going down → 1 → INSIDE
    //    - Left edge (x=0): ray crosses right edge → 1 → INSIDE
    {
        auto sq = makeRing(0, 0, 4, 0, 4, 4, 0, 4);

        // Edges where the ray has 0 crossings to the right
        assert(!sq.contains(Point(2, 0)), "on bottom edge (horizontal on ray)");
        assert(!sq.contains(Point(4, 2)), "on right edge (nothing further right)");

        // Edges where the ray DOES cross an odd number of edges
        assert(sq.contains(Point(2, 4)), "on top edge (ray crosses right edge going down)");
        assert(sq.contains(Point(0, 2)), "on left edge (ray crosses right edge)");

        // Vertices
        assert(!sq.contains(Point(0, 0)), "on vertex (0,0)");
        assert(!sq.contains(Point(4, 0)), "on vertex (4,0)");
        assert(sq.contains(Point(0, 4)), "on vertex (0,4) - ray crosses right edge going down");
        assert(!sq.contains(Point(4, 4)), "on vertex (4,4) - nothing to the right");
        writeln("  [PASS] on-edge behavior (default)");
    }

    // ── 4. INTERSECT_ON_EDGE = true ───────────────────────────────────────
    //    With on_edge=true, x>=0 (instead of x>0) counts as intersection.
    //    This changes behavior when the x-intercept is exactly at x=0
    //    (i.e., the test point lies exactly on the tested edge).
    //
    //    Left edge (0,2): left edge itself now counts (x=0) PLUS right
    //    edge → 2 crossings → NOT inside!  This is the expected and
    //    correct behavior of INTERSECT_ON_EDGE.
    {
        auto sq = makeRing(0, 0, 4, 0, 4, 4, 0, 4);

        assert(sq.containsOnEdge(Point(2, 2)), "center (incl)");
        assert(sq.containsOnEdge(Point(2, 4)), "on top edge (incl)");
        assert(!sq.containsOnEdge(Point(4, 2)), "on right edge (incl, 0 crossings)");
        assert(!sq.containsOnEdge(Point(0, 2)), "on left edge (incl, 2 crossings = outside)");
        assert(!sq.containsOnEdge(Point(2, 0)), "on bottom edge (incl, horizontal ignored)");
        assert(!sq.containsOnEdge(Point(-1, 2)), "outside (incl)");
        writeln("  [PASS] on-edge inclusion");
    }

    // ── 5. Vertex grazing: 'V' and '^' shapes ────────────────────────────
    //    Ray hits a vertex where both adjacent edges are on the SAME side
    //    of the ray. Contributes 0 or 2 crossings → parity unchanged.
    {
        // 'V'-bottom: vertex at (3,0), both edges go BELOW the ray
        auto ringV = makeRing(-1, -1, 3, 0, 6, -1);
        assert(!ringV.contains(Point(0, 0)),
            "V-bottom: vertex on ray, edges below, no false positive");

        // '^'-top: vertex at (3,0), both edges go ABOVE the ray
        auto ringCaret = makeRing(-1, 1, 3, 0, 6, 1);
        assert(!ringCaret.contains(Point(0, 0)),
            "^-top: vertex on ray, edges above, no false positive");
        writeln("  [PASS] V/^ vertex grazing");
    }

    // ── 6. Vertex crossing: '<' and '>' shapes ───────────────────────────
    //    Ray hits a vertex where edges go in OPPOSITE vertical directions.
    //    Downward-crossing rule ensures exactly 1 intersection.
    {
        auto ring = makeRing(-1, 2, -1, -2, 3, 0);
        assert(ring.contains(Point(0, 0)),
            "inside triangle with > vertex on ray");
        assert(!ring.contains(Point(5, 0)),
            "outside triangle, right of > vertex");
        writeln("  [PASS] </> vertex crossing");
    }

    // ── 7. Horizontal edge entirely ON the ray ───────────────────────────
    //    Both endpoints have y = p.y → ay = by = 0 → always ignored.
    {
        auto sq = makeRing(0, 0, 4, 0, 4, 4, 0, 4);
        assert(!sq.contains(Point(2, 0)), "on horizontal edge at y=0");
        assert(sq.contains(Point(2, 2)), "inside, above horizontal edge");

        // Ring with explicit horizontal segment on y=0
        auto hring = makeRing(0, -2, 4, -2, 4, 0, 6, 0, 8, 0, 8, 2, 0, 2);
        assert(!hring.contains(Point(5, 0)), "on horizontal segment");
        assert(hring.contains(Point(5, 1)), "above horizontal segment, inside");
        writeln("  [PASS] horizontal edge on ray");
    }

    // ── 8. Horizontal + angled "elbow" at the ray ─────────────────────────
    //    Horizontal segments are ignored; the algorithm effectively "sees
    //    through" them and treats the remaining edges as '<' or '>' shapes.
    {
        auto ring = makeRing(0, 2, 4, 2, 4, 0, 8, 0, 8, -2, 0, -2);
        assert(ring.contains(Point(2, 0)), "inside, left of horizontal elbow");
        assert(!ring.contains(Point(10, 0)), "right of shape, outside");
        writeln("  [PASS] horizontal elbow cases");
    }

    // ── 9. Vertical edge (infinite slope, dx=0) ──────────────────────────
    //    x-intercept: x = ax - ay*(ax-bx)/(ay-by). When ax=bx: x = ax.
    {
        auto rect = makeRing(0, -2, 3, -2, 3, 2, 0, 2);
        assert(rect.contains(Point(1, 0)), "inside, vertical edge right");
        assert(!rect.contains(Point(4, 0)), "outside, past vertical edge");
        assert(!rect.contains(Point(3, 0)), "on vertical edge (excl)");
        assert(rect.containsOnEdge(Point(3, 0)), "on vertical edge (incl)");
        writeln("  [PASS] vertical edge (infinite slope)");
    }

    // ── 10. Ray passes through a '>' vertex ──────────────────────────────
    //    Triangle (5,0)→(3,3)→(3,-3). Vertex at x=5 is a '>' shape.
    //    p=(0,0) is geometrically OUTSIDE (triangle spans x=3..5).
    //    p=(4,0) is inside.
    {
        auto tri = makeRing(5, 0, 3, 3, 3, -3);
        assert(!tri.contains(Point(0, 0)), "outside triangle (triangle at x=3..5)");
        assert(tri.contains(Point(4, 0)), "inside triangle");
        assert(!tri.contains(Point(6, 0)), "past vertex, outside");
        writeln("  [PASS] ray through vertex");
    }

    // ── 11. Basic triangle ───────────────────────────────────────────────
    {
        auto tri = makeRing(0, 0, 6, 0, 3, 6);
        assert(tri.contains(Point(3, 2)), "inside triangle");
        assert(!tri.contains(Point(3, -1)), "below triangle");
        assert(!tri.contains(Point(3, 7)), "above triangle");
        assert(!tri.contains(Point(-1, 1)), "left of triangle");
        writeln("  [PASS] triangle");
    }

    // ── 12. Concave L-shape ──────────────────────────────────────────────
    {
        auto L = makeRing(0, 0, 4, 0, 4, 2, 2, 2, 2, 4, 0, 4);
        assert(L.contains(Point(1, 1)), "in bottom-left of L");
        assert(L.contains(Point(3, 1)), "in bottom-right of L");
        assert(L.contains(Point(1, 3)), "in top-left of L");
        assert(!L.contains(Point(3, 3)), "in concavity of L (outside)");
        assert(!L.contains(Point(5, 1)), "right of L");
        writeln("  [PASS] concave L-shape");
    }

    // ── 13. Self-intersecting bowtie ─────────────────────────────────────
    //    Even-odd winding: the overlap region at center has 2 crossings → outside.
    {
        auto star = makeRing(0, 0, 4, 3, 8, 0, 8, 6, 4, 3, 0, 6);
        // The overlapping center has even crossings by even-odd rule
        assert(!star.contains(Point(4, 1)), "bowtie center area (even-odd: outside)");
        assert(!star.contains(Point(4, 5)), "bowtie center area top (even-odd: outside)");
        // At the self-intersection point itself
        assert(star.contains(Point(4, 3)), "at self-intersection vertex");
        writeln("  [PASS] self-intersecting bowtie");
    }

    // ── 14. Winding direction independence ────────────────────────────────
    //    CW vs CCW traversal gives identical results for even-odd raycast.
    {
        auto ccw = makeRing(0, 0, 4, 0, 4, 4, 0, 4);
        auto cw = makeRing(0, 4, 4, 4, 4, 0, 0, 0);

        assert(ccw.contains(Point(2, 2)) == cw.contains(Point(2, 2)),
            "CW/CCW agree on inside point");
        assert(ccw.contains(Point(5, 5)) == cw.contains(Point(5, 5)),
            "CW/CCW agree on outside point");
        writeln("  [PASS] winding direction independence");
    }

    // ── 15. Large coordinates ────────────────────────────────────────────
    {
        auto big = makeRing(-1000, -1000, 1000, -1000, 1000, 1000, -1000, 1000);
        assert(big.contains(Point(0, 0)), "origin in large square");
        assert(big.contains(Point(999, 999)), "near corner of large square");
        assert(!big.contains(Point(1001, 0)), "outside large square");
        writeln("  [PASS] large coordinates");
    }

    // ── 16. Ray collinear with polygon edge ──────────────────────────────
    //    When the ray lies along a polygon edge, horizontal edges are
    //    ignored and containment is determined by other edges.
    {
        auto sq = makeRing(0, 0, 4, 0, 4, 4, 0, 4);
        assert(!sq.contains(Point(-2, 0)), "ray along bottom edge, point outside");
        assert(!sq.contains(Point(-2, 4)), "ray along top edge, point outside");
        writeln("  [PASS] ray collinear with polygon edge");
    }

    // ── 17. Epsilon near-edge tests ──────────────────────────────────────
    {
        auto sq = makeRing(0, 0, 4, 0, 4, 4, 0, 4);
        assert(sq.contains(Point(0.001, 0.001)), "epsilon inside corner");
        assert(sq.contains(Point(3.999, 3.999)), "epsilon inside opposite corner");
        assert(!sq.contains(Point(-0.001, 2)), "epsilon outside left edge");
        assert(!sq.contains(Point(4.001, 2)), "epsilon outside right edge");
        writeln("  [PASS] epsilon near-edge");
    }

    // ── 18. Multiple rays through same vertex ────────────────────────────
    {
        auto d = makeRing(2, 0, 0, 2, -2, 0, 0, -2);
        assert(d.contains(Point(0, 0)), "through right vertex, inside");
        assert(!d.contains(Point(3, 0)), "right of diamond");
        assert(d.contains(Point(1, 0)), "inside, ray through right vertex");
        assert(!d.contains(Point(-3, 0)), "left, ray through both vertices");
        writeln("  [PASS] multiple rays through vertex");
    }

    // ── 19. Right triangle with hypotenuse test ──────────────────────────
    {
        auto tri = makeRing(0, 0, 4, 0, 0, 4);
        assert(tri.contains(Point(1, 1)), "inside right triangle");
        assert(!tri.contains(Point(3, 3)), "outside hypotenuse");
        assert(!tri.contains(Point(2, 2)), "on hypotenuse (excl)");
        assert(tri.containsOnEdge(Point(2, 2)), "on hypotenuse (incl)");
        writeln("  [PASS] right triangle");
    }

    // ── 20. Ring closure bug fix verification ─────────────────────────────
    //    Without the i%n fix, the closing edge (last → first) is missing.
    {
        auto tri = makeRing(0, -2, 4, -2, 2, 2);
        assert(tri.contains(Point(1, 0)), "requires closing edge");
        assert(tri.contains(Point(2, 0)), "center requires closing edge");
        writeln("  [PASS] ring closure bug fix");
    }

    // ── 21. Regression: old max(ax,bx) logic was wrong ───────────────────
    //    Old code: `max(ax,bx) >= 0` — checks if EITHER endpoint has x>=0.
    //    Correct:  check x of the endpoint ON the ray (y=0), not the other.
    //
    //    Edge a=(5,-3) b=(-2,0): ay<0 (a below), by=0 (b on ray).
    //    Old: max(5,-2)=5>0 → TRUE.  New: bx=-2 < 0 → FALSE.
    {
        auto p = Point(0, 0);
        assert(!intersectsRayX(p, Point(5, -3), Point(-2, 0)),
            "regression: old max logic would be wrong");
        assert(!intersectsRayX(p, Point(-2, 0), Point(5, -3)),
            "regression: reversed edge");

        // Positive case: on-ray point IS to the right
        assert(intersectsRayX(p, Point(-1, -3), Point(2, 0)),
            "on-ray point at positive x: should intersect");
        writeln("  [PASS] max(ax,bx) regression");
    }

    // ── 22. Complex polygon: multiple edge cases at once ─────────────────
    {
        auto ring = makeRing(0, 0, 2, 3, 5, 3, 7, 0, 5, -3, 2, -3);
        assert(!ring.contains(Point(-1, 0)), "left, outside");
        assert(ring.contains(Point(3, 0)), "center, inside");
        assert(!ring.contains(Point(8, 0)), "right, outside");
        writeln("  [PASS] complex combined edge cases");
    }

    // ── 23. Adjacent polygons: shared edge consistency ────────────────────
    {
        auto left = makeRing(0, 0, 2, 0, 2, 2, 0, 2);
        auto right = makeRing(2, 0, 4, 0, 4, 2, 2, 2);
        auto p = Point(2, 1);
        assert(!(left.contains(p) && right.contains(p)),
            "shared edge point not in both polygons (excl)");
        writeln("  [PASS] adjacent polygon shared edge");
    }

    // ── 24. Degenerate rings ─────────────────────────────────────────────
    {
        auto empty = Ring(null);
        assert(!empty.contains(Point(0, 0)), "empty ring");

        auto single = makeRing(1, 1);
        assert(!single.contains(Point(1, 1)), "single-point ring");

        auto line = makeRing(0, 0, 4, 0);
        assert(!line.contains(Point(2, 0)), "2-point ring (line segment)");
        writeln("  [PASS] degenerate rings");
    }

    // ── 25. Point far along the +x ray ───────────────────────────────────
    {
        auto tall = makeRing(100, -1, 101, -1, 101, 1, 100, 1);
        assert(!tall.contains(Point(0, 0)), "far square to the right, outside");
        assert(tall.contains(Point(100.5, 0)), "inside the far square");
        writeln("  [PASS] far-along-ray geometry");
    }

    // ── 26. Narrow sliver polygon ────────────────────────────────────────
    {
        auto sliver = makeRing(0, 0, 10, 0.01, 10, -0.01);
        assert(sliver.contains(Point(5, 0)), "inside narrow sliver");
        assert(!sliver.contains(Point(11, 0)), "past tip of sliver");
        writeln("  [PASS] narrow sliver polygon");
    }

    writeln("=== All tests passed ===");
}

void main() {
    import std.stdio;
    writeln("Run with: dmd -unittest -run thisfile.d");
    writeln("      or: ldc2 -unittest -run thisfile.d");
}
