import raylib;
import models.omf;
import models.geojson;
import models.geometry;
import models.flexgrid;
import models.flexgrid.flexgeo;
import models.flexgrid.flexstore;
import models.flexgrid_plugins.flexgrid_viewer;
import std;

alias Geometry = TGeometry!PolarNorm;
alias Point = Geometry.Point;
alias Ring = Geometry.Ring;
alias AABB = Geometry.AABB;
alias Polygon = Geometry.Polygon;
alias MultiPolygon = Geometry.MultiPolygon;


// alias Geometry = models.geojson.Geometry;
// alias Point = Geometry.Point;
// alias Ring = Geometry.Ring;
// alias AABB = Geometry.AABB;
// alias Polygon = Geometry.Polygon;
// alias MultiPolygon = Geometry.MultiPolygon;

void main(string[] args) {
    auto exeDir = args[0].dirName;
    scope grid = new FlexGrid();
    scope viewer = new Viewer(grid);
    scope mapview = new MapView(exeDir, grid, viewer);
    mapview.loadAsync();

    // call this before using raylib
    validateRaylibBinding();
    InitWindow(800, 600, "better-places map viewer (rough prototype)");
    SetTargetFPS(60);
    while (!WindowShouldClose())
    {
        BeginDrawing();
        ClearBackground(Colors.RAYWHITE);
        mapview.render();
        // DrawText("Hello, World!", 400, 300, 28, Colors.BLACK);
        EndDrawing();
    }
    CloseWindow();
}

void loadMap (shared MapView v) { v.doLoadAsync(); }

class MapView {
    string exeDir;
    MapRenderer r;
    FlexGrid    grid;
    Viewer      gridViewer;
    shared OmfDataset data;
    shared bool dataLoaded = false;
    shared bool dataLoading = false;
public:
    Throwable dataLoadErr = null;

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

    this (string exeDir, FlexGrid grid, Viewer gridViewer) {
        this.exeDir = exeDir;
        this.grid = grid;
        this.gridViewer = gridViewer;
        this.r = new MapRenderer();
        resetViewBounds();
    }

    @property AABB viewPosLimits () const {
        return vb0.to!PolarNorm.scaledAroundCenter(10.0);
    }
    void resetViewBounds() {
        this.viewBounds = vb0.to!PolarNorm.scaledAroundCenter(0.4);
    }

    void loadAsync(){
        enforce(!dataLoading);
        dataLoading = true;
        // spawn((v) => v.doLoadAsync(), this);
        auto tid = spawn(&loadMap, cast(shared MapView)this);
    }
    private void doLoadAsync () shared {
        assert(!dataLoaded);
        assert(dataLoading);
        this.dataLoadErr = null;
        scope(exit){
            dataLoaded = true; dataLoading = false;
            writefln("finished load\n\tdata = %s\n\terr = %s\n\tloaded = %s, loading = %s"
                , data, dataLoadErr, dataLoaded, dataLoading);
        }
        try {
            this.data = null;
            MapLoader(exeDir).load(this, this.data);
        } catch (Throwable e) {
            writefln("DATA LOAD ERROR: %s", e);
            *(cast(Throwable*)&this.dataLoadErr) = e;
        }
    }
    void render () {
        r.newFrame();
        update();
        if (dataLoaded) {
            gridViewer.view = viewBounds;
            r.render(this, gridViewer);
        } else {
            if (dataLoadErr) {
                ClearBackground(Color(100,50,50,255));
                r.text("Map load error:\n%s".format(dataLoadErr), 20, 20, Colors.WHITE);
            } else if (dataLoading) {
                r.text("Loading...");
            } else {
                r.text("...map not loaded??");
            }
        }
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
            auto mouseNormDelta = Point( mouseScreenDelta.x / w, mouseScreenDelta.y / h );
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
        assert(gridViewer !is null);
        this.gridViewer.view = bounds;
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
        bool startDrag = false; // ignore 1st frame of mouse drag
        if (!draggingView && IsMouseButtonDown(0)) {
            draggingView = true;
            startDrag = true;
        } else if (draggingView && !IsMouseButtonDown(0)) {
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

struct MapLoader {
    string exeDir;
    void load (shared MapView view, ref shared OmfDataset outData, string dataPath = "data/omf/santa_cruz") {
        auto grid = (cast(MapView)view).grid;

        auto dbPath = buildPath("..", "data", "flexgrid", "santa_cruz.db");
        if (dbPath.exists) {
            writefln("loading from sqlite '%s'", dbPath);
            scope store = new FlexStore!FlexStoreSqlite3Storage(dbPath, grid);
            store.load();
            return;
        }

        writefln("loading dataset '%s'", dataPath);
        writefln("current directory: %s", exeDir);
        dataPath = buildPath("..", dataPath);

        enforce(dataPath.exists, "can't locate dataset directory '%s'".format(dataPath));
        foreach (file; [".bounds.txt"] ~ ["address", "building", "building_part", "place"]
            .map!(part => part ~ ".geojson").array
        ) {
            auto path = dataPath.buildPath(file);
            enforce(path.exists, "missing file '%s'".format(path));
        }
        scope dataset = new OmfDataset().loadGeoJson(dataPath);
        static foreach (PART; OmfDataset.PARTS) {
            .load(grid, mixin("dataset." ~ PART), PART);
        }
        outData = cast(shared OmfDataset) dataset;
    }
}

// Load a single OMF collection into the grid as a named layer.
// Mirrors the equivalent function in pipeline/source/app.d.
void load (TPart)(FlexGrid grid, OmfCollection!TPart collection, string name) {
    auto layerName = "omf.%s".format(name);
    auto layerId   = grid.getOrCreateLayer(layerName).id;
    foreach (item; collection.items) {
        static if (__traits(compiles, item.pos)) {
            auto point = item.pos.to!PolarNorm;
            auto key   = FlexCellKey.from(point);
            auto cell  = grid.getOrCreateCell(key, layerId);
            cell.addPoint(item.id, point);
            auto id    = cell.getOrInsertId(item.id);
            cell.decodedProps[id] = item.props;
        } else {
            auto geo  = toFlexGeo(item.geo);
            auto key  = FlexCellKey.from(geo.bounds);
            auto cell = grid.getOrCreateCell(key, layerId);
            cell.addGeometry(item.id, geo);
            auto id   = cell.getOrInsertId(item.id);
            cell.decodedProps[id] = item.props;
        }
    }
}
class MapRenderer {
    Font font;
    bool loaded = false;
    int  textLayoutPosY = 0;
    int  fontSize = 24;

    void load () {
        if (loaded) return; loaded = true;
        // load fonts
        writefln("loading font");
        this.font = LoadFontEx("fonts/JetBrainsMono/JetBrainsMono-Regular.ttf", fontSize, null, 0);
        // this.font = LoadFont("fonts/JetBrainsMono-Regular.ttf");
        writefln(" => %s", this.font);
    }
    void textf(TArgs...)(string msg, TArgs args) {
        text(msg.format(args));
    }
    void text (string msg) {
        textLayoutPosY += fontSize;
        text(msg, 20, 20 + textLayoutPosY);
    }
    void text (string msg, int x, int y) {
        text(msg, x, y, Colors.BLACK);
    }
    void text (string msg, int x, int y, Color color) {
        if (msg.length < 4 * 1024) {
            char[4 * 1024] buf;
            import core.stdc.string: memcpy;
            memcpy(buf.ptr, msg.ptr, msg.length);
            buf[msg.length] = '\0';
            drawText(buf.ptr, x, y, color);
        } else {
            drawText(msg.toStringz, x, y, color);
        }
    }
    private void drawText (const(char)* msg, int x, int y, Color color) {
        if (!loaded) load();
        DrawTextEx(font, msg, Vector2(x, y), fontSize, 0, color);
    }
    void newFrame () {
        if (!loaded) load();
        textLayoutPosY = 0;
    }
    struct ViewTransform {
        AABB viewBounds;
        Point mapToScreenScale;
        Point mapToScreenOffset;
        Point cursorPos; // mouse cursor position, transformed into geo Point space
        float zoomLevel;
        float precalcZoomCircleRadius;
        Vector2 cursorPosScreenSpace;
        float precalcZoomCircleRad2;

        this (const MapView view) {
            this.viewBounds = view.viewBounds;
            auto screenSize = Point(GetScreenWidth(), GetScreenHeight());
            auto viewSize = Point(
                viewBounds.maxv.x - viewBounds.minv.x,
                viewBounds.maxv.y - viewBounds.minv.y
            );
            this.mapToScreenScale = Point(
                screenSize.x / viewSize.x,
                screenSize.y / viewSize.y,
            );
            this.mapToScreenOffset = viewBounds.minv;

            auto m = GetMousePosition();
            this.cursorPos = transformScreenToGeoSpace(m);
            // this.viewBounds = viewBounds.scaledAroundCenter(0.5); // for debugging view culling
            this.zoomLevel = cast(float)view.zoomLevel;
            this.precalcZoomCircleRadius = calcZoomCircleRadius(zoomLevel);
            this.cursorPosScreenSpace = m;
            this.precalcZoomCircleRad2 = precalcZoomCircleRadius * precalcZoomCircleRadius;
        }
        Point transformScreenToGeoSpace (Vector2 p) {
            return Point(
                (p.x / mapToScreenScale.x) + mapToScreenOffset.x,
                (p.y / mapToScreenScale.y) + mapToScreenOffset.y
            );
        }

        Vector2 transform (Point p) {
            p.x -= mapToScreenOffset.x;
            p.y -= mapToScreenOffset.y;
            p.x *= mapToScreenScale.x;
            p.y *= mapToScreenScale.y;
            return Vector2(p.x, p.y);
        }

        float zoomBasedCirclePointRadius () { return precalcZoomCircleRadius; }
        private float calcZoomCircleRadius(float zoomLevel) {
            // zoom goes from 2 (zoomed in) to -4 (zoomed out)
            auto z = (zoomLevel + 2) * 0.25;
            return z * z * 4;
        }
        bool mouseNearPoint(Vector2 screenSpacePoint) {
            float dx = screenSpacePoint.x - cursorPosScreenSpace.x;
            float dy = screenSpacePoint.y - cursorPosScreenSpace.y;
            dx *= dx; dy *= dy;
            enum MOUSE_NEAR_PX_RADIUS = 35;
            return dx + dy <= precalcZoomCircleRad2 + MOUSE_NEAR_PX_RADIUS*MOUSE_NEAR_PX_RADIUS;
        }
    }
    void render (MapView view, Viewer gridViewer) {
        auto tr = ViewTransform(view);
        gridViewer.render(this, tr);
    }
    void render (ViewTransform tr, Geometry g, Color c) {
        g.value.tryVisit!(
            (MultiPolygon p) => draw(p, c, tr),
            (Polygon p) => draw(p, c, tr),
            // (Point p) => draw(p, c, tr)
            (_) {}
        );
    }


    void render (T)(const MapView view, ref const(OmfCollection!T) data, ViewTransform tr) {
        foreach (kv; data.items.byKeyValue) {
            render(view, kv.value, tr);
        }
    }
    void drawLine(Point a, Point b, Color color, ViewTransform tr) {
        auto p1 = tr.transform(a), p2 = tr.transform(b);
        DrawLineV(p1, p2, color);
    }
    void draw (const Ring ring, Color color, ViewTransform tr) {
        size_t n = ring.points.length;
        for (size_t i = 1; i < n; ++i) {
            drawLine(ring.points[i-1], ring.points[i], color, tr);
        }
    }
    void draw (const Polygon p, Color color, ViewTransform tr) {
        foreach (ring; p.rings) {
            draw(ring, color, tr);
        }
    }
    void draw (const MultiPolygon mp, Color color, ViewTransform tr) {
        foreach (poly; mp.polygons) {
            draw(poly, color, tr);
        }
    }
    void draw (AABB r, Color color, ViewTransform tr, float lineThickness = 1) {
        if (!tr.viewBounds.contains(r)) return;
        auto a = tr.transform(r.minv), b = tr.transform(r.maxv);
        DrawLineEx(a, Vector2(b.x, a.y), lineThickness, color);
        DrawLineEx(a, Vector2(a.x, b.y), lineThickness, color);

        DrawLineEx(b, Vector2(a.x, b.y), lineThickness, color);
        DrawLineEx(b, Vector2(b.x, a.y), lineThickness, color);
    }
    // struct CachedGeometry {
    //     AABB    bounds;
    //     Point[] points;
    //     uint[]  rings;

    //     this (const Polygon p) {
    //         assert(p.rings.length);
    //         assert(p.rings[0].points.length);
    //         this.bounds = AABB(p.rings[0].points[0]);
    //         foreach (ring; p.rings) insert(ring);
    //     }
    //     this (const MultiPolygon p) {
    //         assert(p.polygons.length);
    //         assert(p.polygons[0].rings.length);
    //         assert(p.polygons[0].rings[0].points.length);
    //         this.bounds = AABB(p.polygons[0].rings[0].points[0]);
    //         foreach (poly; p.polygons) {
    //             foreach (ring; poly.rings) {
    //                 insert(ring);
    //             }
    //         }
    //     }
    //     private void insert(const Ring r) {
    //         assert(r.points.length);
    //         if (!r.points.length) return;
    //         this.points ~= r.points;
    //         this.rings ~= cast(uint)r.points.length;
    //         foreach (p; r.points) this.bounds.grow(p);
    //     }
    //     void draw (MapRenderer r, Color color, ViewTransform tr, float lineThickness = 1) {
    //         uint start = 0;
    //         foreach (ring; this.rings) {
    //             uint n = ring, end = start + n;
    //             assert(n > 0);
    //             Vector2 p0 = tr.transform(this.points[start]);
    //             Vector2 a = p0;
    //             for (uint i = start + 1; i < end; ++i) {
    //                 Vector2 b = tr.transform(this.points[i]);
    //                 DrawLineEx(a, b, lineThickness, color);
    //                 a = b;
    //             }
    //             // DrawLineV(a, p0, color);
    //             start = end;
    //         }
    //     }
    // }
    // struct GeoCache {
    //     CachedGeometry[UUID] cache;
    //     AABB[UUID] boundsCache;

    //     ref CachedGeometry get (T)(ref const T item) {
    //         auto ptr = item.id in cache;
    //         if (!ptr) {
    //             auto newCachedGeometry = CachedGeometry(item.geo);
    //             boundsCache[item.id] = newCachedGeometry.bounds;
    //             return cache[item.id] = newCachedGeometry;
    //         }
    //         return *ptr;
    //     }
    //     AABB getBounds (T)(ref const T item) {
    //         auto ptr = item.id in boundsCache;
    //         return ptr ? *ptr : get(item).bounds;
    //     }
    //     bool inBounds (T)(ref const T item, ViewTransform tr) {
    //         return tr.viewBounds.contains(getBounds(item));
    //     }
    // }
    // GeoCache geoCache;

    void render (const MapView view, ref const Building item, ViewTransform tr) {
        // if (!geoCache.inBounds(item, tr)) return;
        // CachedGeometry* g = &(geoCache.get(item));
        // if (tr.viewBounds.contains(g.bounds)) {
        //     bool mouseover = false;
        //     float boundsLineThickness = 1;
        //     float polyLineThickness = 1;
        //     enum MOUSEOVER_LINE_THICKNESS = 3;
        //     if (g.bounds.contains(tr.cursorPos)) {
        //         boundsLineThickness = MOUSEOVER_LINE_THICKNESS;
        //         mouseover = item.geo.contains(tr.cursorPos.to!Polar);
        //         if (mouseover) {
        //             polyLineThickness = MOUSEOVER_LINE_THICKNESS;
        //         }
        //     }
        //     draw(g.bounds, Colors.RED, tr, boundsLineThickness);

        //     uint src = 0;
        //     foreach (s; item.props["sources"].array) {
        //         switch (s.object["dataset"].str) {
        //             case "OpenStreetMap":           src |= 1; break;
        //             case "Microsoft ML Buildings":  src |= 2; break;
        //             default:
        //         }
        //     }
        //     immutable Color[4] COLORS_BY_SRC = [
        //         Colors.BLUE,
        //         Colors.ORANGE,
        //         Colors.PURPLE,
        //         Colors.GREEN
        //     ];
        //     g.draw(this, COLORS_BY_SRC[src], tr, polyLineThickness);

        //     if (mouseover) {
        //         textLayoutPosY += fontSize;
        //         textf("Building %s", item.id);
        //         foreach (kv; item.props.byKeyValue) {
        //             textf("%s: %s", kv.key, kv.value);
        //         }
        //     }
        // }
        // // draw(item.geo, Colors.GREEN, tr);
    }
    void render (const MapView view, ref const BuildingPart item, ViewTransform tr) {
        // draw(item.geo, Colors.BLUE, tr);
    }


    void draw (Point p, Color color, float radius, ViewTransform tr) {

        // if (!tr.viewBounds.contains(p)) return; // hosted this up into callees
        Vector2 pt = tr.transform(p);
        DrawCircleV(pt, radius, color);
        // DrawPixel(cast(int)pt.x, cast(int)pt.y, color);
        // DrawPoly(
        //     tr.transform(p), 3, 10, 0, color
        // );
    }

    void drawPoint (TPointItem)(const MapView view, ref const TPointItem item, ViewTransform tr, Color color) {
        float circRadius = tr.zoomBasedCirclePointRadius;
        if (circRadius <= 0) return;
        auto pos = item.pos.to!PolarNorm;
        if (!tr.viewBounds.contains(pos)) return;

        Vector2 pt = tr.transform(pos); // screenspace
        if (tr.mouseNearPoint(pt)) {
            circRadius *= 2;
            describeMouseover(view, item);
        }
        DrawCircleV(pt, circRadius, color);
    }
    void describeMouseover(const MapView view, ref const Place item) {
        textLayoutPosY += fontSize;
        textf("Place %s at %s", item.id, item.pos);
        foreach (kv; item.props.byKeyValue) {
            textf("%s = %s", kv.key, kv.value);
        }

    }
    void describeMouseover(const MapView view, ref const models.omf.Address item) {
        textLayoutPosY += fontSize;
        textf("Address %s at %s", item.id, item.pos);
        foreach (kv; item.props.byKeyValue) {
            textf("%s = %s", kv.key, kv.value);
        }
    }
    void render (const MapView view, ref const Place item, ViewTransform tr) {
        drawPoint(view, item, tr, Colors.RED);
    }
    void render (const MapView view, ref const models.omf.Address item, ViewTransform tr) {
        drawPoint(view, item, tr, Colors.GREEN);
    }
}
