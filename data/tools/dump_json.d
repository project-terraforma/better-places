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
    static foreach (part; data.PARTS) {
        dumpSummary(data, part, mixin("data."~part));
    }

    // detailed dump
    static foreach (part; data.PARTS) {
        dumpDetails(data, part, mixin("data."~part));
    }
}
void dumpSummary (T)(OmfDataset data, string part_name, ref OmfCollection!T part) {
    writefln("\n%s: %s", part_name, part.length);
    struct SourceInfo {
        string name;
        size_t count = 0;
        size_t confidence_count = 0;
        double confidence_sum = 0, confidence_min = double.max, confidence_max = -double.max;
        double[] samples;
        @property size_t missing_confidence () { return count - confidence_count; }
        @property double confidence_mean () { return (confidence_sum) / (cast(double)confidence_count); }

        size_t[string] overlapping_sources;
    }
    SourceInfo[string] sources;
    size_t missing_sources = 0;
    size_t samples = 0;
    string[] found_sources;

    foreach (item; part.items.byValue) {
        ++samples;
        bool has_source = false;
        auto s = "sources" in item.props;
        if (s) {
            found_sources.length = 0;
            foreach (source; s.array) {
                string name = source.object["dataset"].str;
                found_sources ~= name;

                auto src = name in sources;
                if (!src) { sources[name] = SourceInfo(name); src = name in sources; assert(src !is null); }
                src.count += 1;
                auto conf =  "confidence" in source.object;
                if (conf && conf.type != JSONType.null_) {
                    double c = conf.floating;
                    if (c.isNaN) continue;
                    src.confidence_count += 1;
                    src.confidence_sum += c;
                    src.confidence_min = min(src.confidence_min, c);
                    src.confidence_max = max(src.confidence_max, c);
                    src.samples ~= c;
                }
                has_source = true;
            }

            // update overlap metrics
            size_t N = found_sources.length;
            for (size_t i = 0; i < N; ++i) {
                for (size_t j = i+1; j < N; ++j) {
                    auto a = found_sources[i], b = found_sources[j];
                    auto a_s = a in sources, b_s = b in sources;

                    size_t* c = void;

                    c = b in a_s.overlapping_sources;
                    if (c) *c += 1; else a_s.overlapping_sources[b] = 1;

                    c = a in b_s.overlapping_sources;
                    if (c) *c += 1; else b_s.overlapping_sources[a] = 1;
                }
            }
        }
        if (!has_source) {
            missing_sources += 1;
        }
    }
    writeln("\n\tsources:");
    writefln("\t\tmissing sources: %s", missing_sources);
    foreach (src; sources.byValue) {
        writefln("\t\t%s: %s/%s (%0.2f%%)", src.name, src.count, samples, cast(double)src.count / samples * 100.0);
        if (src.confidence_count) {
            writefln("\t\t\tconfidence: (coverage %0.2f%% (%s/%s))\n\t\t\t\tmean %s, min %s, max %s"
                , (cast(double)src.confidence_count / src.count) * 100.0
                , src.confidence_count, src.count
                , src.confidence_mean, src.confidence_min, src.confidence_max
            );
            writefln("\t\t\t\tsamples: %s", src.samples[0..min($,20)]);
        } else {
            writefln("\t\t\tconfidence: N/A");
        }
        auto overlaps = src.overlapping_sources;
        if (overlaps.length) {
            writefln("\t\t\toverlaps:");
            auto totalOverlaps = overlaps.byValue.sum;
            writefln("\t\t\t\ttotal: %s/%s (%0.2f%%)", totalOverlaps, src.count,
                cast(double)totalOverlaps / src.count * 100.0);
            foreach (overlap; overlaps.byKeyValue) {
                writefln("\t\t\t\t%s: %s/%s (%0.2f%%)", overlap.key, overlap.value, src.count,
                    cast(double)overlap.value / src.count * 100.0);
            }
        }
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
