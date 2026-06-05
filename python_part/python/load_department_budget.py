"""
Prepare and load department budget data into the staging schema.

The input files are stored in data/raw:
- raw-department.txt
- raw-department-budget.txt
- raw-department-budget2.txt
"""

from pathlib import Path

import pandas as pd

from db_connection import get_database_engine


ROOT_DIR = Path(__file__).resolve().parents[1]
RAW_DATA_DIR = ROOT_DIR / "data" / "raw"


def prepare_department_budget():
    """Read raw department files and aggregate budget by department."""
    departments = pd.read_csv(
        RAW_DATA_DIR / "raw-department.txt",
        sep="-",
    )

    budget_source_1 = pd.read_json(
        RAW_DATA_DIR / "raw-department-budget.txt",
        lines=True,
    )

    budget_source_2 = pd.read_json(
        RAW_DATA_DIR / "raw-department-budget2.txt",
    )

    budget_source_all = pd.concat(
        [budget_source_1, budget_source_2],
        ignore_index=True,
    )

    merged_departments_budget = pd.merge(
        budget_source_all,
        departments,
        on="department_id",
        how="left",
    )

    department_budget_summary = (
        merged_departments_budget
        .groupby(["department_id", "department_name"])["budget"]
        .sum()
        .reset_index()
    )

    return department_budget_summary


def main():
    """Load the prepared department budget table into stg.department_budget."""
    engine = get_database_engine()
    department_budget_summary = prepare_department_budget()

    print(department_budget_summary)

    department_budget_summary.to_sql(
        "department_budget",
        engine,
        schema="stg",
        if_exists="replace",
        index=False,
    )

    print("department_budget loaded to stg.department_budget")


if __name__ == "__main__":
    main()
