module models.flexgrid.flexgeo.serio;
import models.flexgrid.flexgeo.data;
import msgpack;
import core.stdc.string: memcpy, memset;
import std;
import core.exception: RangeError;

enum FlexGeoFmt {
    // raw entity values
    FLX1,

    // msgpack encoded entity values
    FLX2,

    FLX_RawEncoded = FLX1,
    FLX_MsgPackEncoded = FLX2,
}
struct FlexGeoPacked2 {
    uint[]   idx;
    double[] geo;
}
ubyte[] serialize (FlexGeo g, FlexGeoFmt fmt = FlexGeoFmt.FLX1) {
    validate(g);
    final switch (fmt) {
        // raw fmt
        case FlexGeoFmt.FLX1: {
            ubyte[] result;
            uint hdrBytes    = 16;
            uint entityCount = cast(uint)(g.entities.length);
            uint entityBytes = cast(uint)( 4 * entityCount );
            uint entityZeroPad = (16 - ((hdrBytes + entityBytes) % 16)) % 16;
            uint dataBytes   = cast(uint)( g.points.length * g.points[0].sizeof );
            auto dataOffset  = hdrBytes + entityBytes + entityZeroPad;

            result.length = dataOffset + dataBytes;
            uint* up = cast(uint*)result.ptr;
            memcpy(result.ptr, "FLX1".ptr, 4);
            up[1] = dataOffset;
            up[2] = dataOffset + dataBytes;
            up[3] = entityCount;

            memcpy(result.ptr + hdrBytes, cast(void*)g.entities.ptr, entityBytes);
            if (entityZeroPad) memset(result.ptr + hdrBytes + entityBytes, 0, entityZeroPad);
            memcpy(result.ptr + dataOffset, cast(void*)g.points.ptr, dataBytes);
            return result;
        }
        // msgpack encoded
        case FlexGeoFmt.FLX2: {
            auto packed = FlexGeoPacked2(
                (cast(uint*)g.entities.ptr)[0 .. g.entities.length],
                (cast(double*)g.points.ptr)[0 .. g.points.length * 2]
            );
            static assert(g.points[0].sizeof == double.sizeof * 2);
            ubyte[] result;
            result ~= (cast(const(ubyte)[])"FLX2");
            result ~= packed.pack();
            return result;
        }
    }
}
void load (out FlexGeo g, ubyte[] data) {
    assert(data.length > 4);
    switch (cast(string)data[0..4]) {
        case "FLX1": {
            assert(data.length > 20);
            uint* up = cast(uint*)data.ptr;
            uint dataOffset = up[1];
            uint dataEnd = up[2];
            uint entityCount = up[3];
            enum hdrBytes = 16;
            enforce!RangeError(
                dataOffset <= dataEnd &&
                dataEnd    <= data.length &&
                hdrBytes + entityCount * 4 <= dataOffset,
                "invalid data headers: data.length = %s, data (offset = %s, end = %s), entity count = %s * 4 = %s"
                .format(data.length, dataOffset, dataEnd, entityCount, entityCount * 4)
            );
            g.entities = (cast(Entity*)(data.ptr + hdrBytes))[0 .. entityCount];
            g.points = (cast(Point*)(data.ptr + dataOffset))[0 .. dataEnd - dataOffset];
            g.finishLoad();
            g.validate();
        } break;
        case "FLX2": {
            auto packed = data.unpack!FlexGeoPacked2;
            static assert(g.points[0].sizeof == double.sizeof * 2);
            static assert(Entity.sizeof == uint.sizeof);
            g.entities = (cast(Entity*)packed.idx)[0..packed.idx.length];
            g.points   = (cast(Point*)packed.geo)[0..packed.geo.length / 2];
            g.finishLoad();
            g.validate();
        } break;
        default:
            enforce(false, "invalid type! (prefix %s)".format(cast(string)data[0..4]));
            assert(0);
    }
}
void finishLoad(ref FlexGeo g) {
    // simple: assume we must have a Bounds at root (and that is valid etc)
    enforce(g.entities.length >= 1);
    enforce(g.entities[0].type == GeoType.Bounds);
    enforce(g.points.length >= 2); // and thus we must have bounds
    g.bounds = AABB(g.points[0], g.points[1]);
}

void validate (ref FlexGeo g) {
    // TODO: sanity check all indices + geometry

    // simple: assume we must have a Bounds at root (and that is valid etc)
    enforce(g.entities.length >= 1);
    enforce(g.entities[0].type == GeoType.Bounds);
    enforce(g.points.length >= 2); // and thus we must have bounds
    // enforce(g.bounds == AABB(g.points[0], g.points[1]),
    //     "%s != %s".format(g.bounds, AABB(g.points[0], g.points[1])));
}
