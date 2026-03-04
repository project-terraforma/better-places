module models.geometry.units;

alias DefaultUnit = PolarDeg;

static struct PolarDeg {
    alias This = PolarDeg;
    alias T = double;
    static auto to (Unit)(T value) {
        static if (is(Unit == This)) { return value; }
        else static if (is(Unit == PolarNorm)) {
            return cast(Unit.T)(
                (value * (1.0 / 180.0) + 0.5)
            );
        }
        else static if (is(Unit == PolarRad)) {
            return cast(Unit.T)(
                value * (PI / 180.0)
            );
        }
        else static assert(false, "unsupported conversion from "~This.stringof~" to "~Unit.stringof);
    }
    static auto to (Unit, TSpace)(T value, TSpace space) { return space.fromTo!(This,Unit)(value); }
}
static struct PolarRad {
    alias T = double;
}
static struct PolarNorm {
    alias This = PolarNorm;
    alias T = double;

    static auto to (Unit)(T value) {
        static if (is(Unit == This)) { return value; }
        else static if (is(Unit == PolarDeg)) {
            return cast(Unit.T)(
                (value - 0.5) * 180.0
            );
        }
        else static if (is(Unit == PolarRad)) {
            return cast(Unit.T)(
                (value - 0.5) * PI
            );
        }

        // approximate / wrong
        else static if (is(Unit == Meters)) {
            enum R = 6_378_137.0; // webmercator
            import std.math: PI;
            enum CIRC = R * 2 * PI; // extremely approximate for equator; otherwise wrong
            return cast(Unit.T)( value * CIRC );
        }


        else static assert(false, "unsupported conversion from "~This.stringof~" to "~Unit.stringof);
    }
}
static struct Pixels { alias T = float; }
static struct Meters {
    alias T = double;
}

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
