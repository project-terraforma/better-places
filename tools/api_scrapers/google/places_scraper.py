"""
Google Maps Places Scraper
==========================
Fetches all places within a given coordinate + radius using the Google Maps
Places API (Nearby Search). Supports pagination via next_page_token to exhaust
all results (up to the API's 60-result cap per query).

Features:
  - SQLite cache layer: identical queries return cached rows instantly.
  - Request queue: populate a `search_requests` table and batch-run them.
  - Optional Flask REST API with its own response cache.

Usage (standalone):
    export GOOGLE_MAPS_API_KEY="your-key"
    python places_scraper.py --lat 40.7128 --lng -74.0060 --radius 1000

Usage (batch from DB):
    python places_scraper.py --run-queue

Usage (Flask server):
    python places_scraper.py --serve --port 5000
"""

from __future__ import annotations

import argparse
import hashlib
import logging
import os
import sqlite3
import time
from dataclasses import dataclass, asdict
from typing import Optional

import requests

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

API_KEY = os.environ.get("GOOGLE_MAPS_API_KEY", "")
NEARBY_SEARCH_URL = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
DB_PATH = os.environ.get("PLACES_DB_PATH", "places_cache.db")
PAGE_DELAY = 2.0  # Google requires a short delay before using next_page_token

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class Place:
    place_id: str
    name: str
    lat: float
    lng: float
    types: str = ""  # comma-separated


class ApiLimitExceeded(Exception):
    """Raised when the configured API call limit has been reached."""

    def __init__(self, used: int, limit: int, period: str):
        self.used = used
        self.limit = limit
        self.period = period
        super().__init__(
            f"API call limit reached: {used}/{limit} calls used "
            f"in the current {period} window."
        )


# ---------------------------------------------------------------------------
# Database layer
# ---------------------------------------------------------------------------

class PlacesDB:
    """Thin wrapper around SQLite for caching and request queuing."""

    def __init__(self, db_path: str = DB_PATH):
        self.conn = sqlite3.connect(db_path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self._init_schema()

    def _init_schema(self):
        cur = self.conn.cursor()
        cur.executescript("""
            CREATE TABLE IF NOT EXISTS places (
                place_id   TEXT PRIMARY KEY,
                name       TEXT NOT NULL,
                lat        REAL NOT NULL,
                lng        REAL NOT NULL,
                types      TEXT DEFAULT ''
            );

            CREATE TABLE IF NOT EXISTS search_cache (
                cache_key   TEXT PRIMARY KEY,
                lat         REAL NOT NULL,
                lng         REAL NOT NULL,
                radius_m    INTEGER NOT NULL,
                place_type  TEXT DEFAULT '',
                fetched_at  TEXT DEFAULT (datetime('now')),
                result_count INTEGER DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS search_cache_places (
                cache_key  TEXT NOT NULL,
                place_id   TEXT NOT NULL,
                PRIMARY KEY (cache_key, place_id),
                FOREIGN KEY (cache_key) REFERENCES search_cache(cache_key),
                FOREIGN KEY (place_id)  REFERENCES places(place_id)
            );

            CREATE TABLE IF NOT EXISTS search_requests (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                lat         REAL NOT NULL,
                lng         REAL NOT NULL,
                radius_m    INTEGER NOT NULL,
                place_type  TEXT DEFAULT '',
                status      TEXT DEFAULT 'pending',   -- pending | running | done | error
                created_at  TEXT DEFAULT (datetime('now')),
                finished_at TEXT
            );

            -- Tracks every actual Google API HTTP request (each page = 1 row)
            CREATE TABLE IF NOT EXISTS api_usage (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                called_at   TEXT DEFAULT (datetime('now')),
                endpoint    TEXT DEFAULT 'nearbysearch',
                lat         REAL,
                lng         REAL,
                radius_m    INTEGER,
                place_type  TEXT DEFAULT '',
                page        INTEGER DEFAULT 1
            );

            -- Key-value settings; seeded with defaults on first run
            CREATE TABLE IF NOT EXISTS settings (
                key   TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            -- Default: 1000 calls per month.  Change via SQL or the API.
            INSERT OR IGNORE INTO settings (key, value) VALUES ('api_call_limit', '1000');
            INSERT OR IGNORE INTO settings (key, value) VALUES ('api_limit_period', 'month');
        """)
        self.conn.commit()

    # -- cache helpers -------------------------------------------------------

    @staticmethod
    def _cache_key(lat: float, lng: float, radius_m: int, place_type: str = "") -> str:
        raw = f"{lat:.6f}|{lng:.6f}|{radius_m}|{place_type}"
        return hashlib.sha256(raw.encode()).hexdigest()[:16]

    def get_cached(self, lat: float, lng: float, radius_m: int, place_type: str = "") -> Optional[list[Place]]:
        key = self._cache_key(lat, lng, radius_m, place_type)
        row = self.conn.execute("SELECT 1 FROM search_cache WHERE cache_key = ?", (key,)).fetchone()
        if row is None:
            return None
        rows = self.conn.execute("""
            SELECT p.place_id, p.name, p.lat, p.lng, p.types
            FROM search_cache_places scp
            JOIN places p ON p.place_id = scp.place_id
            WHERE scp.cache_key = ?
        """, (key,)).fetchall()
        return [Place(**dict(r)) for r in rows]

    def store_results(self, lat: float, lng: float, radius_m: int, places: list[Place], place_type: str = ""):
        key = self._cache_key(lat, lng, radius_m, place_type)
        cur = self.conn.cursor()
        for p in places:
            cur.execute("""
                INSERT OR REPLACE INTO places (place_id, name, lat, lng, types)
                VALUES (?, ?, ?, ?, ?)
            """, (p.place_id, p.name, p.lat, p.lng, p.types))
        cur.execute("""
            INSERT OR REPLACE INTO search_cache (cache_key, lat, lng, radius_m, place_type, result_count)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (key, lat, lng, radius_m, place_type, len(places)))
        for p in places:
            cur.execute("""
                INSERT OR IGNORE INTO search_cache_places (cache_key, place_id) VALUES (?, ?)
            """, (key, p.place_id))
        self.conn.commit()

    # -- request queue -------------------------------------------------------

    def add_request(self, lat: float, lng: float, radius_m: int, place_type: str = "") -> int:
        cur = self.conn.execute("""
            INSERT INTO search_requests (lat, lng, radius_m, place_type)
            VALUES (?, ?, ?, ?)
        """, (lat, lng, radius_m, place_type))
        self.conn.commit()
        return cur.lastrowid

    def get_pending_requests(self) -> list[dict]:
        rows = self.conn.execute("""
            SELECT id, lat, lng, radius_m, place_type
            FROM search_requests WHERE status = 'pending'
            ORDER BY created_at
        """).fetchall()
        return [dict(r) for r in rows]

    def update_request_status(self, req_id: int, status: str):
        self.conn.execute("""
            UPDATE search_requests
            SET status = ?, finished_at = datetime('now')
            WHERE id = ?
        """, (status, req_id))
        self.conn.commit()

    # -- API usage tracking --------------------------------------------------

    def get_setting(self, key: str, default: str = "") -> str:
        row = self.conn.execute(
            "SELECT value FROM settings WHERE key = ?", (key,)
        ).fetchone()
        return row["value"] if row else default

    def set_setting(self, key: str, value: str):
        self.conn.execute(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            (key, value),
        )
        self.conn.commit()

    def get_api_limit(self) -> int:
        """Return the configured call limit (0 = unlimited)."""
        return int(self.get_setting("api_call_limit", "1000"))

    def get_api_limit_period(self) -> str:
        """Return 'day', 'month', or 'total'."""
        return self.get_setting("api_limit_period", "month")

    def _period_filter(self) -> str:
        """SQL datetime threshold for the current period window."""
        period = self.get_api_limit_period()
        if period == "day":
            return "datetime('now', '-1 day')"
        elif period == "month":
            return "datetime('now', '-1 month')"
        elif period == "year":
            return "datetime('now', '-1 year')"
        else:  # "total" — count everything
            return "datetime('1970-01-01')"

    def get_api_calls_used(self) -> int:
        """Count API calls made within the current limit period."""
        sql = f"SELECT COUNT(*) as cnt FROM api_usage WHERE called_at >= {self._period_filter()}"
        return self.conn.execute(sql).fetchone()["cnt"]

    def record_api_call(
        self,
        lat: float = 0,
        lng: float = 0,
        radius_m: int = 0,
        place_type: str = "",
        page: int = 1,
    ):
        """Log a single API HTTP request."""
        self.conn.execute("""
            INSERT INTO api_usage (lat, lng, radius_m, place_type, page)
            VALUES (?, ?, ?, ?, ?)
        """, (lat, lng, radius_m, place_type, page))
        self.conn.commit()

    def check_api_limit(self):
        """Raise ApiLimitExceeded if the limit has been reached."""
        limit = self.get_api_limit()
        if limit <= 0:
            return  # unlimited
        used = self.get_api_calls_used()
        if used >= limit:
            raise ApiLimitExceeded(used, limit, self.get_api_limit_period())

    def get_usage_summary(self) -> dict:
        """Return a dict with current usage stats."""
        limit = self.get_api_limit()
        period = self.get_api_limit_period()
        used = self.get_api_calls_used()
        return {
            "calls_used": used,
            "calls_limit": limit,
            "calls_remaining": max(0, limit - used) if limit > 0 else -1,
            "period": period,
            "unlimited": limit <= 0,
        }


# ---------------------------------------------------------------------------
# Google Maps API client
# ---------------------------------------------------------------------------

class PlacesFetcher:
    """Fetches places from Google Maps Nearby Search API with pagination."""

    def __init__(self, api_key: str = API_KEY):
        if not api_key:
            raise ValueError(
                "GOOGLE_MAPS_API_KEY is not set. "
                "Export it as an environment variable or pass it directly."
            )
        self.api_key = api_key
        self.session = requests.Session()

    def fetch_nearby(
        self,
        lat: float,
        lng: float,
        radius_m: int,
        place_type: str = "",
        on_before_request: callable = None,
        on_after_request: callable = None,
    ) -> list[Place]:
        """
        Fetch all nearby places for a coordinate + radius.
        Automatically follows next_page_token for up to 3 pages (60 results).

        Callbacks:
          on_before_request(page)  — called before each HTTP request; raise to abort.
          on_after_request(page)   — called after each successful HTTP request.
        """
        params: dict = {
            "location": f"{lat},{lng}",
            "radius": radius_m,
            "key": self.api_key,
        }
        if place_type:
            params["type"] = place_type

        all_places: list[Place] = []
        page = 0

        while True:
            page += 1

            if on_before_request:
                on_before_request(page)

            log.info("Fetching page %d (lat=%.5f, lng=%.5f, r=%dm, type=%s)",
                     page, lat, lng, radius_m, place_type or "any")

            resp = self.session.get(NEARBY_SEARCH_URL, params=params, timeout=15)
            resp.raise_for_status()
            data = resp.json()

            status = data.get("status")
            if status not in ("OK", "ZERO_RESULTS"):
                error_msg = data.get("error_message", status)
                raise RuntimeError(f"Places API error: {error_msg}")

            for result in data.get("results", []):
                loc = result["geometry"]["location"]
                all_places.append(Place(
                    place_id=result["place_id"],
                    name=result.get("name", ""),
                    lat=loc["lat"],
                    lng=loc["lng"],
                    types=",".join(result.get("types", [])),
                ))

            if on_after_request:
                on_after_request(page)

            next_token = data.get("next_page_token")
            if not next_token:
                break

            # Google requires ~2s before the token becomes valid
            time.sleep(PAGE_DELAY)
            params = {"pagetoken": next_token, "key": self.api_key}

        log.info("Fetched %d places total.", len(all_places))
        return all_places


# ---------------------------------------------------------------------------
# Orchestrator (ties fetcher + DB together)
# ---------------------------------------------------------------------------

class PlacesService:
    """High-level service: fetch with cache, run queued requests."""

    def __init__(self, db: PlacesDB | None = None, fetcher: PlacesFetcher | None = None):
        self.db = db or PlacesDB()
        self.fetcher = fetcher or PlacesFetcher()

    def search(
        self,
        lat: float,
        lng: float,
        radius_m: int,
        place_type: str = "",
        force_refresh: bool = False,
    ) -> list[Place]:
        if not force_refresh:
            cached = self.db.get_cached(lat, lng, radius_m, place_type)
            if cached is not None:
                log.info("Cache HIT — returning %d cached places.", len(cached))
                return cached

        # Check limit *before* the first API call
        self.db.check_api_limit()

        log.info("Cache MISS — querying Google API…")

        def before_request(page: int):
            if page > 1:
                # Re-check before each pagination request
                self.db.check_api_limit()

        def after_request(page: int):
            self.db.record_api_call(lat, lng, radius_m, place_type, page)

        places = self.fetcher.fetch_nearby(
            lat, lng, radius_m, place_type,
            on_before_request=before_request,
            on_after_request=after_request,
        )
        self.db.store_results(lat, lng, radius_m, places, place_type)
        return places

    def run_queue(self):
        """Process all pending requests from the search_requests table."""
        pending = self.db.get_pending_requests()
        log.info("Processing %d pending request(s)…", len(pending))
        for req in pending:
            rid = req["id"]
            self.db.update_request_status(rid, "running")
            try:
                places = self.search(
                    req["lat"], req["lng"], req["radius_m"], req["place_type"]
                )
                self.db.update_request_status(rid, "done")
                log.info("Request #%d done — %d places.", rid, len(places))
            except Exception as exc:
                log.error("Request #%d failed: %s", rid, exc)
                self.db.update_request_status(rid, "error")


# ---------------------------------------------------------------------------
# Flask REST API (optional)
# ---------------------------------------------------------------------------

def create_app(service: PlacesService | None = None) -> "Flask":
    """Factory that builds the Flask app."""
    from flask import Flask, request, jsonify

    app = Flask(__name__)
    svc = service or PlacesService()

    @app.route("/api/places/search", methods=["GET"])
    def search_places():
        """
        GET /api/places/search?lat=40.71&lng=-74.00&radius=1000&type=restaurant&refresh=0
        Returns JSON list of {place_id, name, lat, lng, types}.
        """
        try:
            lat = float(request.args["lat"])
            lng = float(request.args["lng"])
            radius_m = int(request.args.get("radius", 1000))
        except (KeyError, ValueError) as exc:
            return jsonify({"error": f"Bad parameter: {exc}"}), 400

        place_type = request.args.get("type", "")
        force_refresh = request.args.get("refresh", "0") == "1"

        try:
            places = svc.search(lat, lng, radius_m, place_type, force_refresh)
        except ApiLimitExceeded as exc:
            return jsonify({
                "error": str(exc),
                "calls_used": exc.used,
                "calls_limit": exc.limit,
                "period": exc.period,
            }), 429
        except Exception as exc:
            return jsonify({"error": str(exc)}), 502

        return jsonify({
            "count": len(places),
            "results": [asdict(p) for p in places],
        })

    @app.route("/api/requests", methods=["POST"])
    def enqueue_request():
        """
        POST /api/requests  {lat, lng, radius_m, place_type?}
        Queues a search request for batch processing.
        """
        body = request.get_json(force=True)
        try:
            rid = svc.db.add_request(
                float(body["lat"]),
                float(body["lng"]),
                int(body["radius_m"]),
                body.get("place_type", ""),
            )
        except (KeyError, ValueError) as exc:
            return jsonify({"error": f"Bad parameter: {exc}"}), 400

        return jsonify({"request_id": rid, "status": "pending"}), 201

    @app.route("/api/requests/run", methods=["POST"])
    def run_queue():
        """POST /api/requests/run — process all pending queued requests."""
        try:
            svc.run_queue()
        except ApiLimitExceeded as exc:
            return jsonify({
                "error": str(exc),
                "calls_used": exc.used,
                "calls_limit": exc.limit,
                "period": exc.period,
            }), 429
        return jsonify({"status": "ok"})

    @app.route("/api/usage", methods=["GET"])
    def api_usage():
        """GET /api/usage — current API call usage and limits."""
        return jsonify(svc.db.get_usage_summary())

    @app.route("/api/settings", methods=["GET"])
    def get_settings():
        """GET /api/settings — all settings as key-value pairs."""
        rows = svc.db.conn.execute("SELECT key, value FROM settings").fetchall()
        return jsonify({r["key"]: r["value"] for r in rows})

    @app.route("/api/settings", methods=["PUT"])
    def update_settings():
        """
        PUT /api/settings  {"api_call_limit": "500", "api_limit_period": "day"}
        Update one or more settings.
        """
        body = request.get_json(force=True)
        allowed = {"api_call_limit", "api_limit_period"}
        for k, v in body.items():
            if k not in allowed:
                return jsonify({"error": f"Unknown setting: {k}"}), 400
            svc.db.set_setting(k, str(v))
        return jsonify({"status": "updated"})

    @app.route("/api/health", methods=["GET"])
    def health():
        return jsonify({"status": "ok"})

    return app


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Google Maps Places Scraper")
    parser.add_argument("--lat", type=float, help="Latitude of search center")
    parser.add_argument("--lng", type=float, help="Longitude of search center")
    parser.add_argument("--radius", type=int, default=1000, help="Radius in meters (default 1000)")
    parser.add_argument("--type", dest="place_type", default="", help="Place type filter (e.g. restaurant)")
    parser.add_argument("--refresh", action="store_true", help="Bypass cache and re-fetch")
    parser.add_argument("--run-queue", action="store_true", help="Process all pending DB requests")
    parser.add_argument("--serve", action="store_true", help="Start Flask REST server")
    parser.add_argument("--port", type=int, default=5000, help="Flask port (default 5000)")
    parser.add_argument("--db", default=DB_PATH, help="SQLite database path")
    parser.add_argument("--usage", action="store_true", help="Show API usage stats and exit")
    parser.add_argument("--set-limit", type=int, metavar="N", help="Set API call limit (0 = unlimited)")
    parser.add_argument("--set-period", choices=["day", "month", "year", "total"],
                        help="Set limit period window")
    args = parser.parse_args()

    db = PlacesDB(args.db)

    # -- settings commands ---------------------------------------------------
    if args.set_limit is not None:
        db.set_setting("api_call_limit", str(args.set_limit))
        print(f"API call limit set to {args.set_limit}"
              f"{' (unlimited)' if args.set_limit == 0 else ''}.")

    if args.set_period:
        db.set_setting("api_limit_period", args.set_period)
        print(f"API limit period set to '{args.set_period}'.")

    if args.set_limit is not None or args.set_period:
        if not (args.lat or args.run_queue or args.serve or args.usage):
            return  # just updating settings

    if args.usage:
        s = db.get_usage_summary()
        print(f"\n  API Usage")
        print(f"  ─────────────────────────")
        print(f"  Period:    {s['period']}")
        print(f"  Used:      {s['calls_used']}")
        print(f"  Limit:     {'unlimited' if s['unlimited'] else s['calls_limit']}")
        if not s["unlimited"]:
            print(f"  Remaining: {s['calls_remaining']}")
        print()
        return

    if args.serve:
        svc = PlacesService(db=db)
        app = create_app(svc)
        log.info("Starting Flask on port %d…", args.port)
        app.run(host="0.0.0.0", port=args.port, debug=False)
        return

    if args.run_queue:
        svc = PlacesService(db=db)
        svc.run_queue()
        return

    if args.lat is None or args.lng is None:
        parser.error("--lat and --lng are required for a direct search.")

    svc = PlacesService(db=db)
    try:
        places = svc.search(args.lat, args.lng, args.radius, args.place_type, args.refresh)
    except ApiLimitExceeded as exc:
        s = db.get_usage_summary()
        print(f"\n  ERROR: {exc}")
        print(f"  Adjust with: --set-limit <N>  or  --set-period <day|month|year|total>\n")
        raise SystemExit(1)

    print(f"\n{'='*70}")
    print(f" Found {len(places)} places near ({args.lat}, {args.lng}) r={args.radius}m")
    print(f"{'='*70}\n")
    for p in places:
        print(f"  {p.place_id}  |  {p.lat:>10.6f}, {p.lng:>11.6f}  |  {p.name}")
    print()


if __name__ == "__main__":
    main()
