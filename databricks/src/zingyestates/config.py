"""Environment-aware lake locations."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

ZONES = ("landing", "bronze", "silver", "gold", "quarantine")
ENVIRONMENTS = ("local", "dev", "qa", "uat", "prod")


@dataclass(frozen=True)
class PlatformConfig:
    environment: str
    zone_roots: dict[str, str]

    def __post_init__(self) -> None:
        if self.environment not in ENVIRONMENTS:
            raise ValueError(f"Unknown environment {self.environment!r}; expected one of {ENVIRONMENTS}")
        missing = set(ZONES) - set(self.zone_roots)
        if missing:
            raise ValueError(f"Missing zone roots: {sorted(missing)}")

    @classmethod
    def for_azure(cls, environment: str, storage_account: str) -> PlatformConfig:
        """ADLS Gen2: one file system (container) per zone, as created by terraform/modules/storage."""
        if not storage_account:
            raise ValueError("storage_account is required for Azure environments")
        return cls(
            environment=environment,
            zone_roots={z: f"abfss://{z}@{storage_account}.dfs.core.windows.net" for z in ZONES},
        )

    @classmethod
    def for_local(cls, base_dir: str | Path) -> PlatformConfig:
        """Local filesystem lake used by docker compose and tests."""
        base = Path(base_dir).resolve()
        return cls(environment="local", zone_roots={z: (base / z).as_posix() for z in ZONES})

    def zone(self, zone: str) -> str:
        return self.zone_roots[zone]

    def table_path(self, zone: str, table: str) -> str:
        return f"{self.zone_roots[zone]}/{table}"

    def landing_path(self, source: str, entity: str, run_date: str) -> str:
        return f"{self.zone_roots['landing']}/{source}/{entity}/ingest_date={run_date}"

    def export_path(self, table: str, run_date: str) -> str:
        """Parquet snapshot of a gold table that Synapse dedicated SQL loads with COPY INTO."""
        return f"{self.zone_roots['gold']}/_exports/{table}/run_date={run_date}"
