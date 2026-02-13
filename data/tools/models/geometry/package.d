module models.geometry;
import models.utils;
public import std.variant;

struct Point { float x = 0, y = 0; }
struct Ring  { Point[] points; }
struct Polygon { Ring[] rings; }
struct MultiPolygon { Polygon[] polygons; }
