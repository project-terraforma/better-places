module pack_test;
import msgpack;
import std;
unittest {
    uint[string] kv;
    kv["a"] = 10;
    kv["b"] = 4;
    ubyte[] data = kv.pack();
    uint[string] kv2 = data.unpack!(uint[string]);
    // writefln("%s", data);
   assert(kv == kv2);
}
unittest {
    uint[UUID] kv;
    kv[randomUUID()] = 12;
    kv[randomUUID()] = 4;
    // writefln("%s\n%s", kv, kv.byValue.array());
    assert(kv.byValue.array().sort().array() == [4,12]);
    ubyte[] data = kv.pack();
    writefln("%s", data);
    uint[UUID] kv2 = data.unpack!(uint[UUID]);
    assert(kv == kv2);
}

struct FlexGeo {
    enum Type : ubyte {
        None = 0, Bounds = 1,
        Point = 2, Ring = 3, Polygon = 4, MultiPolygon = 5,
        Line = 6, LineString = 7,
    }
    enum CoordType : ubyte {
        PolarDeg = 0, PolarNorm = 1, PolarRad = 2, LocalMeters = 3
    }
    struct Index {
        union {
            uint   value;
            Fields fields;
        }
        alias fields this;
        struct Fields {
            mixin(bitfields!(
                Type,       "type",         4,
                CoordType,  "coordSpace",   2,
                size_t,     "count",        26,
            ));
        }
    }
    struct Data (TUnit) {
        alias Unit = TUnit;
        alias T = TUnit.T;
        enum  CoordType = UnitToCoordType!TUnit;
        T[]         data;
        Index[]     index;

        // Range iterators
        static struct Ranges {
            alias Points    = IterRange!(T, Type.Point, CoordType);
            alias Rings     = IterRange!(T, Type.Ring, CoordType);
            alias Polygons  = IterRange!(T, Type.Polygon, CoordType);
            alias Lines     = IterRange!(T, Type.Line, CoordType);
        }

        /// iterates over points (valid iff type is Line,LineString, Ring,Polygon,MultiPolygon)
        /// Ranges.Points is a forward, slicable, full random access iterator / D range that
        /// produces (and if necessary does non mutating coordinate transformation etc)
        /// Point!Unit values.
        @property Ranges.Points   points   () { return Ranges.Points(data); }

        /// iterates over rings (valid iff type is Ring,Polygon,MultiPolygon)
        /// Ranges.Rings is a forward iterator that returns Ranges.Points iterators
        @property Ranges.Rings    rings    () { return Ranges.Rings(index, data); }

        /// iterates over polygons (valid iff type is Polygon,MultiPolygon)
        /// Ranges.Polygons is a forward iterator that returns Ranges.Rings iterators
        @property Ranges.Polygons polygons () { return Ranges.Polygons(index, data); }

        /// iterates over lines (valid iff type is Line,LineString)
        /// Ranges.Line is a forward iterator that returns Ranges.Points iterators
        @property Ranges.Line     lines    () { return Ranges.Line(index, data); }

        @property Type type () const {
            return index.length ? Type.None : index[0].type;
        }
    }
    template CoordTypeToUnit (CoordType type) {
        static if (type == CoordType.PolarDeg) { alias CoordTypeToUnit = models.geometry.units.PolarDeg; } else
        static if (type == CoordType.PolarNorm) { alias CoordTypeToUnit = models.geometry.units.PolarNorm; } else
        static if (type == CoordType.PolarRad) { alias CoordTypeToUnit = models.geometry.units.PolarRad; } else
        static if (type == CoordType.LocalMeters) { alias CoordTypeToUnit = models.geometry.units.LocalMeters; } else
        static assert(false, "invalid type "~type.stringof);
    }
    template UnitToCoordType (Unit){
        static if (is(Unit == models.geometry.units.PolarDeg)) { enum UnitToCoordType = CoordType.PolarDeg; } else
        static if (is(Unit == models.geometry.units.PolarNorm)) { enum UnitToCoordType = CoordType.PolarNorm; } else
        static if (is(Unit == models.geometry.units.PolarRad)) { enum UnitToCoordType = CoordType.PolarRad; } else
        static if (is(Unit == models.geometry.units.LocalMeters)) { enum UnitToCoordType = CoordType.LocalMeters; } else
        static assert(false, "invalid type "~Unit.stringof);
    }
    static auto doIter(string type,Unit,T)(Index[] index, T[] data) {
        static if (type == "Point") {
            return IterRange!(T,Unit,Type.Point,UnitToCoordType!Unit)(index,data);
        } else static if (type == "Ring") {
            return IterRange!(T,Unit,Type.Ring,UnitToCoordType!Unit)(index,data);
        } else static if (type == "Polygon") {
            return IterRange!(T,Unit,Type.Polygon,UnitToCoordType!Unit)(index,data);
        } else static if (type == "MultiPolygon") {
            return IterRange!(T,Unit,Type.MultiPolygon,UnitToCoordType!Unit)(index,data);
        } else static assert(false, "unsupported type "~type);
    }
    struct IterRange(T,Unit, Type TGeoType, CoordType TCoordType) {
        alias This = IterRange!(T,Unit,TGeoType,TCoordType);

        static Unit.T getv (T* ptr, size_t offset) {
            alias InternalCoordSpaceUnit = CoordTypeToUnit!(TCoordType);
            static if (!is(Unit == InternalCoordSpaceUnit)) {
                return Unit.from!(InternalCoordSpaceUnit)(ptr[offset]);
            } else static if (!is(T == Unit.T)) {
                return Unit.from(ptr[offset]);
            }
        }

        static if (TGeoType == Type.Point) {
            T[]     data;
            @property bool empty () const { return data.length == 0; }
            invariant { assert((data.length % 2) == 0); }
        } else {
            Index[] index;
            T[]     data;
            T[]     bbox = null;
            AABB!Unit cachedBBox = void;
            bool hasCachedBBox = false;

            static if (!(TGeoType == Type.Ring || TGeoType == Type.LineString)) {
                size_t nextChildCount = 0;
            }
            @property bool empty () const { return index.length == 0; }

            invariant { assert((data.length % 2) == 0); }

            @property bool hasBounds () const { return bbox.length == 0; }
            @property AABB!Unit bounds () const
                in { assert(hasBounds); }
                do {
                    if (!hasCachedBBox) {
                        auto x1 = getv(bbox[0]), y1 = getv(bbox[1]),
                            x2 = getv(bbox[2]), y2 = getv(bbox[3]);
                        cachedBBox = AABB!Unit(Point!Unit(x1,y1), Point!Unit(x2,y2));
                    }
                    return cachedBBox;
                }
        }
        This save () const { return this; }

        static if (TGeoType == Type.Point) {
            this (T[] data)
                in { assert((data.length % 2) == 0); }
                do { this.data = data; }
            Point!Unit get (size_t i) const
                in { size_t n = data.length; assert!RangeError(i * 2 < n); }
                do {
                    static if (is(T == Unit.T) && is(Unit == )) {
                        return (cast(Point!(Unit)*)data.ptr)[0..2];
                    } else {
                        return Point!Unit(
                            cast(Unit.T)data.ptr[0],
                            cast(Unit.T)data.ptr[1]
                        );
                    }
                }
            void popFront ()
                in { auto n = data.length; assert(n > 0 && (n % 2) == 0); }
                do { data = data[2..$]; }
            size_t length () const
                { return data.length / 2; }

            Point!Unit front ()             const { return get(0); }
            Point!Unit opIndex (size_t i)   const { return get(i); }
            This opSlice (size_t fromIndex, size_t toIndex)
                in {
                    size_t n = data.length;
                    assert(fromIndex <= toIndex);
                    assert!RangeError(toIndex * 2 <= n);
                } do {
                    size_t offset = fromIndex * 2;
                    return This(index, data.ptr[fromIndex*2 .. toIndex*2]);
                }
        } else static if (TGeoType == Type.Ring) {
            this (Index[] index, T[] data) {
                bool foundCorrectPrefix = false;
                while(index.length) {
                    switch(index[0].type) {
                        case Type.Point: goto end;
                        case Type.Ring:
                            assert(!foundCorrectPrefix, "invalid multiple rings found in ring iterator! %s".format(index));
                            foundCorrectPrefix = true;
                            index = index[1..$];
                            continue;
                        case Type.Bounds:
                            assert(!bbox.ptr);
                            assert(data.length >= 4);
                            this.bbox = data[0..4];
                            data = data[4..$];
                            index = index[1..$];
                            continue;
                        default: assert(false, "invalid internal value found %s in %s".format(index[0].type, This.stringof);
                    }
                    end: break;
                }
                foreach (idx; index) {
                    assert(idx.type == Type.Point, "invalid index type found %s".format(idx.type, This.stringof));
                }
                this.index = index; this.data = data;
            }
            FwdRange!(T,Unit,Type.Point) front () const
                in { assert(!empty); }
                do {
                    auto idx = index[0];
                    auto count = idx.count;
                    assert(count * 2 <= data.length);
                    if (count * 2 > data.length) count = data.length/2;
                    return FwdRange!(T,Unit,Type.Point)(data[0..count*2]);
                }
            void popFront ()
                in { assert(!empty); }
                do {
                    auto idx = index[0];
                    auto count = idx.count;
                    assert(count * 2 <= data.length);
                    if (count * 2 > data.length) count = data.length/2;
                    index = index[1..$];
                    data = data[count..$];
                }
        } else static if (TGeoType == Type.Polygon) {
            this (Index[] index, T[] data) {
                bool foundCorrectPrefix = false;
                while(index.length) {
                    switch(index[0].type) {
                        case Type.Point: goto end;
                        case Type.Ring: goto end;
                        case Type.Polygon:
                            assert(!foundCorrectPrefix, "invalid multiple rings found in polygon iterator! %s".format(index));
                            foundCorrectPrefix = true;
                            index = index[1..$];
                            continue;
                        case Type.Bounds:
                            assert(!bbox.ptr);
                            assert(data.length >= 4);
                            this.bbox = data[0..4];
                            data = data[4..$];
                            index = index[1..$];
                            continue;
                        default: assert(false, "invalid internal value found %s in %s".format(index[0].type, This.stringof);
                    }
                    end: break;
                }
                this.index = index; this.data = data;
                getNextChild();
            }
            private void getNextChild () {
                if (!index.length) {
                    this.nextChildCount = 0;
                } else {
                    size_t count = 1, n = index.length;
                    while (count < n) {
                        switch (index[count]) {
                            case Type.Point: continue;
                            default: break;
                        }
                        break;
                    }
                    this.nextChildCount = count;
                };
            }
            FwdRange!(T,Unit,Type.Point) front () const
                in { assert(!empty); }
                do {
                    return FwdRange!(T,Unit,Type.Ring)(index[0..nextChildCount], data);
                }
            void popFront ()
                in { assert(!empty); }
                do {
                    size_t n = nextChildCount;
                    assert(n < index.length);
                    for (size_t i = 0; i < n; ++i) {
                        if (index[i].type == Type.Point) {
                            size_t count = index[i].count;
                            assert(count <= this.data.length);
                            this.data = this.data[count..$];
                        }
                    }
                    this.index = index[n..$];
                    getNextChild();
                }
        } else static assert(false, "unsupported type"~Type.stringof);
    }
}
