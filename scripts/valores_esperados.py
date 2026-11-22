#!/usr/bin/env python3
"""Reproduce en Python los datos sintéticos de db/01_schema_y_datos.sql para un
portafolio y calcula los valores esperados, sin necesidad de SQL Server.

Sirve para:
  * tener cifras de referencia contra las que contrastar la base y la API;
  * mostrar cuánto se desvía el procedimiento original (dbo.usp_GetPerformance).

Uso: python3 scripts/valores_esperados.py [portafolio] [fecha_corte]
     python3 scripts/valores_esperados.py 7 2023-08-15
"""
import hashlib
import math
import sys
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP

Q4 = Decimal("0.0001")
Q6 = Decimal("0.000001")


def h(prefix: str, p: int, i: int, d: date) -> int:
    # HASHBYTES('MD5', CONCAT(prefix, @p, '|', i, '|', d)) -> BINARY(4) -> BIGINT
    s = f"{prefix}{p}|{i}|{d.isoformat()}".encode("ascii")
    return int.from_bytes(hashlib.md5(s).digest()[:4], "big")


def business_days():
    d = date(2015, 1, 1)
    for _ in range(3653):
        if (d - date(1900, 1, 1)).days % 7 < 5:
            yield d
        d += timedelta(days=1)


def generate(p: int):
    """Devuelve {fecha: [(mvb, flow, pnl, mve, r), ...]} para el portafolio p."""
    out = {}
    for d in business_days():
        rows = []
        for i in range(1, 101):
            mvb = Decimal(100000 + h("m", p, i, d) % 900000)
            r = (float(h("r", p, i, d) % 2001) - 1000) / 50000 + 0.0002
            h3 = h("f", p, i, d)
            flow = Decimal(h3 % 20001 - 10000) if h3 % 100 == 0 else Decimal(0)
            # decimal * float -> float en SQL Server; al insertar se redondea a 4 decimales
            pnl = Decimal(repr(float(mvb) * r)).quantize(Q4, ROUND_HALF_UP)
            mve = Decimal(repr(float(mvb) * (1 + r) + float(flow))).quantize(Q4, ROUND_HALF_UP)
            rows.append((mvb, flow, pnl, mve, r))
        out[d] = rows
    return out


def compound(returns):
    acc = 1.0
    for r in returns:
        acc *= 1 + r
    return acc - 1


def main():
    p = int(sys.argv[1]) if len(sys.argv) > 1 else 7
    as_of = date.fromisoformat(sys.argv[2]) if len(sys.argv) > 2 else date(2023, 8, 15)
    data = generate(p)

    daily = {}  # fecha -> (retorno del portafolio, pnl del día)
    for d, rows in data.items():
        mvb = sum(r[0] for r in rows)
        pnl = sum(r[2] for r in rows)
        daily[d] = (float(pnl) / float(mvb), pnl)

    def rng(f, t):
        days = [d for d in daily if f <= d <= t]
        return compound(daily[d][0] for d in days), sum(daily[d][1] for d in days), len(days)

    print(f"Portafolio {p}, corte {as_of}")
    q_start = date(as_of.year, (as_of.month - 1) // 3 * 3 + 1, 1)
    for name, f in [("MTD", as_of.replace(day=1)), ("QTD", q_start),
                    ("YTD", date(as_of.year, 1, 1)), ("ITD", date(2015, 1, 1))]:
        ret, pnl, n = rng(f, as_of)
        print(f"  {name}: desde {f} dias={n:5d} retorno={ret*100:+.6f}% pnl={pnl:,.4f}")

    year = as_of.year
    print(f"\nAño {year}: correcto vs procedimiento original")
    print("  Mes | Retorno correcto | RetornoMes original (suma) | PnL")
    for m in range(1, 13):
        days = [d for d in daily if d.year == year and d.month == m]
        correct = compound(daily[d][0] for d in days)
        # original: SUM de retornos diarios, cada uno como DECIMAL(38,6)
        legacy = 0.0
        for d in days:
            rows = data[d]
            s_pnl = sum(r[2] for r in rows)
            s_mvb = sum(r[0] for r in rows)
            legacy += float((s_pnl / s_mvb).quantize(Q6, ROUND_HALF_UP))
        pnl = sum(daily[d][1] for d in days)
        print(f"  {m:3d} | {correct*100:+15.6f}% | {legacy*100:+25.6f}% | {pnl:,.4f}")

    ytd_ok, ytd_pnl, n = rng(date(year, 1, 1), date(year, 12, 31))
    legacy_ytd = sum(r[4] for d, rows in data.items() if d.year == year for r in rows)
    print(f"\n  RetornoYTD correcto:  {ytd_ok*100:+.6f}%  ({n} días)")
    print(f"  RetornoYTD original:  {legacy_ytd*100:+.6f}%  (SUM(DailyReturn) de {n*100} filas)")
    print(f"  PnLYTD (igual en ambos): {ytd_pnl:,.4f}")

    bad = sum(1 for rows in data.values() for r in rows if abs(r[2] - (r[3] - r[0] - r[1])) > Q4)
    print(f"\nFilas donde PnL != MVE - MVB - NetFlows (tolerancia 0,0001): {bad}")


if __name__ == "__main__":
    main()
