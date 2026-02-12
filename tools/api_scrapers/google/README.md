# Google Maps Places Scraper

Fetches all Google Maps "places" within a coordinate + radius using the Nearby Search API. Returns minimal data: `place_id`, `name`, `lat`, `lng`, and `types`.

## Architecture

```
┌──────────────┐     ┌────────────────┐     ┌─────────────────┐
│  CLI / Flask  │────▶│ PlacesService  │────▶│  PlacesFetcher  │──▶ Google API
│   REST API   │     │  (orchestrator) │     │  (HTTP client)  │
└──────────────┘     └───────┬────────┘     └─────────────────┘
                             │
                     ┌───────▼────────┐
                     │   PlacesDB     │
                     │   (SQLite)     │
                     └────────────────┘
```

**Key tables:**
| Table | Purpose |
|---|---|
| `places` | Deduplicated place records (keyed by `place_id`) |
| `search_cache` | Maps a query fingerprint → metadata |
| `search_cache_places` | Junction: which places belong to which cached query |
| `search_requests` | Queue of pending/completed batch search jobs |

## Setup

```bash
pip install -r requirements.txt
export GOOGLE_MAPS_API_KEY="your-key-here"
```

## Usage

### 1. Direct search (CLI)

```bash
python places_scraper.py --lat 40.7128 --lng -74.0060 --radius 1500
python places_scraper.py --lat 48.8566 --lng 2.3522 --radius 500 --type restaurant
python places_scraper.py --lat 40.7128 --lng -74.0060 --radius 1000 --refresh   # bypass cache
```

### 2. Batch queue (DB-driven)

Insert rows into `search_requests` manually or via the API, then process them:

```bash
# via SQLite directly
sqlite3 places_cache.db "INSERT INTO search_requests (lat, lng, radius_m, place_type) VALUES (51.5074, -0.1278, 2000, 'cafe');"

# run all pending
python places_scraper.py --run-queue
```

### 3. Flask REST API

```bash
python places_scraper.py --serve --port 5000
```

**Endpoints:**

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/places/search?lat=...&lng=...&radius=...&type=...&refresh=0` | Search (cached) |
| `POST` | `/api/requests` | Enqueue a search job |
| `POST` | `/api/requests/run` | Process all pending jobs |
| `GET` | `/api/health` | Health check |

**Examples:**

```bash
# search (returns cached if available)
curl "http://localhost:5000/api/places/search?lat=40.7128&lng=-74.006&radius=1000&type=restaurant"

# enqueue for batch
curl -X POST http://localhost:5000/api/requests \
  -H "Content-Type: application/json" \
  -d '{"lat": 51.5074, "lng": -0.1278, "radius_m": 2000, "place_type": "bar"}'

# run queue
curl -X POST http://localhost:5000/api/requests/run
```

**Response format:**

```json
{
  "count": 42,
  "results": [
    {
      "place_id": "ChIJaXQRs6...",
      "name": "Joe's Pizza",
      "lat": 40.7308,
      "lng": -73.9892,
      "types": "restaurant,food,point_of_interest,establishment"
    }
  ]
}
```

## Cache strategy

Queries are fingerprinted by `(lat, lng, radius, type)` rounded to 6 decimal places. A SHA-256 hash of these params serves as the cache key. Repeat identical queries hit the SQLite cache with zero API calls. Use `--refresh` or `?refresh=1` to bypass.

## API limits

Google's Nearby Search returns a maximum of **60 results** per query (3 pages × 20). For exhaustive coverage of a large area, tile the region into overlapping circles and enqueue them all via `search_requests`.

## API call tracking & rate limiting

Every HTTP request to Google (each page counts as 1 call) is logged in the `api_usage` table. A configurable limit prevents runaway spending.

**Defaults:** 1000 calls per month. Adjust via CLI or API.

### CLI

```bash
# Check current usage
python places_scraper.py --usage

# Set limit to 500 calls per day
python places_scraper.py --set-limit 500 --set-period day

# Unlimited
python places_scraper.py --set-limit 0

# Combine with a search (limit is checked before calling Google)
python places_scraper.py --set-limit 200 --lat 40.7128 --lng -74.006 --radius 1000
```

When the limit is reached, CLI exits with code 1 and a clear error. The Flask API returns **HTTP 429** with a JSON body:

```json
{
  "error": "API call limit reached: 500/500 calls used in the current day window.",
  "calls_used": 500,
  "calls_limit": 500,
  "period": "day"
}
```

### REST endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/usage` | Current usage stats (used, limit, remaining, period) |
| `GET` | `/api/settings` | All settings as key-value pairs |
| `PUT` | `/api/settings` | Update settings: `{"api_call_limit": "500", "api_limit_period": "day"}` |

### Period options

| Value | Window |
|---|---|
| `day` | Rolling 24 hours |
| `month` | Rolling 30 days |
| `year` | Rolling 365 days |
| `total` | All-time (lifetime cap) |

### Direct DB access

```sql
-- See all API calls
SELECT * FROM api_usage ORDER BY called_at DESC LIMIT 20;

-- Manually adjust limit
UPDATE settings SET value = '2000' WHERE key = 'api_call_limit';

-- Reset usage (nuclear option)
DELETE FROM api_usage;
```
