#!/usr/bin/env rdmd
import std;

struct FeatureCollection {
    Feature[] features;
    Feature[UUID] features_by_id;
}
struct Feature {
    UUID     id;
    Geometry geo;
    JSONValue[string] props;
}
// struct Geometry {
//     Point[] coords;
//     Type    type;
//     enum Type { Point, Polygon }
// }
struct Point { float x = 0, y = 0; }
struct Ring  { Point[] points; }
struct Polygon { Ring[] rings; }
struct MultiPolygon { Polygon[] polygons; }

alias Geometry = Algebraic!(Point, Polygon, MultiPolygon);


T annotateErr (T)(lazy T expr, lazy string msg, string file = __FILE__, size_t line = __LINE__) {
    try {
        return expr;
    } catch (Throwable e) {
        throw new Exception(msg, file, line, e);
    }
}

Geometry parseGeometry (JSONValue v) {
    enforce(v.type == JSONType.object);
    switch (v["type"].str) {
        case "Point":   return Geometry(v["coordinates"].parsePoint.annotateErr("in (type = %s) %s".format(v["type"], v))); break;
        case "Polygon": return Geometry(v["coordinates"].parsePolygon.annotateErr("in (type = %s) %s".format(v["type"], v))); break;
        case "MultiPolygon": return Geometry(v["coordinates"].parseMultiPolygon.annotateErr("in (type = %s) %s".format(v["type"], v))); break;
        default: enforce(false, "unhandled geometry type %s".format(v));
    }
    assert(0);
}
Point parsePoint (JSONValue v) {
    assert(v.type == JSONType.array && v.array.length == 2, "invalid point: %s!".format(v));
    return Point(v.array[0].floating, v.array[1].floating);
}
Ring parseRing (JSONValue v) {
    assert(v.type == JSONType.array);
    return Ring(v.array.map!parsePoint.array.annotateErr("in ring '%s'".format(v)));
}
Polygon parsePolygon (JSONValue v) {
    assert(v.type == JSONType.array);
    return Polygon(v.array.map!parseRing.array.annotateErr("in polygon '%s'".format(v)));
}
MultiPolygon parseMultiPolygon (JSONValue v) {
    assert(v.type == JSONType.array);
    return MultiPolygon(v.array.map!parsePolygon.array.annotateErr("in multipolygon '%s'".format(v)));
}
Feature parseFeature (JSONValue v) {
    assert(v.type == JSONType.object && v["type"].str == "Feature");
    auto props = v["properties"].object;
    auto rawId = props["id"].str;
    auto id = rawId.parseUUID.annotateErr("invalid id '%s'!".format(rawId));
    auto geo = v["geometry"].parseGeometry;
    return Feature(id, geo, props);
}

FeatureCollection parseFeatures (JSONValue v) {
    enforce(v.type == JSONType.object && v["type"].str == "FeatureCollection");
    FeatureCollection result;
    foreach (feature; v["features"].array) {
        auto f = feature.parseFeature();
        result.features ~= f;
        enforce(f.id !in result.features_by_id, "duplicate feature id! %s".format(f.id));
        result.features_by_id[f.id] = f;
    }
    return result;
}

void main (){
    foreach (file; [
        "building",
        "building_part",
        "place"
    ]) {
        dump(buildPath("data/omf/santa_cruz", "%s.geojson".format(file)));
    }
}
void dump(string path) {
    auto file = path.readText;
    auto data = file.parseJSON;
    writefln("%s: %s", path, data.type);
    // dump(data, 0);
    auto res = data.parseFeatures();
    writefln("%s features", res.features.length);

    size_t point_count = 0, poly_count = 0, multi_count = 0;
    foreach (feature; res.features) {
        feature.geo.visit!(
            (Point p) { ++point_count; },
            (Polygon p){ ++poly_count; },
            (MultiPolygon p) { ++multi_count; }
        );
        writefln("\n\t%s", feature.id);
        foreach (kv; feature.props.byKeyValue) {
            writef("\t\tprops.%s: ", kv.key);
            dump(kv.value, 2);
        }
    }
    if (point_count) writefln("\tPoints: %s", point_count);
    if (poly_count) writefln("\tPolygons: %s", poly_count);
    if (multi_count) writefln("\tMultiPolygons: %s", multi_count);
}
void dump(JSONValue v, uint level) {
    writef("%s", v.type);
    final switch (v.type) {
        case JSONType.null_: writefln(" <null>"); break;
        case JSONType.string:
            if (v.str.length < 30) writefln(" '%s'", v.str);
            else writefln(" '%s' [... %s bytes]", v.str[0..20], v.str.length);
            break;
        case JSONType.integer: writefln(" %s", v.integer); break;
        case JSONType.uinteger: writefln(" %s", v.uinteger); break;
        case JSONType.float_: writefln(" %s", v.floating); break;
        case JSONType.true_: writeln(); break;
        case JSONType.false_: writeln(); break;
        case JSONType.array: writeln();
            ++level;
            foreach (k, val; v.array) {
                for (uint i = level; i --> 0; ) write('\t');
                writef("[%s]: ", k);
                dump(val, level);
            }
            break;
        case JSONType.object: writeln();
            ++level;
            foreach (kv; v.object.byKeyValue) {
                for (uint i = level+1; i --> 0; ) write('\t');
                writef("'%s': ", kv.key);
                dump(kv.value, level);
            } break;
    }
}
