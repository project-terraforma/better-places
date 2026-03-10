module models.flexgrid.flexobject;
import std;
import msgpack;
import models.flexgrid.grid;
import models.flexgrid.key;

struct CellObjectStore {
    ObjectType[uint]        objectTypes;
    Place[uint]             places;
    Building[uint]          buildings;
    Street[uint]            streets;
    Address[uint]           addresses;
    AddressPin[uint]        addressPins;
    BuildingPart[uint]      buildingParts;
    OmfSegment[uint]        segments;
    OmfConnector[uint]      connectors;
    SourceInfo[][uint]      sources;
}
struct GlobalObjectCache {
    @serializedAs!NotSerialized
    GlobalObjectLookupInfo[UUID]    allObjects;
    SourceCache                     sourceCache;

    FlexObject findObject(UUID uuid) {
        assert(false, "unimplemented / TODO remove");
        assert(0);
        return null;
    }
}
struct GlobalObjectLookupInfo {
    ObjectType              type;
    ulong                   cellKey;
    uint                    localId;
}
struct SourceCache {
    string[] sources;
    @serializedAs!NotSerialized
    uint[string] sourcesByName;

    uint internSource (string source) {
        auto existing = source in sourcesByName;
        if (!existing) {
            sources ~= source;
            uint i = cast(uint)sources.length;
            sourcesByName[source] = i;
            return i;
        }
        return *existing;
    }
    string getSource (uint i) {
        assert(i < sources.length, "source index out of bounds: %s %s %s"
            .format(i, sources.length, sources));
        return sources[i];
    }
}
struct SourceInfo { uint index; float confidence; string id; }

void insertSourceInfo(FlexCell cell, uint id, JSONValue[string] props) {
    cell.objects.sources[id] = getSources(cell, props);
}

float asFlt (JSONValue value) {
    switch (value.type) {
        case JSONType.float_: return value.floating;
        case JSONType.integer: return value.integer;
        case JSONType.uinteger: return value.uinteger;
        default: return float.nan;
    }
}

SourceInfo[] getSources (FlexCell cell, JSONValue[string] props) {
    auto sources = "sources" in props;
    if (!sources || sources.type != JSONType.array) return null;
    auto srcs = sources.array;
    if (!srcs.length) return null;
    SourceInfo[] results;
    foreach (si; srcs) {
        auto src = si.object;
        if ("dataset" !in src) continue;
        JSONValue v = src["dataset"];
        if (v.type != JSONType.string) continue;
        auto name = v.str;
        if (!name.length) continue;
        float conf = "confidence" in src
            ? src["confidence"].asFlt
            : float.nan;

        auto internedDatasetId = cell.grid.globalObjectCache.sourceCache.internSource(name);
        results ~= SourceInfo(internedDatasetId, conf, null);
    }
    return results;
}

enum ObjectType {
    Place, Building, Street, Address, AddressPin
    , BuildingPart, OmfConnector, OmfSegment
}
struct ObjectRef {
    ulong cell;
    uint layer;
    uint  id;

    FlexCell getCell (FlexCell fromCell) {
        if (id == fromCell.cellKey.value) return fromCell;
        auto key = FlexCellKey.ValidatedFromRaw(id);
        auto layerGrid = layer in fromCell.grid.layers;
        if (layerGrid is null) return null;
        auto existing = key in layerGrid.cells;
        return existing ? *existing : null;
    }
}

struct Place {
    RawAddressInfo[] rawAddresses;
    string name;
    string[] categories;
}
struct Building {}
struct BuildingPart {}
struct Street {}
struct OmfConnector {}
struct OmfSegment {}
struct Address {}
struct AddressPin {
    RawAddressInfo rawAddress;
}
struct RawAddressInfo {
    string street;
    string number;
    string unit;
    string freeform;    // probably / almost certainly has street + number info
    string[] locale;    // typ something like [country, state / region, locality (ie city etc)]
}

bool tryReadString (alias doSomethingWith)(JSONValue[string] props, string key, bool stringExpected = true) {
    if (key !in props) return false;
    auto v = props[key];
    if (v.type == JSONType.string) {
        doSomethingWith(v.str);
        return false;
    } else if (v.type == JSONType.null_) {
        doSomethingWith(null);
        return true;
    }
    if (stringExpected) {
        enforce(false, "WTF what is this %s in %s (key = %s)"
            .format(v, props, key)
        );
    }
    return false;
}
bool tryReadStringInto(ref string[] intoList, JSONValue[string] props, string key, bool stringExpected = true) {
    return tryReadString!(s => intoList ~= s)(props, key, stringExpected);
}
bool tryReadStringInto(ref string intoVal, JSONValue[string] props, string key, bool stringExpected = true) {
    return tryReadString!(s => intoVal = s)(props, key, stringExpected);
}
bool tryReadStringInto(ref string intoVal, JSONValue v, bool stringExpected = true) {
    switch (v.type) {
        case JSONType.string: intoVal = v.str; return true;
        case JSONType.null_: intoVal = null; return true;
        default:
            if (stringExpected) {
                enforce(false, "WTF is this %s".format(v));
            }
            return false;
    }
}
bool tryReadStringInto(ref string[] intoList, JSONValue v, bool stringExpected = true) {
    switch (v.type) {
        case JSONType.string: intoList ~= v.str; return true;
        case JSONType.null_: return true;
        default:
            if (stringExpected) {
                enforce(false, "WTF is this %s".format(v));
            }
            return false;
    }
}

RawAddressInfo parseAddress(JSONValue[string] props) {
    RawAddressInfo result;
    if ("country" in props && props["country"].type == JSONType.string) {
        result.locale ~= props["country"].str;
    }
    bool hasAddressLevels = false;
    if ("address_levels" in props && props["address_levels"].type == JSONType.array) {
        hasAddressLevels = true;
        foreach (loc; props["address_levels"].array) {
            // wtf
            if (loc.type == JSONType.object) {
                auto o = loc.object;
                result.locale.tryReadStringInto(o, "value", true);
                // if ("value" in o && o["value"].type == JSONType.string) {
                //     auto v = o["value"];
                //     assert(v.type == JSONType.string, "wtf %s".format(v));
                //     string val = v.str;
                //     result.locale ~= val;
                // } else if ("value" in o && o["value"].type == JSONType.null_) {
                //     result.locale ~= null;
                // } else {
                //     assert(false, "WTF what is this %s in %s".format(
                //         o,
                //         props["address_levels"]));
                // }
                continue;
            }
            assert(loc.type == JSONType.string, "WTF what is this %s".format(props["address_levels"]));
            result.locale ~= loc.str;
        }
    }
    string region, locality;
    bool hasRegion   = region.tryReadStringInto(props, "region") && region !is null;
    bool hasLocality = locality.tryReadStringInto(props, "locality") && locality !is null;
    assert(!(hasAddressLevels && (hasRegion || hasLocality)),
        "weird ass probably incorrect JSON address object has both address_levels and region and/or locality: %s"
        .format(props));

    if (!hasAddressLevels) {
        result.locale ~= region;
        result.locale ~= locality;
    }

    if ("street" in props && props["street"].type == JSONType.string) {
        result.street = props["street"].str.toLower;
    }
    if ("number" in props && props["number"].type == JSONType.string) {
        result.number = props["number"].str.toLower;
    }
    if (result.freeform.tryReadStringInto(props, "freeform")) {
        result.freeform = result.freeform.toLower;
    }


    return result;
}
RawAddressInfo[] parseAddresses(JSONValue v) {
    assert(v.type == JSONType.array, "WTF is this %s".format(v));
    RawAddressInfo[] result;
    foreach (val; v.array) {
        if (val.type == JSONType.object) {
            result ~= parseAddress(val.object);
        } else {
            assert(false, "WTF is this %s".format(v));
        }
    }
    return result;
}

struct NotSerialized {
    static void serialize(T)(ref Packer p, ref T val)   {}
    static void deserialize(T)(ref Packer p, ref T val) {}
}
TObject asObjectType (TObject)(FlexObject obj)
    if (is(TObject : FlexObject))
{
    auto conv = cast(TObject)obj;
    enforce(conv, "failed to convert object %s to %s"
        .format(obj, TObject.stringof));
    return conv;
}

class FlexObject {
public:
    UUID                uuid;
    FlexCell            cell;
    this (UUID uuid, FlexCell cell = null) { this.uuid = uuid; this.cell = cell; }
}

import models.omf;
void insertNew(FlexCell cell, models.omf.Building item, uint id) {
    cell.objects.objectTypes[id] = ObjectType.Building;
    cell.objects.buildings[id] = createNew(item);
    insertSourceInfo(cell, id, item.props);
}
Building createNew (models.omf.Building item) {
    return Building();
}
void insertNew(FlexCell cell, models.omf.BuildingPart item, uint id) {
    cell.objects.objectTypes[id] = ObjectType.BuildingPart;
    cell.objects.buildingParts[id] = createNew(item);
}
BuildingPart createNew (models.omf.BuildingPart item) {
    return BuildingPart();
}

void insertNew(FlexCell cell, models.omf.Address item, uint id) {
    cell.objects.objectTypes[id] = ObjectType.AddressPin;
    cell.objects.addressPins[id] = createNew(item);
}
AddressPin createNew (models.omf.Address item) {
    return AddressPin(parseAddress(item.props));
}

void insertNew(FlexCell cell, models.omf.Place item, uint id) {
    cell.objects.objectTypes[id] = ObjectType.Place;
    cell.objects.places[id] = createNew(item);
}
Place createNew (models.omf.Place item) {
    Place result;
    auto props = item.props;
    if ("addresses" in item.props) result.rawAddresses = parseAddresses(item.props["addresses"]);

    if ("names" in props && props["names"].type == JSONType.object) {
        auto o = props["names"].object;
        result.name.tryReadStringInto(o, "primary");
    }
    if ("categories" in props) {
        auto cats = props["categories"];
        switch (cats.type) {
            case JSONType.array: {
                auto ca = cats.array;
                foreach(v; ca) {
                    result.categories.tryReadStringInto(v)
                        .enforce("wtf is %s in %s".format(v, ca));
                }
            } break;
            case JSONType.object: {
                auto co = cats.object;
                result.categories.tryReadStringInto(co, "primary");
                if ("alternate" in co) {
                    auto alts = co["alternate"];
                    switch (alts.type) {
                        case JSONType.array: {
                            foreach (val; alts.array) {
                                result.categories.tryReadStringInto(val);
                            }
                        } break;
                        case JSONType.null_: break;
                        default: assert(false, "WTF is this %s".format(alts));
                    }
                }
            } break;
            default: assert("WTF is this %s in %s".format(cats, props));
        }
        writefln("categories = %s", result.categories);
    }
    return result;
}

void insertNew(FlexCell cell, models.omf.Segment item, uint id) {
    auto geo = id in cell.geo;
    if (geo) {
        writefln("%s", *geo);
    } else {
        assert(false, "no segment geometry??");
    }


    cell.objects.objectTypes[id] = ObjectType.OmfSegment;
    cell.objects.segments[id] = createNew(item);
}
OmfSegment createNew (models.omf.Segment item) {
    OmfSegment result;

    return result;
}
void insertNew(FlexCell cell, models.omf.Connector item, uint id) {
    cell.objects.objectTypes[id] = ObjectType.OmfConnector;
    cell.objects.connectors[id] = createNew(item);
}
OmfConnector createNew (models.omf.Connector item) {
    OmfConnector result;

    return result;
}
