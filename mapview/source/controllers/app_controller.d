module controllers.app_controller;
import controllers.map_view_controller;
import controllers.map_loader;
import views;
import base;
import std;

class AppController {
    alias This = AppController;
    string[] args;
    string   dataset;

    FlexGrid          grid;
    MapViewController mapController;
    MapView           mapView;
    MapLoader         mapLoader;
    Renderer          renderer;
    Throwable         runtimeError = null;
    bool loaded = false;

    this(string[] args, string defaultDataset = "santa_cruz") {
        this.args = args;
        this.grid = new FlexGrid();
        this.args = args;
        parseArgs(args, defaultDataset);
        initialize();
        this.renderer = new Renderer();
    }
    private void parseArgs(string[] args, string defaultDataset) {
        if (args.length > 1) {
            dataset = args[1];
        } else {
            dataset = defaultDataset;
        }
    }
    private void initialize() {
        InitWindow(800, 600, "better-places map viewer (rough prototype)");
        SetTargetFPS(60);
    }
    This load () {
        mapLoader.load(grid, dataset, &onLoad, &onErr);
        renderer.load();
        return this;
    }
    This run () {
        scope(exit) CloseWindow();
        while (!WindowShouldClose()) {
            BeginDrawing();
            ClearBackground(Colors.RAYWHITE);
            update();
            render();
            EndDrawing();
        }
        return this;
    }
private:
    void update () {
        if (mapController) {
            mapController.update();
        }
    }
    void render () {
        renderer.newFrame();
        if (runtimeError !is null) {
            renderError(runtimeError);
        } else if (loaded) {
            assert(mapView !is null);
            mapController.update();
            // mapView.render(renderer);
            mapView.render(renderer, mapController); // hack
            mapController.drawGui();
        } else {
            renderer.textf("loading dataset %s", dataset);
        }
    }
    void renderError(Throwable err) {
        ClearBackground(Color(100,50,50,255));
        // ClearBackground(Colors.RED);
        renderer.text("Map load error:\n%s".format(err), 20, 20, Colors.WHITE);
        // renderer.textf("%s", err);
    }
    void onLoad (ref MapLoader loader, FlexGrid loadedGrid, AABB bounds) {
        assert(loadedGrid is this.grid);
        if (!mapView) {
            mapView = new MapView(grid, bounds);
        }
        if (!mapController) {
            mapController = new MapViewController(grid, mapView, renderer);
        }
        mapController.onLoaded(loadedGrid, bounds);
    }
    void onErr (Throwable err) {
        this.runtimeError = err;
    }
}
