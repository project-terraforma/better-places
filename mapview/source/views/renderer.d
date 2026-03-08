module views.renderer;
import views.view_transform;
import base;
import std;

class Renderer {
    ViewTransform tr;
    Font font;
    bool loaded = false;
    int  textLayoutPosY = 0;
    int  fontSize = 24;
    bool drawGridRects = false;

    void load () {
        if (loaded) return; loaded = true;
        // load fonts
        writefln("loading font");
        this.font = LoadFontEx("fonts/JetBrainsMono/JetBrainsMono-Regular.ttf", 24, null, 250);
        import raygui;
        GuiSetFont(font);
        GuiSetStyle(DEFAULT, TEXT_SIZE, 24);
        // this.font = LoadFont("fonts/JetBrainsMono-Regular.ttf");
        writefln(" => %s", this.font);
    }
    void textf(TArgs...)(string msg, TArgs args) {
        text(msg.format(args));
    }
    void text (string msg) {
        textLayoutPosY += fontSize;
        text(msg, 20, 20 + textLayoutPosY);
    }
    void text (string msg, int x, int y) {
        text(msg, x, y, Colors.BLACK);
    }
    void text (string msg, int x, int y, Color color) {
        if (msg.length < 4 * 1024) {
            char[4 * 1024] buf;
            import core.stdc.string: memcpy;
            memcpy(buf.ptr, msg.ptr, msg.length);
            buf[msg.length] = '\0';
            drawText(buf.ptr, x, y, color);
        } else {
            drawText(msg.toStringz, x, y, color);
        }
    }
    private void drawText (const(char)* msg, int x, int y, Color color) {
        if (!loaded) load();
        DrawTextEx(font, msg, Vector2(x, y), fontSize, 0, color);
    }
    void newFrame () {
        if (!loaded) load();
        textLayoutPosY = 0;
    }
    void drawRect (AABB r, Color color, float lineThickness = 1) {
        auto a = tr.transform(r.minv), b = tr.transform(r.maxv);
        DrawLineEx(a, Vector2(b.x, a.y), lineThickness, color);
        DrawLineEx(a, Vector2(a.x, b.y), lineThickness, color);

        DrawLineEx(b, Vector2(a.x, b.y), lineThickness, color);
        DrawLineEx(b, Vector2(b.x, a.y), lineThickness, color);
    }
    // void draw (Point p, Color color, float radius) {

    //     // if (!tr.viewBounds.contains(p)) return; // hosted this up into callees
    //     Vector2 pt = tr.transform(p);
    //     DrawCircleV(pt, radius, color);
    //     // DrawPixel(cast(int)pt.x, cast(int)pt.y, color);
    //     // DrawPoly(
    //     //     tr.transform(p), 3, 10, 0, color
    //     // );
    // }
    void drawLine(Point a, Point b, Color color) {
        auto p1 = tr.transform(a), p2 = tr.transform(b);
        DrawLineV(p1, p2, color);
    }
    void drawRing (const Ring ring, Color color) {
        size_t n = ring.points.length;
        for (size_t i = 1; i < n; ++i) {
            drawLine(ring.points[i-1], ring.points[i], color);
        }
    }
    void draw (AABB r, Color color, float lineThickness = 1) {
        auto a = tr.transform(r.minv), b = tr.transform(r.maxv);
        DrawLineEx(a, Vector2(b.x, a.y), lineThickness, color);
        DrawLineEx(a, Vector2(a.x, b.y), lineThickness, color);

        DrawLineEx(b, Vector2(a.x, b.y), lineThickness, color);
        DrawLineEx(b, Vector2(b.x, a.y), lineThickness, color);
    }
    void drawPoint(Point point, Color color, float r) {
        float circRadius = r * tr.zoomBasedCirclePointRadius;
        if (circRadius <= 0) return;
        Vector2 pt = tr.transform(point); // screenspace
        DrawCircleV(pt, circRadius, color);
    }
}
