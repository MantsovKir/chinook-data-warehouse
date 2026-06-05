# Python ETL

This folder contains the Python part of the Chinook Data Warehouse project.

## Files

- `db_connection.py` — creates a SQLAlchemy connection using environment variables.
- `load_department_budget.py` — prepares department budget data from raw files and loads it into `stg.department_budget`.
- `load_currency_rates.py` — loads historical USD to ILS exchange rates from the Frankfurter API into `stg.currency_rates`.

## Security

Database credentials are not stored in the code.  
Use `.env.example` as a template and create a local `.env` file.

The real `.env` file is ignored by Git and must not be uploaded to GitHub.

## Run

Install dependencies:

```bash
pip install -r requirements.txt
```

Create `.env` from `.env.example`, then run:

```bash
python python/load_department_budget.py
python python/load_currency_rates.py
```
