#!/usr/bin/env python3
"""Display the current chain state."""
import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).parent / "chain.db"
db = sqlite3.connect(DB_PATH)
for row in db.execute("SELECT id, intent, signer, record_hash FROM records ORDER BY id"):
    print(f"{row[0]:3}  {row[1]:<12}  {row[2]:<20}  {row[3]}")
