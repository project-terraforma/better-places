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
    InitWindow(800, 600, "Hello, Raylib-D!");
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
        if (data) {
            r.render(this);
        } else {
            if (dataLoadErr) {
                ClearBackground(Color(100,50,50,255));
                r.text("Map load error:\n%s".format(dataLoadErr), 20, 20, Colors.WHITE);
            } else if (dataLoading) {
                ClearBackground(Colors.RAYWHITE);
                r.text("Loading...", 20, 20, Colors.BLACK);
            } else {
                r.text("...map not loaded??", 20, 20);
            }
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

    void load () {
        if (loaded) return; loaded = true;
        // load fonts
        writefln("loading font");
        this.font = LoadFontEx("fonts/JetBrainsMono-Regular.ttf", 24, null, 0);
        // this.font = LoadFont("fonts/JetBrainsMono-Regular.ttf");
        writefln(" => %s", this.font);
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
        DrawTextEx(font, msg, Vector2(x, y), 24, 0, color);
    }
    void render (MapView view) {
        if (!loaded) load();
        text("map rendering TBD!", 20, 20);
    }
}
