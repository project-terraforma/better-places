module models.flexgrid_plugins.flexgrid_viewer;
import models.flexgrid;
import raylib;
import std;

alias AABB = TAABB!PolarNorm;
alias Point = TPoint!PolarNorm;

class Viewer {
    private FlexGrid m_grid;
    private AABB m_view;
    private ubyte m_viewLevel;
    private FlexCellKey m_viewKeyMin, m_viewKeyMax;
    private bool m_hasView = false;

    // void setView (AABB view) { this.view = view; }
    void setView (AABB newView) {
        if (newView != m_view || !m_hasView) {
            m_hasView = true;
            writefln("Setting view to\n\n\t%s\n\n\t%s\n\n\t%s",
                newView.to!PolarNorm,
                newView.to!PolarDeg,
                newView.to!Meters
            );
            m_view = newView;
            m_viewLevel = FlexCellKey.getLevel(newView);
            writefln("View level = %s", m_viewLevel);
            m_viewKeyMin = FlexCellKey.from(newView.minv, m_viewLevel);
            m_viewKeyMax = FlexCellKey.from(newView.maxv, m_viewLevel);
            writefln("View MIN = %s", m_viewKeyMin);
            writefln("View MAX = %s", m_viewKeyMax);
            writeln();
        } else {
            // writefln("ignoring setView change");
        }
    }
    void setView (U)(TAABB!U newView)
        if (!is(U == AABB.Unit)) {
            // writefln("setting view to %s\n-> %s", newView, newView.to!AABB);
            setView(newView.to!AABB);
        }

    @property FlexGrid grid () { return m_grid; }
    @property AABB view () { return m_view; }
    @property void view (U)(TAABB!U newView) { setView(newView); }


    this (FlexGrid grid, AABB view) { m_grid = grid; m_view = view; }
    this (FlexGrid grid) { m_grid = grid; }

    void render (TR, TTR)(TR r, TTR tr) {
        // writefln("RENDERING VIEW, view bounds =\n\t%s\n\t%s\n\t%s",
        //     view.to!PolarNorm,
        //     view.to!PolarDeg,
        //     view.to!Meters
        // );
        // m_grid.visitCells(view, &renderCell);
        auto v = this.view;
        r.textf("view bounds %s", v);
        bool drawGridRects = r.drawGridRects;

        foreach (layer; grid.layers.byValue) {
            // writefln("%s %s", layer.id, r.layerViews);
            auto lv = layer.id in r.layerViews;
            if (lv && !lv.visible) continue;
            if (!lv) {
                writefln("layer %s missing view", layer.name);
            }
            // if (!lv) { r.layerViews[layer.id] = TR.LayerView(); lv = layer.id in r.layerViews; }

            foreach (kv; layer.cells.byKeyValue) {
                auto cellBounds = kv.key.bounds;
                bool inBounds = v.contains(cellBounds);
                // r.textf("checking cell %s bounds: %x => (%s,%s) => %s",
                //     layer.name, kv.key.value, cellBounds.minv, cellBounds.maxv,
                //     inBounds);
                //
                if (r.drawGridRects) {
                    auto mouseover = cellBounds.contains(tr.cursorPos);
                    r.draw(cellBounds, Colors.BLUE, tr, mouseover ? 4 : 3);
                }
                if (!inBounds) continue;

                renderCell(kv.value, r, tr, *lv);
            }
        }
    }
    import models.flexgrid.flexgeo;
    import models.flexgrid.flexgeo.iteration;
    import models.geometry.bounds;
    import models.geometry.algorithms;
    private struct GeometryRenderer (TR,TTR) {
        TR renderer; TTR tr; bool drawRect = true;
        void visit(scope FlexObject obj, AABB bounds, bool boundsHit, bool objectHit) {
            writefln("%s", obj);
            if (drawRect) {
                renderer.draw(bounds, Colors.RED, tr, boundsHit ? 5 : 2);
            }
        }
        void visit( scope Prim prim, AABB bounds, bool boundsHit, bool primHit ) {
            if (drawRect) {
                renderer.draw(bounds, Colors.ORANGE, tr, boundsHit ? 3 : 1);
            }
        }
    }
    struct DummyQuery {
        bool matches (AABB bounds) { writefln("hi"); return true; }
        bool matches (Prim prim) { writefln("hi"); return true; }
    }

    private void renderCell (TR, TTR, TLayerView)(FlexCell cell, TR renderer, TTR transform, ref TLayerView layerView) {
        auto viewBounds = view;
        if (!viewBounds.contains(cell.bounds)) return;

        auto r = GeometryRenderer!(TR,TTR)(renderer, transform);
        // auto q = models.flexgrid.flexgeo.iteration.withinRadiusOf(transform.cursorPos, transform.cursorRadius);
        auto q = DummyQuery();
        bool shouldCheckMouseover = cell.bounds.withinRadiusOf(transform.cursorPos, transform.cursorRadius);

        foreach (kv; cell.geoBounds.byKeyValue) {
            auto bounds = kv.value;
            if (!viewBounds.contains(bounds)) continue;
            import models.geometry.algorithms: withinRadiusOf;
            bool mouseover = shouldCheckMouseover&& bounds.withinRadiusOf(transform.cursorPos, transform.cursorRadius);
            // bool mouseover = bounds.contains(transform.cursorPos);
            renderer.draw(bounds, mouseover? Colors.ORANGE : Colors.GREEN, transform, 1);
            auto geometry = kv.key in cell.geo;
            if (geometry) {
                models.flexgrid.flexgeo.iteration.visitMatchingAll(q, *geometry, r);
            }
        }
        auto pointsWithinRadius = Scalar!Meters(3000);
        enum zoomLevelCutoff = 0.15;

        if (transform.zoomLevel >= zoomLevelCutoff) return;
        // shouldCheckMouseover = cell.bounds.withinRadiusOf(transform.cursorPos, transform.cursorRadius);
        // if (!shouldCheckMouseover) return;

        foreach (kv; cell.points.byKeyValue) {
            auto pt = kv.value;
            if (!viewBounds.contains(pt)) continue;

            bool mouseover = shouldCheckMouseover &&
                pt.withinRadiusOf(transform.cursorPos, transform.cursorRadius);
            // if (pt.withinRadiusOf(transform.cursorPos, pointsWithinRadius)) {
            renderer.draw(pt, mouseover ? Colors.PURPLE : Colors.RED, mouseover ? 6.0f : 3.0f, transform);
            // }
        }
    }
}
