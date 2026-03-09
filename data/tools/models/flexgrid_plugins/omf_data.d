module models.flexgrid_plugins.omf_data;
import models.flexgrid;
import models.flexgrid.flexobject;
import std;
import msgpack;


enum ObjectType {
    Building, Place, Address, AddressPin, Street, StreetSection, DatasetOriginInfo
}
abstract class OmfBase : FlexObject {
public:
    ObjectType                      type;
    ulong                           hashedOrigin = 0;

    this (UUID uuid, ObjectType type, FlexCell cell = null) {
        super(uuid, cell);
        this.type = type;
    }
}
class Street : OmfBase {
public:
    string                          name;
    ReferenceSet!StreetSection[]    sections;
    ReferenceSet!Address[]          addresses;
    AABB                            bounds;

    enum Type = ObjectType.Street;
    this (UUID uuid) { super(uuid, Type); }
}
class StreetSection : OmfBase {
public:
    Reference!Street                street;
    AABB                            bounds;

    enum Type = ObjectType.StreetSection;
    this (UUID uuid) { super(uuid, Type); }
}
struct AddressPart {
    uint                            integerPart = 0;
    string                          extraPart = null;
}
class Address : OmfBase {
public:
    ReferenceSet!Building           nearBuildings;
    ReferenceSet!AddressPin         addressPins;
    ReferenceSet!Street             street;
    AddressPart                     addressNumber; // eg. "119", "1", etc. use lexicographical sorting
    AddressPart                     unitNumber;

    enum Type = ObjectType.Address;
    this (UUID uuid) { super(uuid, Type); }
}
class Building : OmfBase {
    ReferenceSet!Address            addresses;
    ReferenceSet!Place              places;
    ReferenceSet!Street             nearbyStreets;
    AABB                            bounds;

    enum Type = ObjectType.Building;
    this (UUID uuid) { super(uuid, Type); }
}

class AddressPin : OmfBase {
public:
    Reference!Address               address;
    Point                           point;

    enum Type = ObjectType.AddressPin;
    this (UUID uuid) { super(uuid, Type); }
}
class Place : OmfBase {
public:
    alias This = Place;
    ReferenceSet!Building           nearBuildings;
    Reference!Address               address;

    enum Type = ObjectType.Place;
    this (UUID uuid) { super(uuid, Type); }

    static void serialize (ref Packer p, ref This obj) {

    }
    static void deserialize(ref Packer p, ref This obj) {

    }
}

// shared static this() {
//     static foreach (t; [
//         "Place", "AddressPin", "Address", "Building",
//         "Street", "StreetSection",
//     ]) {
//         mixin("registerPackHandler!("~t~", "~t~".serialize)");
//         mixin("registerPackHandler!("~t~", "~t~".deserialize)");
//     }
// }
