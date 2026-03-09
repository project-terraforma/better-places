module views.map_view;
import views.view_transform;
import views.layer_view_filter;
import views.entity_view_filter;
import views.renderer;
import base;
import std;

import controllers.map_view_controller; // hack

class MapView {
public:
    FlexGrid            grid;
    AABB                view;
    LayerViewFilter     layerFilters;
    EntityViewFilter    entityFilters;

    bool                drawStrictGridCellBounds = false;
    Color               drawStrictGridCellBoundsColor = Colors.BLUE;

    bool                drawCellBounds = false;
    Color               drawCellBoundsColor = Colors.RED;

    bool                drawPoints = true;

    bool                drawGeoBounds = true;

    enum GridCellBoundsCheck { UseCellBounds, UseGridBounds }
    enum gridCellBoundsCheck = GridCellBoundsCheck.UseCellBounds;
    // enum gridCellBoundsCheck = GridCellBoundsCheck.UseGridBounds;

    this (FlexGrid grid, AABB viewBounds)
        in { assert(grid !is null); }
        do {
            this.grid = grid;
            this.layerFilters = new LayerViewFilter(grid);
            this.entityFilters = new EntityViewFilter(grid);
        }
    void render (Renderer r, MapViewController c) {
        r.textf("render %s", view.to!PolarDeg);
        r.textf("    is %s", view);

        foreach (layer; grid.layers.byValue) {
            // r.textf("render layer %s '%s'", layer.id, layer.name);

            if (!layerFilters.isVisible(layer.id)) {
                // r.textf("hidden layer %s", layer.name);
                continue;
            } else {
                // r.textf("layer %s has %s cells", layer.name, layer.cells.length);
            }
            size_t i = 0;
            auto layerView = layer.id in layerFilters.layerInfo;
            if (!layerView) continue;

            foreach (kv; layer.cells.byKeyValue) {
                auto cell = kv.value;
                auto gridCellBounds = kv.key.bounds;
                auto cellBounds = cell.bounds;

                // r.textf("grid cell size: %s      %s     origin %s  view origin %s", gridCellBounds.size.to!Meters, cell.bounds.size.to!Meters
                //             , cell.bounds.minv.to!PolarDeg, view.minv.to!PolarDeg
                // );
                // r.textf("         origin (raw) %s         view origin (raw) %s"
                //         , cell.bounds.minv.to!PolarDeg, view.minv.to!PolarDeg
                // );
                // if (++i >= 10) break;
                //
                static if (gridCellBoundsCheck == GridCellBoundsCheck.UseGridBounds) {
                    bool inBounds = view.contains(gridCellBounds);
                    // bool inGridBounds = inBounds;
                    // bool inCellBounds = drawCellBounds ? view.contains(cellBounds) : false;
                } else {
                    bool inBounds = view.contains(cellBounds);
                    // bool inCellBounds = inBounds;
                    // bool inGridBounds = drawStrictGridCellBounds ? view.contains(gridCellBounds) : false;
                }
                if (inBounds) {
                    // writefln("cell %s is in bounds", kv.key);
                } else {
                    // writefln("%s not in bounds %s", view, gridCellBounds);
                }
                if (!inBounds) continue;

                if (drawStrictGridCellBounds) {
                    bool mouseover = gridCellBounds.contains(r.tr.cursorPos);
                    r.drawRect(gridCellBounds, drawStrictGridCellBoundsColor, mouseover ? 4 : 1);
                    if (mouseover) {
                        auto k = kv.key;
                        r.textf("mouse over (strict grid) bounds for cell (%s,%s,%s, layer=%s)", k.level, k.x, k.y, layer.name);
                    }
                }
                if (drawCellBounds) {
                    bool mouseover = cellBounds.contains(r.tr.cursorPos);
                    r.drawRect(cellBounds, drawCellBoundsColor, mouseover ? 4 : 1);
                    if (mouseover) {
                        auto k = kv.key;
                        r.textf("mouse over (cell actual) bounds for cell (%s,%s,%s, layer=%s)", k.level, k.x, k.y, layer.name);
                    }
                }
                drawCell(layer.id, cell, r, c, *layerView);
            }
        }
    }
private:
    void drawCell (uint layer, FlexCell cell, Renderer r, MapViewController c, LayerViewInfo layerView) {
        auto viewBounds = view;
        if (!viewBounds.contains(cell.bounds)) return;

        auto transform = r.tr; // ahck

        // auto q = models.flexgrid.flexgeo.iteration.withinRadiusOf(transform.cursorPos, transform.cursorRadius);
        // auto q = DummyQuery();
        bool shouldCheckMouseover = cell.bounds.withinRadiusOf(transform.cursorPos, transform.cursorRadius);

        auto defaultColor   = layerView.color;// layerFilters.getColor(layer, false);
        auto mouseoverColor = layerView.mouseoverColor;// layerFilters.getColor(layer, true);

        enum minGeometryPixelSizeToRender = 5;
        auto minPixelSizeFilterWorldSpace = r.tr.mapToScreenScale.x;

        foreach (kv; cell.geoBounds.byKeyValue) {
            auto bounds = kv.value;

            // filter out geometry too small to render (<= 1px)
            auto sz = bounds.size;
            auto maxVisibleWorld = max(sz.x, sz.y);
            // if (r.tr.mapToScreenScale.x * maxVisibleWorld <= 1)
            // if (r.tr.mapToScreenScale.x <= sz.x * 4) continue;
            if (minPixelSizeFilterWorldSpace * maxVisibleWorld <= minGeometryPixelSizeToRender) continue;

            if (!viewBounds.contains(bounds)) continue;
            import models.geometry.algorithms: withinRadiusOf;
            bool mouseover = shouldCheckMouseover&& bounds.withinRadiusOf(transform.cursorPos, transform.cursorRadius);
            // bool mouseover = bounds.contains(transform.cursorPos);
            //
            if (drawGeoBounds) {
                auto color = mouseover ? mouseoverColor : defaultColor;
                r.draw(bounds, color, 1);
            }
            auto geometry = kv.key in cell.geo;
            if (geometry) {
                // models.flexgrid.flexgeo.iteration.visitMatchingAll(q, *geometry, r);
            }
            if (mouseover) {
                auto geoType = geometry ? (*geometry).getType() : kv.key in cell.points ? GeoType.Point : GeoType.None;
                // hack
                c.mouseover(FlexCellId(cell, kv.key, geoType));
            }
        }
        auto pointsWithinRadius = Scalar!Meters(3000);
        enum zoomLevelCutoff = 0.15;

        // if (transform.zoomLevel >= zoomLevelCutoff) return;
        // shouldCheckMouseover = cell.bounds.withinRadiusOf(transform.cursorPos, transform.cursorRadius);
        // if (!shouldCheckMouseover) return;
        //
        float circRadius = r.tr.zoomBasedCirclePointRadius * 0.6;
        // float circRadius = 2.0;
        // circRadius *= circRadius;
        // circRadius /= 10;

        // writefln("%s, %s", circRadius, 1.0 / circRadius);
        if (!drawPoints || circRadius < 0.5) return;
        // if (circRadius <= 0) return;

        foreach (kv; cell.points.byKeyValue) {
            auto pt = kv.value;
            if (!viewBounds.contains(pt)) continue;

            bool mouseover = shouldCheckMouseover &&
                pt.withinRadiusOf(transform.cursorPos, transform.cursorRadius);
            auto color = mouseover ? mouseoverColor : defaultColor;
            // if (pt.withinRadiusOf(transform.cursorPos, pointsWithinRadius)) {
            r.drawPoint(pt, color, mouseover ? circRadius * 1.5 : circRadius);
            // }
            //
            if (mouseover) {
                // hack
                c.mouseover(FlexCellId(cell, kv.key, GeoType.Point));
            }
        }
    }

}
