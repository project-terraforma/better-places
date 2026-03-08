module views.map_view;
import views.view_transform;
import views.layer_view_filter;
import views.entity_view_filter;
import views.renderer;
import base;

import controllers.map_view_controller; // hack

class MapView {
public:
    FlexGrid            grid;
    AABB                view;
    LayerViewFilter     layerFilters;
    EntityViewFilter    entityFilters;

    bool                drawStrictGridCellBounds;
    Color               drawStrictGridCellBoundsColor = Colors.BLUE;

    bool                drawCellBounds;
    Color               drawCellBoundsColor = Colors.RED;

    bool                drawPoints = true;

    enum GridCellBoundsCheck { UseCellBounds, UseGridBounds }
    // enum gridCellBoundsCheck = GridCellBoundsCheck.UseCellBounds;
    enum gridCellBoundsCheck = GridCellBoundsCheck.UseGridBounds;

    this (FlexGrid grid, AABB viewBounds)
        in { assert(grid !is null); }
        do {
            this.grid = grid;
            this.layerFilters = new LayerViewFilter(grid);
            this.entityFilters = new EntityViewFilter(grid);
        }
    void render (Renderer r, MapViewController c) {
        foreach (layer; grid.layers.byValue) {
            if (!layerFilters.isVisible(layer.id)) continue;
            foreach (kv; layer.cells.byKeyValue) {
                auto cell = kv.value;
                auto gridCellBounds = kv.key.bounds;

                static if (gridCellBoundsCheck == GridCellBoundsCheck.UseGridBounds) {
                    bool inBounds = view.contains(gridCellBounds);
                } else {
                    bool inBounds = view.contains(cell.bounds);
                }
                if (!inBounds) continue;

                if (drawStrictGridCellBounds) {
                    r.drawRect(gridCellBounds, drawStrictGridCellBoundsColor);
                }
                if (drawCellBounds) {
                    r.drawRect(cell.bounds, drawCellBoundsColor);
                }
                drawCell(layer.id, cell, r, c);
            }
        }
    }
private:
    void drawCell (uint layer, FlexCell cell, Renderer r, MapViewController c) {
        auto viewBounds = view;
        if (!viewBounds.contains(cell.bounds)) return;

        auto transform = r.tr; // ahck

        // auto q = models.flexgrid.flexgeo.iteration.withinRadiusOf(transform.cursorPos, transform.cursorRadius);
        // auto q = DummyQuery();
        bool shouldCheckMouseover = cell.bounds.withinRadiusOf(transform.cursorPos, transform.cursorRadius);

        auto defaultColor = layerFilters.getColor(layer, false);
        auto mouseoverColor = layerFilters.getColor(layer, true);

        foreach (kv; cell.geoBounds.byKeyValue) {
            auto bounds = kv.value;
            if (!viewBounds.contains(bounds)) continue;
            import models.geometry.algorithms: withinRadiusOf;
            bool mouseover = shouldCheckMouseover&& bounds.withinRadiusOf(transform.cursorPos, transform.cursorRadius);
            // bool mouseover = bounds.contains(transform.cursorPos);
            auto color = mouseover ? defaultColor : mouseoverColor;
            r.draw(bounds, color, 1);
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
        if (!drawPoints) return;

        foreach (kv; cell.points.byKeyValue) {
            auto pt = kv.value;
            if (!viewBounds.contains(pt)) continue;

            bool mouseover = shouldCheckMouseover &&
                pt.withinRadiusOf(transform.cursorPos, transform.cursorRadius);
            auto color = mouseover ? defaultColor : mouseoverColor;
            // if (pt.withinRadiusOf(transform.cursorPos, pointsWithinRadius)) {
            r.drawPoint(pt, color, mouseover ? 6.0f : 3.0f);
            // }
            //
            if (mouseover) {
                // hack
                c.mouseover(FlexCellId(cell, kv.key, GeoType.Point));
            }
        }
    }

}
