module models.geometry.units;

alias DefaultUnit = PolarDeg;

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
    alias T = double;
}
static struct Pixels { alias T = float; }
static struct Meters { alias T = double; }

static struct ScreenSpace { uint w, h; }
static struct RawCoordSpace {}
// static struct BasicPolarProjectionSpace {
//     Point!PolarRad projectAt, projectScale;

//     this (Point!PolarRad at)    { assign(at); }
//     this (Unit)(Point!Unit at)  { assign(at); }
//     void assign (Unit)(Point!Unit at) { assign(at.to!PolarRad); }
//     void assign (Point!PolarRad at) {
//         this.projectAt = at;
//         // this.projectScale = // TODO
//     }
//     static auto fromTo (TFrom, TTo, T)(T value) {
//         static if (is(TFrom == TTo)) return value;
//         static if (is(TTo == Meters)) {

//         }
//     }
// }
static struct WebMercatorSpace {}
