struct Point (Unit) {
    alias T = Unit.T;
    T x, y;
    
    Point!U (U) to () {
        static if (__traits(compiles, U.from!Unit(x))) {
            return Point!U( U.from!Unit(x), U.from!Unit(y) );
        } else static if (__traits(compiles, Unit.to!U(x))) {
            return Point!U( Unit.to!U(x), Unit.to!U(y) );
        } else static assert("unknown conversion from "~Unit.stringof~" to "~U.stringof);
    }
}
struct AABB (Unit) {
    alias T = Unit.T;
    Point!T minv, maxv;
}
static struct PolarDeg {
    alias This = PolarDeg;
    alias T = double;
    static auto to (Unit)(T value) {
        static if (is(Unit == PolarDeg)) { return value; }
        else static if (is(Unit == PolarNorm)) { return cast(Unit.T)( value * (1.0 / 180.0) ); }
        else static if (is(Unit == PolarRad))  { return cast(Unit.T)( value * (PI / 180.0) ); }
        else static assert("unsupported type");
    }
    static auto to (Unit, TSpace)(T value, TSpace space) { return space.fromTo!(This,Unit)(value); }
}
static struct PolarRad {
    alias T = double;
}
static struct PolarNorm {
    alias T = float;
}
static struct Pixels { alias T = float; }
static struct Meters { alias T = double; }

static struct ScreenSpace { uint w, h; }
static struct RawCoordSpace {}
static struct BasicPolarProjectionSpace {
    Point!PolarRad projectAt, projectScale;
    
    this (Point!PolarRad at)    { assign(at); }
    this (Unit)(Point!Unit at)  { assign(at); }
    void assign (Unit)(Point!Unit at) { assign(at.to!PolarRad); }
    void assign (Point!PolarRad at) {
        this.projectAt = at;
        // this.projectScale = // TODO
    }
    static auto fromTo (TFrom, TTo, T)(T value) {
        static if (is(TFrom == TTo)) return value;
        static if (is(TTo == Meters)) {
            
        }
    }
    
}
static struct WebMercatorSpace {}