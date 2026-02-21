import raylib;
import models.omf;
import models.geojson;
import models.geometry;
import std;

void main(string[] args) {
    auto exeDir = args[0].dirName;
    scope mapview = new MapView(exeDir);
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
    shared OmfDataset data;
    shared bool dataLoaded = false;
    shared bool dataLoading = false;
public:
    Throwable dataLoadErr = null;

    // overall view bounds
    AABB vb0 = AABB(
        Point(-122.081623,36.946668),
        Point(-121.932878,37.003170)
    );
    double zoomLevel    = 0.2;
    double minZoomLevel = -5; // exponents
    double maxZoomLevel = +2;

    AABB viewBounds; // current view bounds

    this (string exeDir) { this.exeDir = exeDir; this.r = new MapRenderer(); }
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
        if (data) {
            r.render(this);
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

    void update () {
        textf("view bounds: %s", viewBounds);

        float dt = GetFrameTime();
        textf("dt: %s", dt);
        textf("FPS: %s", 1/dt);

        float scroll = GetMouseWheelMove();
        textf("scroll: %s", 100 * scroll * dt);

        auto wsz = Vector2(GetScreenWidth(), GetScreenHeight());
        auto mp = GetMousePosition();
        auto mr = Vector2( mp.x / wsz.x, 1 - mp.y / wsz.y );
        textf("mouse (pixel): %s", mp);
        textf("mouse (rel):   %s", mr);

        auto viewSz = Point(
            viewBounds.maxv.x - viewBounds.minv.x,
            viewBounds.maxv.y - viewBounds.minv.y
        );
        auto viewCenter = Point(
            (viewBounds.maxv.x + viewBounds.minv.x) * 0.5,
            (viewBounds.maxv.y + viewBounds.minv.y) * 0.5
        );
        textf("view size: %s", viewSz);
        textf("view center: %s", viewCenter);

        if (scroll) {
            // adjust view size: bigger or smaller
            enum SCROLL_SENSITIVITY = 5.0;
            enum USE_DT = true;
            auto clampedDt = min(dt, 1/30);
            double scrollInput = cast(double)scroll * dt * SCROLL_SENSITIVITY;
            this.zoomLevel += scrollInput;

            writefln("raw input %s => input %s => scale %s => zoom %s",
                scroll, scrollInput, (1.0 - scrollInput) * 100, zoomLevel);

            auto clamped = zoomLevel.clamp(minZoomLevel, maxZoomLevel);
            if (clamped != zoomLevel) {
                writefln("CLAMP: %s => %s", zoomLevel, clamped);
            }
            zoomLevel = clamped;
        }
        textf("zoom = %s (%s)", this.zoomLevel, std.math.log(zoomLevel));
        this.viewBounds = this.vb0.scaledAroundCenter(pow(10, -this.zoomLevel));

        if (data) {
            auto tr = MapRenderer.ViewTransform(cast(MapView)this);
            textf("cursor pos: %s", tr.cursorPos);
        }
    }
}

struct MapLoader {
    string exeDir;
    void load (shared MapView view, ref shared OmfDataset outData, string dataPath = "data/omf/santa_cruz") {
        writefln("loading dataset '%s'", dataPath);
        writefln("current directory: %s", exeDir);

        dataPath = buildPath("..", dataPath);

        enforce(dataPath.exists, "can't located dataset directory '%s'".format(dataPath));
        foreach(file; [".bounds.txt"]~["address", "building", "building_part", "place"]
            .map!(part => part~".geojson").array
        ) {
            auto path = dataPath.buildPath(file);
            enforce(path.exists, "missing file '%s'".format(path));
        }
        auto data = new OmfDataset().loadGeoJson(dataPath);
        outData = cast(shared OmfDataset)data;
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
    }
    void render (MapView view) {
        auto data = view.data;
        if (!data) {
            textf("MISSING MAP OBJECT!");
        } else {
            render(view, cast(const(OmfDataset))data);
        }
    }
    void render (MapView view, const(OmfDataset) data) {
        assert(data !is null);
        auto tr = ViewTransform(view);
        static foreach (part; data.PARTS) {
            render(view, mixin("data."~part), tr);
        }
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
    void draw (Point p, Color color, ViewTransform tr) {
        if (!tr.viewBounds.contains(p)) return;
        DrawPoly(
            tr.transform(p), 3, 10, 0, color
        );
    }
    struct CachedGeometry {
        AABB    bounds;
        Point[] points;
        uint[]  rings;

        this (const Polygon p) {
            assert(p.rings.length);
            assert(p.rings[0].points.length);
            this.bounds = AABB(p.rings[0].points[0]);
            foreach (ring; p.rings) insert(ring);
        }
        this (const MultiPolygon p) {
            assert(p.polygons.length);
            assert(p.polygons[0].rings.length);
            assert(p.polygons[0].rings[0].points.length);
            this.bounds = AABB(p.polygons[0].rings[0].points[0]);
            foreach (poly; p.polygons) {
                foreach (ring; poly.rings) {
                    insert(ring);
                }
            }
        }
        private void insert(const Ring r) {
            assert(r.points.length);
            if (!r.points.length) return;
            this.points ~= r.points;
            this.rings ~= cast(uint)r.points.length;
            foreach (p; r.points) this.bounds.grow(p);
        }
        void draw (MapRenderer r, Color color, ViewTransform tr, float lineThickness = 1) {
            uint start = 0;
            foreach (ring; this.rings) {
                uint n = ring, end = start + n;
                assert(n > 0);
                Vector2 p0 = tr.transform(this.points[start]);
                Vector2 a = p0;
                for (uint i = start + 1; i < end; ++i) {
                    Vector2 b = tr.transform(this.points[i]);
                    DrawLineEx(a, b, lineThickness, color);
                    a = b;
                }
                // DrawLineV(a, p0, color);
                start = end;
            }
        }
    }
    struct GeoCache {
        CachedGeometry[UUID] cache;
        AABB[UUID] boundsCache;

        ref CachedGeometry get (T)(ref const T item) {
            auto ptr = item.id in cache;
            if (!ptr) {
                auto newCachedGeometry = CachedGeometry(item.geo);
                boundsCache[item.id] = newCachedGeometry.bounds;
                return cache[item.id] = newCachedGeometry;
            }
            return *ptr;
        }
        AABB getBounds (T)(ref const T item) {
            auto ptr = item.id in boundsCache;
            return ptr ? *ptr : get(item).bounds;
        }
        bool inBounds (T)(ref const T item, ViewTransform tr) {
            return tr.viewBounds.contains(getBounds(item));
        }
    }
    GeoCache geoCache;

    void render (const MapView view, ref const Building item, ViewTransform tr) {
        if (!geoCache.inBounds(item, tr)) return;
        CachedGeometry* g = &(geoCache.get(item));
        if (tr.viewBounds.contains(g.bounds)) {
            bool mouseover = false;
            float boundsLineThickness = 1;
            float polyLineThickness = 1;
            enum MOUSEOVER_LINE_THICKNESS = 3;
            if (g.bounds.contains(tr.cursorPos)) {
                boundsLineThickness = MOUSEOVER_LINE_THICKNESS;
                mouseover = item.geo.contains(tr.cursorPos);
                if (mouseover) {
                    polyLineThickness = MOUSEOVER_LINE_THICKNESS;
                }
            }
            draw(g.bounds, Colors.RED, tr, boundsLineThickness);
            g.draw(this, Colors.BLUE, tr, polyLineThickness);

            if (mouseover) {
                textf("Building %s", item.id);
                foreach (kv; item.props.byKeyValue) {
                    textf("%s: %s", kv.key, kv.value);
                }
            }
        }
        // draw(item.geo, Colors.GREEN, tr);
    }
    void render (const MapView view, ref const BuildingPart item, ViewTransform tr) {
        draw(item.geo, Colors.BLUE, tr);
    }
    void render (const MapView view, ref const Place item, ViewTransform tr) {
        // draw(item.geo, Colors.RED, tr);
    }
    void render (const MapView view, ref const models.omf.Address item, ViewTransform tr) {
        // draw(item.geo, Colors.PURPLE, tr);
    }
}
