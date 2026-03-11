module models.flexgrid.common;
public import models.geometry;

alias u32 = uint;
alias u64 = ulong;

alias Geometry = TGeometry!PolarNorm;
alias Point = Geometry.Point;
alias AABB = Geometry.AABB;
alias Ring = Geometry.Ring;
alias Polygon = Geometry.Polygon;
alias MultiPolygon = Geometry.MultiPolygon;
