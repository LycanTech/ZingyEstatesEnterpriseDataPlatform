import pytest

from zingyestates.entities import AGENTS, PROPERTIES
from zingyestates.quality import RULES, Rule, apply_rules, latest_per_key
from zingyestates.silver import conform

pytestmark = pytest.mark.spark


def test_apply_rules_splits_and_names_failures(spark):
    df = spark.createDataFrame([(1, 10), (2, -1), (None, 5)], "id int, amount int")
    rules = [Rule("id_present", "id IS NOT NULL"), Rule("amount_positive", "amount > 0")]

    valid, rejected = apply_rules(df, rules)

    assert [r.id for r in valid.collect()] == [1]
    failures = {r.amount: r._dq_failures for r in rejected.collect()}
    assert failures == {-1: ["amount_positive"], 5: ["id_present"]}


def test_null_rule_result_is_a_failure(spark):
    df = spark.createDataFrame([(None,)], "amount int")
    _, rejected = apply_rules(df, [Rule("amount_positive", "amount > 0")])
    assert rejected.count() == 1


def test_email_rule(spark):
    rows = [("a1", "ok@zingyestates.example", "L1"), ("a2", "not-an-email", "L2"), ("a3", "two words@x.com", "L3")]
    df = spark.createDataFrame(rows, "agent_id string, email string, license_number string")
    valid, _ = apply_rules(df, RULES["agents"])
    assert [r.agent_id for r in valid.collect()] == ["a1"]


def test_latest_per_key_keeps_newest(spark):
    df = spark.createDataFrame(
        [("p1", "2026-01-01 00:00:00", "old"), ("p1", "2026-02-01 00:00:00", "new"), ("p2", "2026-01-01 00:00:00", "only")],
        "property_id string, updated_at string, v string",
    ).selectExpr("property_id", "cast(updated_at as timestamp) updated_at", "v", "current_timestamp() _ingested_at")
    result = {r.property_id: r.v for r in latest_per_key(df, "property_id").collect()}
    assert result == {"p1": "new", "p2": "only"}


def test_conform_casts_trims_and_standardises(spark):
    df = spark.createDataFrame(
        [(" PR1 ", " tx ", "condo", "abc", "a@B.COM")],
        "property_id string, state string, property_type string, square_feet string, email string",
    )
    row = conform(df, PROPERTIES).first()
    assert row.property_id == "PR1"
    assert row.state == "TX"
    assert row.property_type == "CONDO"
    assert row.square_feet is None  # unparseable -> NULL -> fails square_feet_positive
    assert row.bedrooms is None  # missing column is added as NULL

    assert conform(df.withColumnRenamed("property_id", "agent_id"), AGENTS).first().email == "a@b.com"
