"""00_description_hash.py -- what 01_clean.do needs from the vacancy descriptions.

Stata cannot read the descriptions: they are only in the export's Parquet file. This script
writes, for every vacancy id:
  desc_hash  a short fingerprint of the description, so 01_clean.do can tell whether two
             vacancies have the same text without carrying the text itself (which still
             holds contact first names). Same text -> same hash, after collapsing whitespace.
  desc_len   length of the description, characters
  pay_unit   the period the posted salary refers to, when the posting says it:
             hour, day (day or shift), week, month, piece (piece rate, per task, per m2...),
             thousands (a number like 14 meaning 14,000), or "" (not stated).
             Read first from salary_comment, then from the words right after the salary
             figure in the description ("500 грн за зміну", "60 грн/год").
  desc_address 1 if the description names a street address or a precise place of work
             (вул./вулиця, адреса, просп./проспект, пров./провулок, бульв., площа, ТЦ/ТРЦ,
             ст. м. = metro station; Ukrainian and Russian spellings). Used by 01_clean.do
             (step 7) to tell local openings from one job advertised in several cities.

Run once per export, before 01_clean.do (from the Project folder):
    python do/00_description_hash.py "<export folder>"
Default export folder: the one below (keep in line with 01_clean.do).

Output: data/temp/robota_description_hash.csv  (id, desc_hash, desc_len, pay_unit, desc_address)
"""
import hashlib
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd

PROJECT = Path(__file__).resolve().parent.parent
DEFAULT_EXPORT = PROJECT.parent / "Collector" / "data" / "exports" / "20261106_123402"
OUT = PROJECT / "data" / "temp" / "robota_description_hash.csv"

# Words that name the pay period (Ukrainian and Russian). Checked in this order.
UNITS = {
    "hour":  r"годин|\bгод\b|/\s?год|\bв час|за час|/\s?час|почасов|погодин|per hour|/h\b",
    "day":   r"\bден|\bдня\b|\bдень|змін|смен|\bдоб[аиу]|сутк|щоденн|ежедневн",
    "week":  r"тижд|недел",
    "month": r"\bміс|\bмес|month",
    "piece": r"виробіт|выработ|відрядн|сдельн|\bм2|м\.?\s?кв|кв\.?\s?м|куб|за одиниц|за штук|за урок|за заняття|за занятие|за об'єкт",
}


# A street address or precise place of work named in the text (lowercased).
ADDRESS = (r"\bвул\.|\bвулиц|\bул\.|\bулиц|\bадрес|\bпросп|\bпр-т|\bпров\.|\bпровул|\bпереул"
           r"|\bбульв|\bб-р\b|\bплоща\b|\bплощадь\b|\bтрц\b|\bтц\b|\bст\.\s?м\.|\bметро\b")


def fingerprint(text):
    t = re.sub(r"\s+", " ", text or "").strip()
    return hashlib.md5(t.encode("utf-8")).hexdigest()[:16] if t else ""


def first_unit(text):
    for unit, pattern in UNITS.items():
        if re.search(pattern, text):
            return unit
    return ""


def words_after_salary(desc, values):
    """The ~45 characters after each place the posted salary figures appear in the text."""
    out = []
    for v in values:
        if not v or np.isnan(v):
            continue
        s = str(int(v))
        for p in {s, s[:-3] + " " + s[-3:] if len(s) > 3 else s}:
            for m in re.finditer(r"(?<!\d)" + re.escape(p) + r"(?!\d)", desc):
                out.append(desc[m.end():m.end() + 45])
    return " | ".join(out).lower()


def pay_unit(row, desc):
    unit = first_unit(str(row.salary_comment or "").lower())
    if not unit:
        unit = first_unit(words_after_salary(desc, [row.salary, row.salary_from, row.salary_to]))
    if not unit:
        low = min(v for v in (row.salary, row.salary_from, row.salary_to) if v and not np.isnan(v)) \
            if any(v and not np.isnan(v) for v in (row.salary, row.salary_from, row.salary_to)) else None
        if low and low < 100 and re.search(r"(?<!\d)%d\s?(тис|тыс|000|k\b)" % int(low), desc.lower()):
            unit = "thousands"
    return unit


def main():
    export = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_EXPORT
    d = pd.read_parquet(export / "vacancies_with_text.parquet", columns=["id", "description_text"])
    s = pd.read_csv(export / "vacancies.csv", encoding="utf-8-sig",
                    usecols=["id", "salary", "salary_from", "salary_to", "salary_comment"])
    for c in ["salary", "salary_from", "salary_to"]:
        s[c] = s[c].replace(0, np.nan)
    d = d.merge(s, on="id", how="left", validate="1:1")

    d["desc_hash"] = d["description_text"].map(fingerprint)
    d["desc_len"] = d["description_text"].fillna("").str.len()
    texts = d["description_text"].fillna("").str.replace(r"\s+", " ", regex=True)
    d["pay_unit"] = [pay_unit(r, t) for r, t in zip(d.itertuples(index=False), texts)]
    # plain re (not pandas' string methods): with Arrow strings, \b and \w in pandas
    # regexes may treat Cyrillic letters as non-word characters
    addr = re.compile(ADDRESS)
    d["desc_address"] = [int(bool(addr.search(t.lower()))) for t in texts.astype(object)]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    d[["id", "desc_hash", "desc_len", "pay_unit", "desc_address"]].to_csv(OUT, index=False)
    print(f"desc_address: {d.desc_address.mean():.1%} of vacancies name an address")
    print(f"{len(d):,} vacancies from {export.name}; {(d.desc_hash == '').sum():,} without a description")
    print("pay_unit:", d.pay_unit.replace("", "(not stated)").value_counts().to_dict())
    print(f"written: {OUT}")


if __name__ == "__main__":
    main()
