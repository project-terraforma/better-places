/+module flexgrid;

struct FlexGridIndex {
    union {
        u64     id = 0;
        Fields  fields;
    }
    struct Fields {
        mixin bitfields!(
            u32, "x",       24,
            u32, "y",       24,
            Level, "level", 16
        );
    }
    enum Level : i16 {
        L0_64m   = 0,  // error/unused.
        L1_256m  = 1,  // ~256m = ~0.00025 arc degree (horiz),  ~256m = ~0.004 arc degree (vertical)
        L2_1km   = 2,  // ~1km  = ~0.001 arc degree (horiz),    ~1km  = ~0.016 arc degree (vertical)
        L3_4km   = 3,  // ~4km  = ~0.004 arc degree (horiz),    ~4km  = ~0.064 arc degree (vertical)
        L4_16km  = 4,
        L5_64km  = 5,
        L6_256km = 6,
    }
    static immutable Point GRID_SCALE[Level.max] = [
        Point( 2.1457672119140625e-05, 0.001373291015625 ), // 360 * 2^-24, 360 * 2^-18 | 9 | circ:
        Point( 8.58306884765625e-05, 0.0054931640625 ), // 360 * 2^-22, 360 * 2^-16 | 8 | circ: ~2.3886 km x ~152 km
        Point( 0.00034332275390625, 0.02197265625 ), // 360 * 2^-20, 360 * 2^-14 | 7 | circ: ~38.218 km x ~611 km
        Point( 0.001373291015625, 0.087890625 ), // 360 * 2^-18, 360 * 2^-12 | 6 | circ: ~152.87 km x 9783.93 km
        Point( 0.0054931640625, 0.3515625), // 360 * 2^-16, 360 * 2^-10 | 5 | circ: ~611 km x ~39.135k km
        Point( 0.02197265625, 1.40625), // 360 * 2^-14, 360 * 2^-8 | 4 | circ: ~2.445k km x ~156.543k km
        Point( 0.087890625, 5.625), // 360 * 2^-12, 360 * 2^-6 | 3 | circ: ~9.783k km x ~626.172k km
        Point( 0.3515625, 22.5), // 360 * 2^-10, 360 * 2^-4 | 2 | circ: ~39.135k km x ~250.4k km
        Point( 1.40625, 90.0), // 360 * 2^-8, 360 * 2^-2 | 1 | circ: ~156.5k km x ~10m km
        Point( 5.625, 360.0), // 360 * 2^-6, 360 * 2^0 | 0 | radius: (99.658k km x ~637k km) | circum: 626k km x ~40m km
    ];
    this (Point p, u16 level = 1)
        in { assert(level >= 1 && level <= Level.max); }
        do {
            u64 gridX = cast(u64)( p.x / GRID_SCALE[level] );
            u64 gridY = cast(u64)( p.y / GRID_SCALE[level] );
        }

    this (AABB bounds)
        in {}
        do {

        }
}

class FlexCell {
    FlexGridIndex   index;
    Point           pos     = Point(0,0);
    Point           scale   = Point(1,1);
    Point           flexMax = Point(0,0);
    SpatialIndex[]  gridData;
    SpatialIndex[]  flexData;
    DataStorage     storage;
}
class FlexGrid {
    FlexCell[u64]       cells;
    FlexLookup[u64]     flexLookup;
}
+/
