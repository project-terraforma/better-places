#!/usr/bin/env rdmd
import models.omf;
import models.geometry;
import std;

void main (){
    enum DATASET_DIR = "data/omf";
    enum OUTPUT_DIR = "data/address_summary";
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
    auto data = new OmfDataset().loadGeoJson(path);
    File of = File(outputPath, "w");
    summarizeBuildingAddressOverlaps(data, of);
    // static foreach (part; data.PARTS) {
    //     dumpSummary(data, part, mixin("data."~part), of);
    // }
}
void summarizeBuildingAddressOverlaps (OmfDataset data, ref File of) {

    File of_address_conflicts = File("address_conflicts.txt", "w");
    writefln("BUILDINGS");
    of.writefln("BUILDINGS");
    summarizeBuildings(data, data.building, of, of_address_conflicts);
    writeln();
    writeln();
    writefln("BUILDING PARTS");
    of.writefln("BUILDING PARTS");
    summarizeBuildings(data, data.building_part, of, of_address_conflicts);
}
string fmtFrac (size_t n, size_t d) {
    return "%s/%s (%0.2f%%)".format(n, d, cast(double)n/d*100);
}

void summarizeBuildings(TBuilding)(OmfDataset data, ref TBuilding buildings
, ref File of, ref File of_address_conflicts) {
    writefln("addresses: %s", data.address.items.length);
    writefln("buildings: %s", buildings.length);
    writefln("building parts: %s", buildings.length);

    size_t n_building = 0, n_building_with_addr = 0, n_with_multi = 0;
    size_t[UUID] buildings_with_multiple_addresses;
    size_t total_addr_hit = 0, total_bounds_hit = 0;
    UUID[UUID] buildingsByAddr;
    size_t addressMultiHitBuildingConflicts = 0;
    size_t n_address = 0, n_address_building_hits = 0;

    struct SrcInfo {
        size_t n = 0, withAddresses = 0, withMultipleAddresses = 0;
        size_t maxAddressCount = 0;
        size_t[size_t] multiAddressDist;
    }
    SrcInfo[string] bySource;

    void updateSource (string src, size_t numAddresses) {
        auto ptr = src in bySource;
        if (!ptr) { bySource[src] = SrcInfo(); ptr = src in bySource; assert(ptr); }
        ptr.n += 1;
        if (numAddresses) ptr.withAddresses += 1;
        if (numAddresses > 1) {
            ptr.withMultipleAddresses += 1;
            ptr.maxAddressCount = max(ptr.maxAddressCount, numAddresses);

            auto dist = numAddresses in ptr.multiAddressDist;
            if (dist) *dist += 1;
            else ptr.multiAddressDist[numAddresses] = 1;
        }
    }
    void updateSources (JSONValue[string] props, size_t numAddresses) {
        auto sources = "sources" in props;
        if (sources && sources.array.length) {
            foreach (source; sources.array) {
                updateSource(source.object["dataset"].str, numAddresses);
            }
        } else {
            updateSource("N/A", numAddresses);
        }
    }
    void printSourceSummary(ref File f) {
        f.writeln();
        f.writefln("statistics by source:");
        foreach (kv; bySource.byKeyValue) {
            auto src = kv.value;
            f.writefln("\t%s: count %s", kv.key, fmtFrac(src.n, n_building));
            f.writefln("\t\twith addresses: %s", fmtFrac(src.withAddresses, src.n));
            f.writefln("\t\twith multiple addresses: %s", fmtFrac(src.withMultipleAddresses, src.n));
            f.writefln("\t\tmax address count: %s", src.maxAddressCount);
            f.writefln("\t\tmulti address distribution:");
            foreach (dist; src.multiAddressDist.byKeyValue.array.sort!("a.key < b.key")) {
                f.writefln("\t\t\t%s: %s", dist.key, dist.value);
            }
            f.writeln();
        }
    }
    void writeSummary (ref File f) {
        f.writefln("address building hits: %s", fmtFrac(n_address_building_hits, n_address));
        f.writefln("buildings with addresses: %s", fmtFrac(n_building_with_addr,n_building));
        f.writefln("with multiple addresses: %s", n_with_multi);

        f.writefln("avg bounds hits: %s", fmtFrac(total_bounds_hit,n_building));
        f.writefln("avg address hits: %s", fmtFrac(total_addr_hit,n_building));

        printSourceSummary(f);
    }

    size_t k = 0;

    models.omf.Address[] extraAddressHits;
    foreach (ref building; buildings.byValue) {
        ++n_building;
        auto bounds = AABB(building.geo);
        // writefln("%s %s (%s, %s)", bounds, bounds.minv == bounds.maxv,
        //     bounds.maxv.x - bounds.minv.x,
        //     bounds.maxv.y - bounds.minv.y);
        // foreach (poly; building.geo.polygons) {
        //     foreach (ring; poly.rings) {
        //         foreach (point; ring.points) {
        //             assert(bounds.contains(point));
        //         }
        //     }
        // }
        size_t addr_count = 0;
        extraAddressHits.length = 0;
        foreach (ref addr; data.address.items) {
            if (bounds.contains(addr.pos)) {
                // writefln("AABB hit");
                ++total_bounds_hit;
                if (building.geo.contains(addr.pos)) {
                    // writefln("found address!");
                    // writefln("building = %s", building.props);
                    // writefln("address = %s", addr.props);
                    ++addr_count;
                    ++total_addr_hit;
                    extraAddressHits ~= addr;

                    if (addr.id in buildingsByAddr) {
                        ++addressMultiHitBuildingConflicts;
                        writefln("CONFLICT: address %s matches building %s, already matched %s", addr.id, building.id, buildingsByAddr[addr.id]);
                        of_address_conflicts.writefln("CONFLICT: address %s matches building %s, already matched %s", addr.id, building.id, buildingsByAddr[addr.id]);
                    }
                    buildingsByAddr[addr.id] = building.id;
                }
            }
        }
        if (addr_count) ++n_building_with_addr;
        if (addr_count > 1) ++n_with_multi;
        updateSources(building.props, addr_count);

        if (addr_count > 1) {
            of_address_conflicts.writeln();
            of_address_conflicts.writefln("building %s has %s address hits!\n\t%s", building.id, addr_count, building.props);
            of_address_conflicts.writefln("building geometry: (%.9f, %.9f),(%.9f,%.9f)", bounds.minv.x,bounds.minv.y, bounds.maxv.x, bounds.maxv.y);
            of_address_conflicts.writefln("\t%s", building.geo);
            foreach (addr; extraAddressHits[0..min($,20)]) {
                of_address_conflicts.writefln("ADDR (%.9f, %.9f) %s\n\t%s", addr.pos.x, addr.pos.y, addr.id, addr.props);
            }
            if (addr_count > 20) { of_address_conflicts.writefln("[... %s]", addr_count-20);}
        }

        if (++k > 2000) {
            k = 0;
            writeSummary(stdout);
            writeln();
        }
    }

    // find addresses without buildings
    // auto of_missing = File("missing_addresses.txt", "w");
    foreach (ref addr; data.address.items) {
        ++n_address;
        if (addr.id in buildingsByAddr) {
            ++n_address_building_hits;
        } else {
            // of_missing.writefln("%s %s", addr.id, addr.props);
        }
    }
    writeSummary(stdout);
    writeSummary(of);
}
