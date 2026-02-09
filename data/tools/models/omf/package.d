module models.omf;
import models.geojson;
import models.utils: annotateErr;
import std;
import core.sync.mutex;

class OmfDataset {
public:
    alias This = OmfDataset;
    OmfCollection!Building      buildings;
    OmfCollection!BuildingPart  building_parts;
    OmfCollection!Place         places;

    This loadGeoJson(string datasetDirectory) {
        enum BUILDING = "building", BUILDING_PART = "building_part", PLACE = "place";
        enum PARTS = [BUILDING, BUILDING_PART, PLACE];
        auto filePaths = PARTS
            .map!(part => tuple(part, datasetDirectory.buildPath("%s.geojson".format(part))))
            .array;

        Tuple!(string,string,models.geojson.FeatureCollection)[] files;
        auto mutex = new Mutex();
        foreach (parts; filePaths.parallel) {
            auto part = parts[0], path = parts[1];
            auto file = path.readText().annotateErr("error opening '%s'".format(path));
            auto json = file.parseJSON().annotateErr("error reading JSON in '%s'".format(path));
            auto fc = json.parseFeatures().annotateErr("error reading geojson in '%s'".format(path));
            synchronized(mutex){
                files ~= tuple(part, path, fc);
            }
        }

        void doLoad (string part, models.geojson.FeatureCollection fc) {
            final switch (part) {
                case BUILDING:      buildings.load(fc); break;
                case BUILDING_PART: building_parts.load(fc); break;
                case PLACE:         places.load(fc); break;
            }
        }
        void load (Tuple!(string, string, models.geojson.FeatureCollection) parts) {
            auto part = parts[0], path = parts[1];
            doLoad(part, parts[2])
                .annotateErr("error loading OMF data part %s in '%s'"
                    .format(part, path));
        }
        foreach (part; files.parallel) {
            load(part);
        }
        return this;
    }

}

struct OmfCollection (TFeature) {
    alias This = OmfCollection!TFeature;
    alias Feature = TFeature;
    TFeature[UUID] items;
    alias items this;

    void load (models.geojson.FeatureCollection fc) {
        foreach (feature; fc.features
            .map!((models.geojson.Feature f) => TFeature(f)
                .annotateErr("error loading '%s' from `%s`"
                    .format(TFeature.stringof, f))
            )
        ) {
            TFeature* existing = feature.id in items;
            enforce(!existing,
                "duplicate values for same id '%s':\n\t%s\n\t%s"
                .format(feature.id, *existing, feature)
            );
            items[feature.id] = feature;
        }
    }
}

struct OmfFeatureBase {
    UUID id;
    JSONValue[string] props;

    this (models.geojson.Feature f) {
        auto rawid = f.props["id"].str
            .annotateErr(
                "invalid or missing expected string 'id'\n\tin `%s`\n\t(has keys `%s`)!"
                .format(f.props, f.props.keys));

        this.id = rawid.parseUUID
            .annotateErr("invalid id '%s'!".format(f.props["id"].str));
        this.props = f.props;
    }
}

struct Building {
    alias This = Building;
    alias Geometry = MultiPolygon;
    // alias Geometry = Algebraic!(Polygon, MultiPolygon);

    OmfFeatureBase base; alias base this;
    Geometry geo;

    static This parse (JSONValue v) { return This(v.parseFeature); }

    this (models.geojson.Feature f) {
        this.base = OmfFeatureBase(f);
        f.geo.tryVisit!(
            (Polygon p)      { this.geo = MultiPolygon([ p ]); },
            (MultiPolygon p) { this.geo = p; },
            () { enforce(false, "invalid Building geometry! %s".format(f.geo)); }
        );
    }
}
struct BuildingPart {
    alias This = BuildingPart;
    // alias Geometry = Algebraic!(Polygon, MultiPolygon);
    alias Geometry = Polygon;

    OmfFeatureBase base; alias base this;
    Geometry geo;

    static This parse (JSONValue v) { return This(v.parseFeature); }

    this (models.geojson.Feature f) {
        this.base = OmfFeatureBase(f);
        f.geo.tryVisit!(
            (Polygon p)      { this.geo = p; },
            // (MultiPolygon p) { this.geo = Geometry(p); },
            () { enforce(false, "invalid BuildingPart geometry! %s".format(f.geo)); }
        );
    }
}
struct Place {
    alias This = Place;
    alias Geometry = Point;

    OmfFeatureBase base; alias base this;
    Point pos; alias pos geo;

    static This parse (JSONValue v) { return This(v.parseFeature); }

    this (models.geojson.Feature f) {
        this.base = OmfFeatureBase(f);
        f.geo.tryVisit!(
            (Point p) { this.pos = p; },
            () { enforce(false, "invalid BuildingPart geometry! %s".format(f.geo)); }
        );
    }
}
