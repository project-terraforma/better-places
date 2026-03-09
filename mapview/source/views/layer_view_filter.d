module views.layer_view_filter;
import base;

enum DEFAULT_LAYER_COLOR = Colors.GREEN;
enum DEFAULT_LAYER_MOUSEOVER_COLOR = Colors.BLACK;

struct LayerViewInfo {
    bool  visible = true;
    Color color = DEFAULT_LAYER_COLOR;
    Color mouseoverColor = DEFAULT_LAYER_MOUSEOVER_COLOR;
}
class LayerViewFilter {
    FlexGrid            grid;
    LayerViewInfo[uint] layerInfo;

    this (FlexGrid grid)
        in { assert(grid !is null); }
        do { this.grid = grid; setupDefaultColors(); }

    private void setupDefaultColors () {
        setColors("omf.address",  Colors.ORANGE, DEFAULT_LAYER_MOUSEOVER_COLOR);
        setColors("omf.building", Colors.PURPLE, DEFAULT_LAYER_MOUSEOVER_COLOR);
        setColors("omf.place",    Colors.RED, DEFAULT_LAYER_MOUSEOVER_COLOR);
    }

    LayerViewInfo* get (uint id) { return id in layerInfo; }
    LayerViewInfo* get (string name) {
        auto gridLayer = grid.tryGetLayer(name);
        return gridLayer ? get(gridLayer.id) : null;
    }
    auto getPropOr(alias getterDg,T,TLayerId)(TLayerId id, lazy T orElseValue) {
        auto existing = get(id);
        return existing ? getterDg(*existing) : orElseValue;
    }
    ref LayerViewInfo getOrInsert(uint id) {
        auto existing = id in layerInfo;
        return existing ? *existing : (layerInfo[id] = LayerViewInfo());
    }
    ref LayerViewInfo getOrInsert(string name) {
        return this.getOrInsert(grid.getOrCreateLayer(name).id);
    }
    void setVisible (TLayer)(TLayer layer, bool visible) {
        this.getOrInsert(layer).visible = visible;
    }
    bool isVisible (TLayer)(TLayer layerId) {
        auto info = get(layerId);
        return info ? info.visible : false;
    }
    void setVisible(string[] layerNames, bool visible) {
        foreach (layer; layerNames) setVisible(layer, visible);
    }
    Color getColor(TLayer)(TLayer layerId, bool mouseover) {
        auto info = get(layerId);
        if (info) {
            return mouseover ? info.mouseoverColor : info.color;
        } else {
            return mouseover ? DEFAULT_LAYER_COLOR : DEFAULT_LAYER_MOUSEOVER_COLOR;
        }
    }
    void setColors (TLayer)(TLayer layerId, Color c1, Color c2) {
        auto layer = &getOrInsert(layerId);
        layer.color = c1;
        layer.mouseoverColor = c2;
    }
    void setColors(TLayer)(TLayer layerId, Color c) {
        setColors(layerId, c, DEFAULT_LAYER_MOUSEOVER_COLOR);
    }
}
