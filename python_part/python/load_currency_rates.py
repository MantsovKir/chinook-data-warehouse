"""
Load historical USD to ILS exchange rates into the staging schema.

Steps:
1. Read distinct invoice dates from stg.invoice.
2. Request historical USD -> ILS exchange rates from the Frankfurter API.
3. Load the result into stg.currency_rates.
"""

import time

import pandas as pd
import requests

from db_connection import get_database_engine


def get_invoice_dates(engine):
    """Read all distinct invoice dates from the staging invoice table."""
    query = """
        SELECT DISTINCT invoicedate::date AS rate_date
        FROM stg.invoice
        ORDER BY rate_date;
    """
    return pd.read_sql(query, engine)


def fetch_exchange_rate(rate_date, from_currency="USD", to_currency="ILS"):
    """Fetch exchange rate for a specific date."""
    url = f"https://api.frankfurter.app/{rate_date}?from={from_currency}&to={to_currency}"

    response = requests.get(url, timeout=15)
    response.raise_for_status()
    data = response.json()

    return {
        "requested_date": rate_date,
        "api_rate_date": data["date"],
        "from_currency": data["base"],
        "to_currency": to_currency,
        "exchange_rate": data["rates"][to_currency],
    }


def main():
    """Run the currency-rate ETL process."""
    engine = get_database_engine()
    dates_df = get_invoice_dates(engine)

    print(f"Found {len(dates_df)} distinct invoice dates.")

    currency_rows = []

    for rate_date in dates_df["rate_date"]:
        print(f"Loading rate for {rate_date}")

        try:
            currency_rows.append(fetch_exchange_rate(rate_date))
        except requests.RequestException as error:
            print(f"Failed to load rate for {rate_date}: {error}")

        time.sleep(0.1)

    currency_rates_df = pd.DataFrame(currency_rows)

    print(currency_rates_df.head())
    print(f"Prepared {len(currency_rates_df)} exchange-rate rows.")

    currency_rates_df.to_sql(
        "currency_rates",
        engine,
        schema="stg",
        if_exists="replace",
        index=False,
    )

    print("currency_rates loaded to stg.currency_rates")


if __name__ == "__main__":
    main()
