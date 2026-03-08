module base;
public import raylib;
public import models.flexgrid;
public import models.flexgrid.flexgeo;
public import models.geometry;
public import models.flexgrid_plugins.omf_loader;

alias Geometry = TGeometry!PolarNorm;
alias Point = Geometry.Point;
alias Ring = Geometry.Ring;
alias AABB = Geometry.AABB;
alias Polygon = Geometry.Polygon;
alias MultiPolygon = Geometry.MultiPolygon;
