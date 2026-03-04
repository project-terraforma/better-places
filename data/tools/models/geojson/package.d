module models.geojson;
public import models.geometry;
public import models.utils;
public import std.json;
import std.algorithm;
import std.array;
import std;

alias Geometry = TGeometry!PolarDeg;
alias Point = Geometry.Point;
alias AABB = Geometry.AABB;
alias Ring = Geometry.Ring;
alias Polygon = Geometry.Polygon;
alias MultiPolygon = Geometry.MultiPolygon;

struct FeatureCollection {
    Feature[] features;
}
struct Feature {
    Geometry geo;
    JSONValue[string] props;
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
    auto rawId = props["id"].str
        .annotateErr(
            "invalid or missing expected string 'id'\n\tin `%s`\n\t(has keys `%s`)!"
            .format(props, props.keys));
    auto geo = v["geometry"].parseGeometry;
    return Feature(geo, props);
}

FeatureCollection parseFeatures (JSONValue v) {
    enforce(v.type == JSONType.object && v["type"].str == "FeatureCollection");
    FeatureCollection result;
    foreach (feature; v["features"].array) {
        auto f = feature.parseFeature();
        result.features ~= f;
    }
    return result;
}
