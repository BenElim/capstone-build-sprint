// MongoDB layer: GPS / temperature collar readings (NOT RUN in the build sandbox: no mongod available.
// Run with:  mongosh "mongodb://localhost:27017/ndume" collar_readings.js )
// Why Mongo: append-only, high-volume (one reading per animal every few minutes), payload differs by
// collar vendor, and the only access patterns are "latest readings for animal X" and "readings in a time range".
// PostgreSQL keeps the master data; Mongo stores only animal_id / ranch_id references to it.

db = db.getSiblingDB("ndume");

// Time-series collection: columnar compression + automatic expiry after 180 days.
db.createCollection("collar_readings", {
  timeseries: { timeField: "ts", metaField: "meta", granularity: "minutes" },
  expireAfterSeconds: 60 * 60 * 24 * 180
});

// meta = { ranch_id, animal_id, collar_id }   (ids are the PostgreSQL keys)
db.collar_readings.createIndex({ "meta.ranch_id": 1, "meta.animal_id": 1, ts: -1 });

// Sample inserts: two vendors, different fields, no migration needed.
db.collar_readings.insertMany([
  { ts: new Date("2026-10-01T06:00:00Z"), meta: { ranch_id: 1, animal_id: 12, collar_id: "A-7731" },
    lat: -0.3031, lon: 36.0800, temp_c: 38.6, battery_pct: 91 },
  { ts: new Date("2026-10-01T06:05:00Z"), meta: { ranch_id: 1, animal_id: 12, collar_id: "A-7731" },
    lat: -0.3034, lon: 36.0803, temp_c: 38.7, battery_pct: 91 },
  { ts: new Date("2026-10-01T06:00:00Z"), meta: { ranch_id: 1, animal_id: 15, collar_id: "B-2210" },
    position: { type: "Point", coordinates: [36.0811, -0.3040] }, body_temp_f: 101.8, activity_score: 42 }
]);

// Access pattern 1: latest reading per animal for a ranch
db.collar_readings.aggregate([
  { $match: { "meta.ranch_id": 1 } },
  { $sort: { ts: -1 } },
  { $group: { _id: "$meta.animal_id", last_seen: { $first: "$ts" }, temp_c: { $first: "$temp_c" } } }
]);

// Access pattern 2: fever alert (temperature above 39.5 C in the last 24 hours)
db.collar_readings.find({ "meta.ranch_id": 1, ts: { $gte: new Date(Date.now() - 864e5) }, temp_c: { $gt: 39.5 } });

// Link back to PostgreSQL: the application stores alerts it cares about in health_events (relational, audited).
