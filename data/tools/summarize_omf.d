#!/usr/bin/env rdmd
import models.omf;
import models.geometry;
import std;

void main (){
    enum DATASET_DIR = "data/omf";
    enum OUTPUT_DIR = "data/summary";
    foreach (dataset; DATASET_DIR.dirEntries(SpanMode.shallow)
        .filter!(d => d.isDir)
        .map!(d => d.name)
        .parallel
    ) {
        summarize(dataset, OUTPUT_DIR.buildPath(dataset.baseName~".txt"));
    }
}
void summarize (string path, string outputPath) {
    writefln("generating summary for '%s' -> %s", path, outputPath);

    auto basePath = outputPath.dirName;
    if (!basePath.exists) {
        writefln("creating %s", basePath);
        basePath.mkdirRecurse;
    }

    scope of = File(outputPath, "w");
    of.writefln("summary: OMF dataset %s", path);

    // read in + write out bounds file
    auto boundsFile = buildPath(path, ".bounds.txt");
    if (boundsFile.exists) {
        auto bounds = std.file.readText(boundsFile).strip.split("\n")[0];
        of.writefln("bounds: %s", bounds);
    }

    auto dataset = new OmfDataset().loadGeoJson(path);
    dataset.dumpSummary(of);
}
void dumpSummary (OmfDataset data, ref File of) {
    static foreach (part; data.PARTS) {
        dumpSummary(data, part, mixin("data."~part), of);
    }
}
void dumpSummary (T)(OmfDataset data, string part_name, ref OmfCollection!T part, ref File of) {
    of.writefln("\n%s: %s", part_name, part.length);
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
    of.writeln("\tsources:");
    of.writefln("\t\tmissing sources: %s", missing_sources);
    foreach (src; sources.byValue) {
        of.writefln("\t\t%s: %s/%s (%0.2f%%)", src.name, src.count, samples, cast(double)src.count / samples * 100.0);
        if (src.confidence_count) {
            of.writefln("\t\t\tconfidence: (coverage %0.2f%% (%s/%s))\n\t\t\t\tmean %s, min %s, max %s"
                , (cast(double)src.confidence_count / src.count) * 100.0
                , src.confidence_count, src.count
                , src.confidence_mean, src.confidence_min, src.confidence_max
            );
            of.writefln("\t\t\t\tsamples: %s", src.samples[0..min($,20)]);
        } else {
            of.writefln("\t\t\tconfidence: N/A");
        }
        auto overlaps = src.overlapping_sources;
        if (overlaps.length) {
            of.writefln("\t\t\toverlaps:");
            auto totalOverlaps = overlaps.byValue.sum;
            of.writefln("\t\t\t\ttotal: %s/%s (%0.2f%%)", totalOverlaps, src.count,
                cast(double)totalOverlaps / src.count * 100.0);
            foreach (overlap; overlaps.byKeyValue) {
                of.writefln("\t\t\t\t%s: %s/%s (%0.2f%%)", overlap.key, overlap.value, src.count,
                    cast(double)overlap.value / src.count * 100.0);
            }
        }
    }
}
