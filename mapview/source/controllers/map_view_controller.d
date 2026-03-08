module controllers.map_view_controller;
import views.renderer;
import views.map_view;
import base;
import std;

class MapViewController {
public:
    FlexGrid grid;
    MapView  view;
    Renderer r;
    FlexCellId[] mouseoverIds;
    FlexCellId[] selectedIds;

    // overall view bounds
    auto vb0 = TAABB!PolarDeg(
        TPoint!PolarDeg(-122.081623,36.946668),
        TPoint!PolarDeg(-121.932878,37.003170)
    );
    double zoomLevel    = 0.2;
    double minZoomLevel = -5; // exponents
    double maxZoomLevel = +3;

    AABB viewBounds; // current view bounds
    bool draggingView = false;
    Point dragViewStart;
    Point viewPos = Point(0, 0);
    Point viewVel = Point(0, 0);

    struct LayerView {
        bool visible = true;
        Color color = Colors.GREEN;
        Color mouseoverColor = Colors.BLACK;
    }
    LayerView[uint] layerViews;

    this (FlexGrid grid, MapView view, Renderer r) {
        this.grid = grid;
        this.view = view;
        this.r = r;
        assert(view.grid is grid);

        resetViewBounds();
    }

    void onLoaded (FlexGrid grid, AABB bounds) {
        assert(grid == this.grid);
        this.viewBounds = bounds;
        resetViewBounds();
    }

    AABB[] guiRects;
    Rectangle layoutGuiRect (float x, float y, float w, float h) {
        guiRects ~= AABB(Point(x, y), Point(x+w, y+h));
        return Rectangle(x, y, w, h);
    }
    void drawGui () {
        guiRects.length = 0;
        import raygui;
        auto showGridBackgroundLayer = grid.getOrCreateLayer("show-grid-background").id;
        float x = 40, y = 30;
        GuiPanel(layoutGuiRect(x,y,500,200), "layers");
        x += 5; y += 30;

        foreach (layer; grid.layers.byValue) {
            if (layer.id !in layerViews) {
                layerViews[layer.id] = LayerView();
            }
            auto visible = layerViews[layer.id].visible;
            auto r = Rectangle(x, y, 25, 25);
            auto msg = "%s: %s\0".format(layer.name, layer.id);

            auto selected = GuiCheckBox(r, msg.ptr, &visible);
            layerViews[layer.id].visible = visible;
            y += 35;
        }
        // drawGridRects = layerViews[showGridBackgroundLayer].visible;

        y += 40; auto y0 = y; auto panelWidth = 300;
        if (selectedIds.length) {
            GuiPanel(layoutGuiRect(x,y,panelWidth,1000), "selected");
            foreach (id; selectedIds) {
                y += 30;
                auto layerName = grid.layers[id.cell.layer].name;
                GuiLabel(Rectangle(x,y,panelWidth, 30), "%s %s\0".format(id.geoType, layerName).ptr);
            }
        }
        if (selectedIds.length) {
             y = y0; x += panelWidth + 20;
        }
        if (mouseoverIds.length) {
            GuiPanel(layoutGuiRect(x,y,500,400), "mouseover");
            foreach (id; mouseoverIds) {
                y += 30;
                auto layerName = grid.layers[id.cell.layer].name;
                GuiLabel(Rectangle(x,y,panelWidth, 30), "%s %s\0".format(id.geoType, layerName).ptr);
            }
        }
    }
    bool isMouseInUI() {
        auto mouseXY = GetMousePosition();
        auto mp = Point(mouseXY.x, mouseXY.y);
        foreach (rect; guiRects) {
            if (rect.contains(mp)) return true;
        }
        return false;
    }

    @property AABB viewPosLimits () const {
        return vb0.to!PolarNorm.scaledAroundCenter(10.0);
    }
    void resetViewBounds() {
        this.viewBounds = vb0.to!PolarNorm.scaledAroundCenter(0.4);
    }

    private void updateMouseover() {
        scope(exit) mouseoverIds.length = 0;
        if (IsMouseButtonPressed(0) && !isMouseInUI) {
            selectedIds = mouseoverIds;
        }
    }
    void mouseover (FlexCellId id) {
        mouseoverIds ~= id;
    }

    void textf(TArgs...)(TArgs args) { r.textf(args); }

    private void updateView (bool dragView, double relZoom) {

        if (IsKeyPressed(KeyboardKey.KEY_R)) {
            resetViewBounds();
        }

        auto bounds = viewBounds;
        auto viewSpanWorld = bounds.size;

        auto w = GetScreenWidth(), h = GetScreenHeight();
        auto mousePosScreen = GetMousePosition();
        auto mousePosNorm   = Vector2(mousePosScreen.x / w, 1 - mousePosScreen.y / h);

        double dt = GetFrameTime();

        auto prevZoom = this.zoomLevel;
        auto nextZoom = (this.zoomLevel - relZoom).clamp(minZoomLevel, maxZoomLevel);
        relZoom = nextZoom - prevZoom;
        this.zoomLevel = nextZoom;

        textf("bounds %s", bounds);
        textf("mousePosNorm %s", mousePosNorm);
        textf("zoom: %s => %s = %s", prevZoom, nextZoom, relZoom);

        auto relZoomScale = pow(4, relZoom);
        textf("=> rel zoom %s", relZoomScale);

        if (relZoom) {
            bounds.minv.x += mousePosNorm.x * viewSpanWorld.x * (1 - relZoomScale);
            bounds.minv.y += (1-mousePosNorm.y) * viewSpanWorld.y * (1 - relZoomScale);

            bounds.maxv.x = bounds.minv.x + viewSpanWorld.x * relZoomScale;
            bounds.maxv.y = bounds.minv.y + viewSpanWorld.y * relZoomScale;
        }
        if (dragView) {
            auto mouseScreenDelta = GetMouseDelta();
            auto mouseNormDelta = Point( mouseScreenDelta.x / w, -mouseScreenDelta.y / h );
            auto mouseDeltaWorld = Point(
                -mouseNormDelta.x * viewSpanWorld.x,
                -mouseNormDelta.y * viewSpanWorld.y
            );
            textf("mouse delta: %s => %s", mouseNormDelta, mouseDeltaWorld);
            bounds.minv.x += mouseDeltaWorld.x;
            bounds.minv.y += mouseDeltaWorld.y;
            bounds.maxv.x += mouseDeltaWorld.x;
            bounds.maxv.y += mouseDeltaWorld.y;
            this.viewVel = Point( mouseDeltaWorld.x / dt, mouseDeltaWorld.y / dt );
        } else {
            viewVel.x *= (1 - 0.5 * dt);
            viewVel.y *= (1 - 0.5 * dt);

            bounds.minv.x += viewVel.x * dt;
            bounds.minv.y += viewVel.y * dt;
            bounds.maxv.x += viewVel.x * dt;
            bounds.maxv.y += viewVel.y * dt;
        }
        this.viewBounds = bounds;
        assert(view !is null);
        this.view.view = bounds;
    }
    void update () {
        textf("view bounds: %s", viewBounds.to!PolarDeg);
        textf("view size:   %s", viewBounds.size.to!PolarDeg);

        textf("view bounds: %s", viewBounds);
        textf("view size:   %s", viewBounds.size.to!Meters);

        float dt = GetFrameTime();
        textf("dt: %s", dt);
        textf("FPS: %s", 1/dt);

        // handle mouse dragging
        bool isDragDown = IsMouseButtonDown(0) || IsMouseButtonDown(2);
        bool startDrag = false; // ignore 1st frame of mouse drag
        if (!draggingView && isDragDown) {
            draggingView = true;
            startDrag = true;
        } else if (draggingView && !isDragDown) {
            draggingView = false;
        }
        float scroll = GetMouseWheelMove();
        textf("scroll: %s", 100 * scroll * dt);

        auto wsz = Vector2(GetScreenWidth(), GetScreenHeight());
        auto mp = GetMousePosition();
        auto mr = Vector2( mp.x / wsz.x, 1 - mp.y / wsz.y );
        textf("mouse (pixel): %s", mp);
        textf("mouse (rel):   %s", mr);

        double zoomRel = 0;
        if (scroll) {
            // adjust view size: bigger or smaller
            enum SCROLL_SENSITIVITY = 5.0;
            enum USE_DT = true;
            auto clampedDt = min(dt, 1/30);
            double scrollInput = cast(double)scroll * dt * SCROLL_SENSITIVITY;
            // this.zoomLevel += scrollInput;
            zoomRel = scrollInput;

            writefln("raw input %s => input %s => scale %s => zoom %s",
                scroll, scrollInput, (1.0 - scrollInput) * 100, zoomLevel);

        }
        updateView(draggingView && !startDrag, zoomRel);
    }
}
