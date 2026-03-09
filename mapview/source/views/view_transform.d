module views.view_transform;
import base;
import std;
import controllers.map_view_controller; // hacks

// full of hacks, refactor eventually
// exists as is from tech debt from rapid prototyping
class ViewTransform {
    AABB viewBounds;
    Point mapToScreenScale;
    Point mapToScreenOffset;
    Point cursorPos; // mouse cursor position, transformed into geo Point space
    float zoomLevel;
    float precalcZoomCircleRadius;
    Vector2 cursorPosScreenSpace;
    float precalcZoomCircleRad2;
    Vector2 screenSize;

    float cursorRadiusPixels = 15;

    import models.geometry.units;
    @property Scalar!Meters cursorRadius () const {
        return Scalar!PolarNorm(
            cursorRadiusPixels / mapToScreenScale.x
        ).to!Meters;
    }
    this (const MapViewController view) {
        update(view);
    }
    void update (const MapViewController view) {
        this.viewBounds = view.viewBounds;
        auto screenSize = Point(GetScreenWidth(), GetScreenHeight());
        this.screenSize = Vector2(screenSize.x, screenSize.y);
        auto viewSize = Point(
            viewBounds.maxv.x - viewBounds.minv.x,
            viewBounds.maxv.y - viewBounds.minv.y
        );
        this.mapToScreenScale = Point(
            screenSize.x / viewSize.x,
            screenSize.y / viewSize.y,
        );
        this.mapToScreenOffset = viewBounds.minv;

        auto m = GetMousePosition();
        this.cursorPos = transformScreenToGeoSpace(m);
        // this.viewBounds = viewBounds.scaledAroundCenter(0.5); // for debugging view culling
        this.zoomLevel = cast(float)view.zoomLevel;
        this.precalcZoomCircleRadius = calcZoomCircleRadius(zoomLevel);
        this.cursorPosScreenSpace = m;
        this.precalcZoomCircleRad2 = precalcZoomCircleRadius * precalcZoomCircleRadius;
    }
    Point transformScreenToGeoSpace (Vector2 p) {
        p.y = screenSize.y - p.y;
        return Point(
            (p.x / mapToScreenScale.x) + mapToScreenOffset.x,
            (p.y / mapToScreenScale.y) + mapToScreenOffset.y
        );
    }

    Vector2 transform (Point p) {
        p.x -= mapToScreenOffset.x;
        p.y -= mapToScreenOffset.y;
        p.x *= mapToScreenScale.x;
        p.y *= mapToScreenScale.y;
        p.y = screenSize.y - p.y;
        return Vector2(p.x, p.y);
    }

    float zoomBasedCirclePointRadius () { return precalcZoomCircleRadius; }
    private float calcZoomCircleRadius(float zoomLevel) {
        // zoom goes from 2 (zoomed in) to -4 (zoomed out)
        auto z = (zoomLevel + 2) * 0.25;
        return z * z * 4;
    }
    bool mouseNearPoint(Vector2 screenSpacePoint) {
        float dx = screenSpacePoint.x - cursorPosScreenSpace.x;
        float dy = screenSpacePoint.y - cursorPosScreenSpace.y;
        dx *= dx; dy *= dy;
        enum MOUSE_NEAR_PX_RADIUS = 35;
        return dx + dy <= precalcZoomCircleRad2 + MOUSE_NEAR_PX_RADIUS*MOUSE_NEAR_PX_RADIUS;
    }
}
