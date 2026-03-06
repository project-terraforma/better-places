module models.flexgrid_plugins.flexgrid_viewer;
import models.flexgrid;
import raylib;
import std;

class Viewer {
    private FlexGrid m_grid;
    private AABB m_view;
    private ubyte m_viewLevel;
    private FlexCellKey m_viewKeyMin, m_viewKeyMax;
    private bool m_hasView = false;

    // void setView (AABB view) { this.view = view; }
    void setView (AABB newView) {
        if (newView != m_view || !m_hasView) {
            m_hasView = true;
            writefln("Setting view to\n\n\t%s\n\n\t%s\n\n\t%s",
                newView.to!PolarNorm,
                newView.to!PolarDeg,
                newView.to!Meters
            );
            m_view = newView;
            m_viewLevel = FlexCellKey.getLevel(newView);
            writefln("View level = %s", m_viewLevel);
            m_viewKeyMin = FlexCellKey.from(newView.minv, m_viewLevel);
            m_viewKeyMax = FlexCellKey.from(newView.maxv, m_viewLevel);
            writefln("View MIN = %s", m_viewKeyMin);
            writefln("View MAX = %s", m_viewKeyMax);
            writeln();
        } else {
            // writefln("ignoring setView change");
        }
    }
    void setView (U)(TAABB!U newView)
        if (!is(U == AABB.Unit)) {
            // writefln("setting view to %s\n-> %s", newView, newView.to!AABB);
            setView(newView.to!AABB);
        }

    @property FlexGrid grid () { return m_grid; }
    @property AABB view () { return m_view; }
    @property void view (U)(TAABB!U newView) { setView(newView); }


    this (FlexGrid grid, AABB view) { m_grid = grid; m_view = view; }
    this (FlexGrid grid) { m_grid = grid; }

    void render (TR, TTR)(TR r, TTR tr) {
        // writefln("RENDERING VIEW, view bounds =\n\t%s\n\t%s\n\t%s",
        //     view.to!PolarNorm,
        //     view.to!PolarDeg,
        //     view.to!Meters
        // );
        // m_grid.visitCells(view, &renderCell);
        auto v = this.view;
        r.textf("view bounds %s", v);
        foreach (layer; grid.layers.byValue) {
            foreach (kv; layer.cells.byKeyValue) {
                auto cellBounds = kv.key.bounds;
                bool inBounds = v.contains(cellBounds);
                r.textf("checking cell %s bounds: %x => (%s,%s) => %s",
                    layer.name, kv.key.value, cellBounds.minv, cellBounds.maxv,
                    inBounds);

                r.draw(cellBounds.to!PolarDeg, Colors.BLUE, tr, 2);
                if (!inBounds) continue;

                renderCell(kv.value, r, tr);
            }
        }
    }
    private void renderCell (TR, TTR)(FlexCell cell, TR renderer, TTR transform) {
        auto viewBounds = view;
        foreach (kv; cell.geoBounds.byKeyValue) {
            auto bounds = kv.value;
            if (!viewBounds.contains(bounds)) continue;
            renderer.draw(bounds.to!PolarDeg, Colors.GREEN, transform, 1);
            // TODO: render FlexGeo geometry (cell.geo[kv.key]) once a FlexGeo renderer exists
        }
        foreach (kv; cell.points.byKeyValue) {
            auto pt = kv.value;
            if (!viewBounds.contains(pt)) continue;
            renderer.draw(pt.to!PolarDeg, Colors.RED, 3.0f, transform);
        }
    }
}
// interface ITextWriter { void write (const(char)[]); }
// struct ChunkedTextWriter {
//     enum SIZE = 16 * 1024 * 1024;
//     struct Blk { void* ptr; size_t length; }
//     Blk[] blks;
//     size_t head = 0;
//     size_t flushHead = 0;
//     this(this) = delete;
//     ~this(){
//         foreach (blk; blks) { free(blk); }
//         this.blks.length = 0;
//         this.head = 0;
//     }
//     void reset() { this.head = 0; this.flushHead = 0; }
//     private Blk getBlk (size_t sz) {
//         if (!head || blks[head].length + sz >= SIZE) {
//             auto ptr = malloc(SIZE);
//             memset(ptr, 0, SIZE);
//             blks ~= Blk(ptr, min(sz, SIZE));
//             ++head;
//             return Blk(ptr, min(sz, SIZE));
//         } else {
//             auto blk = blks[head];
//             auto start = blk.length;
//             auto end = min(start + sz, SIZE);
//             auto bytesToWrite = end - start;
//             blks[head].length = end;
//             return Blk(blk.ptr, bytesToWrite);
//         }
//     }
//     void flushWritesTo(void delegate(const(char)[]) sink) {
//         size_t fhead = flushHead;
//         size_t currentHead = head * SIZE + (head ? blks[head].length : 0);
//         if (currentHead == flushHead) return;
//         this.flushHead = currentHead;
//         size_t currentBlkHead = flushHead / SIZE;
//         size_t blkOffset = flushHead % SIZE;
//         if (currentBlkHead < head && blkOffset) {
//             auto blk = blks[currentBlkHead];
//             sink(blk.ptr[blkOffset .. blk.length]);
//             while (++currentBlkHead < head) {
//                 blk = blks[currentBlkHead];
//                 sink(blk.ptr[0 .. blk.length]);
//             }
//             blk = blks[currentBlkHead];
//             if (blk.length) {
//                 sink(blk.ptr[0 .. blk.length]);
//             }
//         } else {
//             auto blk = blks[currentBlkHead];
//             if (blkOffset < blk.length) {
//                 sink(blk.ptr[blkOffset .. blk.length]);
//             }
//         }
//     }
//     void put (C)(C c) if (isSomeChar!C) {
//         auto blk = getBlk(C.sizeof);
//         assert(blk.length == C.sizeof);
//         static if (C.sizeof == 1) {
//             *(cast(C*)blk.ptr) = c;
//         } else static if (C.sizeof == 2) {
//             *(cast(C*)blk.ptr) = c;
//         } else static if (C.sizeof == 4) {
//             *(cast(C*)blk.ptr) = c;
//         } else {
//             memcpy(blk.ptr, &c, blk.length);
//         }
//     }
//     void put(C)(const(C)[] r) if (isSomeChar!C) {
//         do {
//             auto blk = getBlk(r.length);
//             assert(blk.length && blk.length <= r.length);
//             memcpy(blk.ptr, r.ptr, blk.length);
//             r = r[blk.length..$];
//         } while(r.length);
//     }
// }
// struct BasicCachedTextWriter {
//     ITextWriter l;
//     ChunkedTextWriter w;
//     void flush () { w.flushWritesTo(&(l.write)); w.reset(); }
//     void textf (string msg) { w.put(msg); w.put('\n'); w.flushWritesTo(&(l.write)); }
//     void textf (TArgs...)(string fmt, TArgs args) {
//         formattedWrite(w, fmt, args); w.put('\n'); w.flushWritesTo(&(l.write));
//     }
// }
// class TextLogger {
//     public BasicCachedTextWriter w;
//     public alias w this;
//     this (ITextWriter w) { this.w = BasicCachedTextWriter(w); }
// }
// struct CameraController {
//     Viewer viewer;
//     TextLogger logger;
//     alias TextLogger this;

//     void update ()
//         in { assert(viewer && logger); }
//         do {
//             textf("view bounds: %s", viewBounds);
//             textf("view size:   %s", viewBounds.size);

//             float dt = GetFrameTime();
//             textf("dt: %s", dt);
//             textf("FPS: %s", 1/dt);

//             // handle mouse dragging
//             bool startDrag = false; // ignore 1st frame of mouse drag
//             if (!draggingView && IsMouseButtonDown(0)) {
//                 draggingView = true;
//                 startDrag = true;
//             } else if (draggingView && !IsMouseButtonDown(0)) {
//                 draggingView = false;
//             }
//             float scroll = GetMouseWheelMove();
//             textf("scroll: %s", 100 * scroll * dt);

//             auto wsz = Vector2(GetScreenWidth(), GetScreenHeight());
//             auto mp = GetMousePosition();
//             auto mr = Vector2( mp.x / wsz.x, 1 - mp.y / wsz.y );
//             textf("mouse (pixel): %s", mp);
//             textf("mouse (rel):   %s", mr);

//             double zoomRel = 0;
//             if (scroll) {
//                 // adjust view size: bigger or smaller
//                 enum SCROLL_SENSITIVITY = 5.0;
//                 enum USE_DT = true;
//                 auto clampedDt = min(dt, 1/30);
//                 double scrollInput = cast(double)scroll * dt * SCROLL_SENSITIVITY;
//                 // this.zoomLevel += scrollInput;
//                 zoomRel = scrollInput;

//                 writefln("raw input %s => input %s => scale %s => zoom %s",
//                     scroll, scrollInput, (1.0 - scrollInput) * 100, zoomLevel);

//             }
//             updateView(draggingView && !startDrag, zoomRel);
//         }
// }
