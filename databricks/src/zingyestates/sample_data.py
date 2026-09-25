"""Deterministic synthetic source data for local runs, demos and tests.

Mimics what ADF lands: CRM tables as Parquet and the listings API as JSON Lines.
A handful of deliberately bad records exercise the data-quality rules and the
quarantine zone.
"""

from __future__ import annotations

import json
import random
from datetime import date, datetime, timedelta
from pathlib import Path

from zingyestates.config import PlatformConfig
from zingyestates.entities import ENTITIES

CITIES = [
    ("Austin", "TX", "787"),
    ("Dallas", "TX", "752"),
    ("Denver", "CO", "802"),
    ("Phoenix", "AZ", "850"),
    ("Atlanta", "GA", "303"),
    ("Charlotte", "NC", "282"),
    ("Tampa", "FL", "336"),
    ("Nashville", "TN", "372"),
]
STREETS = ["Oak", "Maple", "Cedar", "Pine", "Elm", "Lakeview", "Hillcrest", "Sunset", "Park", "River"]
PROPERTY_TYPES = ["SINGLE_FAMILY", "CONDO", "TOWNHOUSE", "MULTI_FAMILY", "COMMERCIAL"]
FIRST_NAMES = ["Ava", "Liam", "Maya", "Noah", "Zoe", "Ethan", "Priya", "Mateo", "Chloe", "Omar", "Grace", "Kai"]
LAST_NAMES = ["Nguyen", "Garcia", "Smith", "Patel", "Johnson", "Kim", "Okafor", "Rossi", "Brown", "Silva"]
OFFICES = ["Austin Central", "Dallas Uptown", "Denver LoDo", "Phoenix North", "Atlanta Midtown"]


def generate(run_date: str, n_properties: int = 250, n_agents: int = 25, seed: int = 42) -> dict[str, list[dict]]:
    rng = random.Random(seed)
    today = datetime.strptime(run_date, "%Y-%m-%d").date()
    stamp = datetime.combine(today, datetime.min.time()) + timedelta(hours=1)

    def past(days_max: int, days_min: int = 0) -> date:
        return today - timedelta(days=rng.randint(days_min, days_max))

    agents = []
    for i in range(1, n_agents + 1):
        first, last = rng.choice(FIRST_NAMES), rng.choice(LAST_NAMES)
        agents.append(
            {
                "agent_id": f"AG{i:04d}",
                "first_name": first,
                "last_name": last,
                "email": f"{first}.{last}{i}@zingyestates.example".lower(),
                "office": rng.choice(OFFICES),
                "license_number": f"LIC-{rng.randint(100000, 999999)}",
                "hired_date": past(3650, 90),
                "updated_at": stamp,
            }
        )

    properties = []
    for i in range(1, n_properties + 1):
        city, state, zip_prefix = rng.choice(CITIES)
        ptype = rng.choice(PROPERTY_TYPES)
        beds = 0 if ptype == "COMMERCIAL" else rng.randint(1, 6)
        properties.append(
            {
                "property_id": f"PR{i:05d}",
                "address_line": f"{rng.randint(10, 9999)} {rng.choice(STREETS)} St",
                "city": city,
                "state": state.lower() if i % 17 == 0 else state,  # conformance upper-cases these
                "postal_code": f"{zip_prefix}{rng.randint(10, 99)}",
                "property_type": ptype,
                "bedrooms": beds,
                "bathrooms": float(max(1, beds) + rng.choice([0, 0.5, 1])),
                "square_feet": rng.randint(650, 5200) if ptype != "COMMERCIAL" else rng.randint(3000, 25000),
                "year_built": rng.randint(1925, today.year),
                "updated_at": stamp,
            }
        )

    sales, leases, listings = [], [], []
    for i, prop in enumerate(properties, start=1):
        agent = rng.choice(agents)["agent_id"]
        base = prop["square_feet"] * rng.uniform(180, 520)
        roll = rng.random()
        if roll < 0.45:
            sale_date = past(720, 10)
            sales.append(
                {
                    "transaction_id": f"TX{i:06d}",
                    "property_id": prop["property_id"],
                    "agent_id": agent,
                    "sale_price": round(base, 2),
                    "sale_date": sale_date,
                    "closing_date": sale_date + timedelta(days=rng.randint(20, 60)),
                    "financing_type": rng.choice(["conventional", "fha", "va", "cash"]),
                    "updated_at": stamp,
                }
            )
        elif roll < 0.75:
            start = past(540, 5)
            leases.append(
                {
                    "lease_id": f"LS{i:06d}",
                    "property_id": prop["property_id"],
                    "agent_id": agent,
                    "monthly_rent": round(base * 0.0055, 2),
                    "lease_start": start,
                    "lease_end": start + timedelta(days=rng.choice([180, 365, 730])),
                    "updated_at": stamp,
                }
            )
        listed = datetime.combine(past(120), datetime.min.time()) + timedelta(hours=rng.randint(8, 18))
        listings.append(
            {
                "listing_id": f"LI{i:06d}",
                "property_id": prop["property_id"],
                "agent_id": agent,
                "list_price": round(base * rng.uniform(0.97, 1.08), 2),
                "status": rng.choice(["ACTIVE", "ACTIVE", "PENDING", "SOLD", "WITHDRAWN"]),
                "listed_at": listed.isoformat(),
                "updated_at": stamp.isoformat(),
            }
        )

    # Deliberate defects -> quarantine.
    properties.append({**properties[0], "property_id": "PR99901", "square_feet": -40})
    properties.append({**properties[1], "property_id": "PR99902", "property_type": "CASTLE"})
    agents.append({**agents[0], "agent_id": "AG9901", "email": "not-an-email"})
    sales.append({**sales[0], "transaction_id": "TX999901", "sale_price": 0.0})
    sales.append({**sales[1], "transaction_id": "TX999902", "closing_date": sales[1]["sale_date"] - timedelta(days=3)})
    leases.append({**leases[0], "lease_id": "LS999901", "lease_end": leases[0]["lease_start"]})
    listings.append({**listings[0], "listing_id": "LI999901", "status": "UNKNOWN"})
    # Duplicate: an older version of an existing sale arrives in the same extract.
    sales.append({**sales[2], "sale_price": sales[2]["sale_price"] - 1000, "updated_at": stamp - timedelta(days=1)})

    return {
        "properties": properties,
        "agents": agents,
        "sales_transactions": sales,
        "leases": leases,
        "listings": listings,
    }


def write_landing(spark, cfg: PlatformConfig, run_date: str, data: dict[str, list[dict]]) -> None:
    for name, rows in data.items():
        entity = ENTITIES[name]
        target = cfg.landing_path(entity.source, name, run_date)
        if entity.file_format == "parquet":
            spark.createDataFrame(rows, schema=entity.landing_ddl()).coalesce(1).write.mode("overwrite").parquet(target)
        else:
            path = Path(target)
            path.mkdir(parents=True, exist_ok=True)
            with open(path / "part-00000.json", "w", encoding="utf-8") as fh:
                for row in rows:
                    fh.write(json.dumps(row, default=str) + "\n")
