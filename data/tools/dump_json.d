#!/usr/bin/env rdmd
import models.geojson;
import models.omf;
import std;

void main (){
    // foreach (file; [
    //     "building",
    //     "building_part",
    //     "place"
    // ]) {
    //     dump(buildPath("data/omf/santa_cruz", "%s.geojson".format(file)));
    // }
    dump(new OmfDataset().loadGeoJson("data/omf/santa_cruz"));
}
void dump (OmfDataset data) {
    // collect and print interesting statistics
    // MOVED TO `summarize_omf.d`
    // static foreach (part; data.PARTS) {
    //     dumpSummary(data, part, mixin("data."~part));
    // }

    // detailed dump
    static foreach (part; data.PARTS) {
        dumpDetails(data, part, mixin("data."~part));
    }
}

void dumpDetails (T)(OmfDataset data, string name, ref OmfCollection!T part) {
    writefln("%s: %s", name, part.length);
    foreach (item; part.items.byValue) {
        writefln("\n\t%s", item.id);
        writefln("\n\t\t%s", summarizeGeometry(item.geo));
        // writefln("\n\t\tGeometry: %s\n\t\t\t%s", item.Geometry.stringof, item.geo);
        foreach (kv; item.props.byKeyValue) {
            writef("\t\tprops.%s: ", kv.key);
            dump(kv.value, 2);
        }
    }
    writefln("%s: %s", name, part.length);
}
string summarizeGeometry (Point p) {
    return "Point: (%s, %s)".format(p.x, p.y);
}
string summarizeGeometry (Polygon p) {
    return "Polygon: rings = %s, shape = %s"
        .format(p.rings.length, p.rings.map!(r => r.points.length));
}
string summarizeGeometry (MultiPolygon p) {
    switch (p.polygons.length) {
        case 0: return "MultiPolygon: (empty)!";
        case 1: return p.polygons[0].summarizeGeometry;
        default: return "MultiPolygon: polygons = %s, shape = %s"
            .format(p.polygons.length, p.polygons.map!(
                poly => poly.rings.map!(r => r.points.length).array
            ).array);
    }
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
