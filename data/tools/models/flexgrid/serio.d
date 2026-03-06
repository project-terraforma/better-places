module models.flexgrid.serio;
import models.flexgrid.grid;
import models.flexgrid.grid;
import models.flexgrid.flexgeo;
import models.flexgrid.flexgeo.serio;
import msgpack;
import std;

struct FlexCellIntermediate {
    UUID[uint]          ids;
    ubyte[][uint]       geo;
    Point[uint]         points;
    FlexObject[uint]    objects;
    string[uint]        rawProps;
    AABB                bounds;
}
ubyte[] serializeBlob (FlexCell cell) {
    FlexCellIntermediate data;
    data.ids = cell.ids;
    foreach (kv; cell.geo.byKeyValue) {
        data.geo[kv.key] = kv.value.serialize();
    }
    data.points = cell.points;
    data.objects = cell.objects;
    data.rawProps = cell.rawProps;
    foreach (kv; cell.decodedProps.byKeyValue) {
        if (kv.key !in data.rawProps) {
            data.rawProps[kv.key] = kv.value.to!string;
        }
    }
    data.bounds = cell.bounds;
    return data.pack;
}
void load (FlexCell cell, ubyte[] dataBytes) {
    auto data = dataBytes.unpack!FlexCellIntermediate;
    cell.ids = data.ids;
    foreach (kv; data.geo.byKeyValue) {
        FlexGeo result;
        models.flexgrid.flexgeo.serio.load(result, kv.value);
        cell.geo[kv.key] = result;
        cell.geoBounds[kv.key] = result.bounds;
    }
    cell.points = data.points;
    cell.objects = data.objects;
    cell.rawProps = data.rawProps;
    data.bounds = cell.bounds;
}
