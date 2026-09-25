"""Source entities and their conformed (silver) schemas."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Entity:
    name: str
    source: str  # landing folder: crm (Azure SQL via ADF) or listings_api (REST via ADF)
    file_format: str  # format ADF lands the data in
    key: str
    columns: tuple[tuple[str, str], ...]  # (name, Spark SQL type) in silver

    @property
    def column_names(self) -> list[str]:
        return [c for c, _ in self.columns]

    def landing_ddl(self) -> str:
        """Schema of the landed files. Decimals arrive as doubles from the source extract."""
        return ", ".join(f"{c} {'double' if t.startswith('decimal') else t}" for c, t in self.columns)


PROPERTIES = Entity(
    name="properties",
    source="crm",
    file_format="parquet",
    key="property_id",
    columns=(
        ("property_id", "string"),
        ("address_line", "string"),
        ("city", "string"),
        ("state", "string"),
        ("postal_code", "string"),
        ("property_type", "string"),
        ("bedrooms", "int"),
        ("bathrooms", "double"),
        ("square_feet", "int"),
        ("year_built", "int"),
        ("updated_at", "timestamp"),
    ),
)

AGENTS = Entity(
    name="agents",
    source="crm",
    file_format="parquet",
    key="agent_id",
    columns=(
        ("agent_id", "string"),
        ("first_name", "string"),
        ("last_name", "string"),
        ("email", "string"),
        ("office", "string"),
        ("license_number", "string"),
        ("hired_date", "date"),
        ("updated_at", "timestamp"),
    ),
)

SALES_TRANSACTIONS = Entity(
    name="sales_transactions",
    source="crm",
    file_format="parquet",
    key="transaction_id",
    columns=(
        ("transaction_id", "string"),
        ("property_id", "string"),
        ("agent_id", "string"),
        ("sale_price", "decimal(18,2)"),
        ("sale_date", "date"),
        ("closing_date", "date"),
        ("financing_type", "string"),
        ("updated_at", "timestamp"),
    ),
)

LEASES = Entity(
    name="leases",
    source="crm",
    file_format="parquet",
    key="lease_id",
    columns=(
        ("lease_id", "string"),
        ("property_id", "string"),
        ("agent_id", "string"),
        ("monthly_rent", "decimal(12,2)"),
        ("lease_start", "date"),
        ("lease_end", "date"),
        ("updated_at", "timestamp"),
    ),
)

LISTINGS = Entity(
    name="listings",
    source="listings_api",
    file_format="json",
    key="listing_id",
    columns=(
        ("listing_id", "string"),
        ("property_id", "string"),
        ("agent_id", "string"),
        ("list_price", "decimal(18,2)"),
        ("status", "string"),
        ("listed_at", "timestamp"),
        ("updated_at", "timestamp"),
    ),
)

ENTITIES: dict[str, Entity] = {e.name: e for e in (PROPERTIES, AGENTS, SALES_TRANSACTIONS, LEASES, LISTINGS)}

# Upper/lower-casing applied during conformance.
UPPERCASE_COLUMNS = {"state", "property_type", "status", "financing_type"}
LOWERCASE_COLUMNS = {"email"}
