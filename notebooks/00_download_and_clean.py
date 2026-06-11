# -*- coding: utf-8 -*-
"""
NutriSales Insights — Phase 1: Data Download & Cleaning
==========================================================
This script downloads the UCI Online Retail dataset, cleans it,
and exports clean_retail.csv + populates the SQLite database.

Run this BEFORE opening 01_eda.ipynb
"""

import os
import urllib.request
import zipfile
import pandas as pd
import sqlite3

# ── Paths ──────────────────────────────────────────────────────────────────
BASE_DIR  = os.path.dirname(os.path.abspath(__file__))
DATA_DIR  = os.path.join(BASE_DIR, "..", "data")
os.makedirs(DATA_DIR, exist_ok=True)

RAW_PATH   = os.path.join(DATA_DIR, "online_retail.csv")
CLEAN_PATH = os.path.join(DATA_DIR, "clean_retail.csv")
DB_PATH    = os.path.join(DATA_DIR, "retail.db")

# ── 1. Download dataset ─────────────────────────────────────────────────────
UCI_URL = (
    "https://archive.ics.uci.edu/static/public/352/online+retail.zip"
)

def download_dataset():
    zip_path = os.path.join(DATA_DIR, "online_retail.zip")
    xlsx_path = os.path.join(DATA_DIR, "Online Retail.xlsx")

    if os.path.exists(RAW_PATH):
        print(f"[OK] Raw data already exists: {RAW_PATH}")
        return

    print("[->] Downloading UCI Online Retail dataset (~23 MB)...")
    urllib.request.urlretrieve(UCI_URL, zip_path)
    print("[OK] Download complete.")

    print("[->] Extracting zip...")
    with zipfile.ZipFile(zip_path, "r") as z:
        z.extractall(DATA_DIR)
    print("[OK] Extracted.")

    print("[->] Converting Excel to CSV...")
    df_raw = pd.read_excel(xlsx_path, dtype={"CustomerID": str})
    df_raw.to_csv(RAW_PATH, index=False, encoding="utf-8")
    print(f"[OK] Saved raw CSV: {RAW_PATH}")

    os.remove(zip_path)

# ── 2. Load raw data ────────────────────────────────────────────────────────
def load_raw():
    print(f"\n[->] Loading raw data from {RAW_PATH}...")
    try:
        df = pd.read_csv(RAW_PATH, encoding="utf-8", dtype={"CustomerID": str})
    except UnicodeDecodeError:
        df = pd.read_csv(RAW_PATH, encoding="ISO-8859-1", dtype={"CustomerID": str})

    print(f"[OK] Loaded: {df.shape[0]:,} rows x {df.shape[1]} columns")
    return df

# ── 3. Clean data ───────────────────────────────────────────────────────────
def clean_data(df: pd.DataFrame) -> pd.DataFrame:
    print("\n[->] Cleaning data...")
    n_raw = len(df)

    # Step 3.1: Drop rows with missing CustomerID
    df = df.dropna(subset=["CustomerID"])
    print(f"  Dropped missing CustomerID: {n_raw - len(df):,} rows removed")

    # Step 3.2: Remove cancelled orders (InvoiceNo starts with 'C')
    before = len(df)
    df = df[~df["InvoiceNo"].astype(str).str.startswith("C")]
    print(f"  Removed cancellations: {before - len(df):,} rows removed")

    # Step 3.3: Remove negative/zero quantities and zero prices
    before = len(df)
    df = df[(df["Quantity"] > 0) & (df["UnitPrice"] > 0)]
    print(f"  Removed invalid Quantity/Price rows: {before - len(df):,} rows removed")

    # Step 3.4: Parse InvoiceDate to datetime
    df["InvoiceDate"] = pd.to_datetime(df["InvoiceDate"])

    # Step 3.5: Engineer new columns
    df["UnitPrice"]  = df["UnitPrice"] * 105 # Convert GBP to INR (approx rate)
    df["Revenue"]    = df["Quantity"] * df["UnitPrice"]
    df["Month"]      = df["InvoiceDate"].dt.to_period("M").astype(str)
    df["Year"]       = df["InvoiceDate"].dt.year
    df["Hour"]       = df["InvoiceDate"].dt.hour
    df["DayOfWeek"]  = df["InvoiceDate"].dt.day_name()

    # Step 3.6: Strip whitespace from Description
    df["Description"] = df["Description"].astype(str).str.strip().str.upper()

    print(f"\n[OK] Clean dataset: {len(df):,} rows ({n_raw - len(df):,} removed total)")
    print(f"    Revenue range: INR {df['Revenue'].min():.2f} - INR {df['Revenue'].max():,.2f}")
    
    return df

# ── 4. Save outputs ─────────────────────────────────────────────────────────
def save_outputs(df: pd.DataFrame):
    df.to_csv(CLEAN_PATH, index=False, encoding="utf-8")
    print(f"\n[OK] Saved: {CLEAN_PATH}")

    conn = sqlite3.connect(DB_PATH)
    df.to_sql("sales", conn, if_exists="replace", index=False)
    conn.close()
    print(f"[OK] SQLite DB populated: {DB_PATH}")


if __name__ == "__main__":
    download_dataset()
    df_raw   = load_raw()
    df_clean = clean_data(df_raw)
    save_outputs(df_clean)
    print("\n[DONE] Phase 1 complete! Run notebooks/01_eda.ipynb next.\n")
