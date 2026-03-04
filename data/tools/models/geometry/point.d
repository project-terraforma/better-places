module models.geometry.point;
public import models.geometry.units;
import std;

struct TPoint (Unit=PolarDeg) {
    alias This = TPoint!Unit;
    alias T = Unit.T;
    T x = 0, y = 0;

    this (T x, T y) {
        static if (__traits(compiles, Unit.clamp(x))) {
            this.x = Unit.clamp(x);
            this.y = Unit.clamp(y);
        } else {
            this.x = x;
            this.y = y;
        }
    }

    TPoint!U to (U)() const {
        static if (is(U == Unit)) { return this; }
        else static if (__traits(compiles, U.from!Unit(x))) {
            return TPoint!U( U.from!Unit(x), U.from!Unit(y) );
        } else static if (__traits(compiles, Unit.to!U(x))) {
            return TPoint!U( Unit.to!U(x), Unit.to!U(y) );
        } else static assert(false, "unknown conversion from "~Unit.stringof~" to "~U.stringof);
    }

    void toString (scope void delegate(scope const(char)[]) sink) {
        char[256] buf = void;
        sink(buf.sformat("Point(%s)(%s, %s)", Unit.stringof, x, y));
    }
    bool opEquals (const TPoint rhs) const { return x == rhs.x && y == rhs.y; }
    long opCmp (const TPoint rhs) const {
        if (x != rhs.x) return x < rhs.x ? -1 : +1;
        if (y != rhs.y) return y < rhs.y ? -1 : +1;
        return 0;
    }
    This opBinary (string op,U2)(const TPoint!(U2) rhs) const {
        static if (op == "+" || op == "-" || op == "*" || op == "/") {
            static if (is(U2 == Unit)) {
                This r = rhs.to!Unit;
                auto x = mixin("x"~op~"r.x");
                auto y = mixin("y"~op~"r.y");
                return This(x,y);
            } else {
                auto x = mixin("x"~op~"rhs.x");
                auto y = mixin("y"~op~"rhs.y");
                return This(x,y);
            }
        } else static assert(false, "invalid operator "~s);
    }
    This opBinary (string op)(T s) const {
        static if (op == "+" || op == "-" || op == "*" || op == "/") {
            auto x = mixin("x"~op~"s");
            auto y = mixin("y"~op~"s");
            return This(x,y);
        } else static assert(false, "invalid operator "~s);
    }
    This opBinaryRight (string op)(T s) const{
        return opBinary!op(s);
    }
}
