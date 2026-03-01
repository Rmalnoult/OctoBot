#!/usr/bin/env python3
"""
Signal Bridge: signal-aggregator SQLite → OctoBot webhook.

Polls signal-aggregator's score_history every 5 minutes.
Score ≥70 → POST BUY to OctoBot webhook.
Score ≤30 → POST SELL.
Only sends on state change to avoid duplicate signals.
"""
import json
import logging
import os
import sqlite3
import sys
import time
from pathlib import Path

import requests

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
SIGNAL_DB = os.getenv(
    "SIGNAL_DB",
    str(Path.home() / "crypto-bots/signal-aggregator/data/signal_aggregator.db"),
)
WEBHOOK_URL = os.getenv("WEBHOOK_URL", "http://127.0.0.1:9000/webhook/trading_view")
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "300"))  # 5 minutes
BUY_THRESHOLD = float(os.getenv("BUY_THRESHOLD", "70"))
SELL_THRESHOLD = float(os.getenv("SELL_THRESHOLD", "30"))

# signal-aggregator uses USDC pairs, OctoBot uses USDT
PAIR_MAP = {
    "BTCUSDC": "BTCUSDT",
    "ETHUSDC": "ETHUSDT",
    "SOLUSDC": "SOLUSDT",
    "BNBUSDC": "BNBUSDT",
    "XRPUSDC": "XRPUSDT",
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("signal-bridge")


def get_latest_scores(db_path: str) -> dict[str, tuple[float, str]]:
    """Return {pair: (score, signal)} for the most recent cycle."""
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    conn.execute("PRAGMA query_only = ON")
    try:
        rows = conn.execute(
            """
            SELECT pair, total_score, signal
            FROM score_history
            WHERE timestamp = (SELECT MAX(timestamp) FROM score_history)
            """
        ).fetchall()
        return {row[0]: (row[1], row[2]) for row in rows}
    finally:
        conn.close()


def send_signal(symbol: str, signal: str) -> bool:
    """POST a TradingView-style signal to OctoBot webhook."""
    body = f"EXCHANGE=binance\nSYMBOL={symbol}\nSIGNAL={signal}\nVOLUME=20%\n"
    try:
        resp = requests.post(
            WEBHOOK_URL,
            data=body,
            headers={"Content-Type": "text/plain"},
            timeout=10,
        )
        if resp.status_code == 200:
            log.info("Sent %s %s → %s", signal.upper(), symbol, resp.status_code)
            return True
        log.warning(
            "Webhook returned %s for %s %s: %s",
            resp.status_code,
            signal,
            symbol,
            resp.text[:200],
        )
        return False
    except requests.RequestException as e:
        log.error("Webhook request failed for %s %s: %s", signal, symbol, e)
        return False


def main():
    log.info(
        "Starting signal bridge: DB=%s  webhook=%s  interval=%ds",
        SIGNAL_DB,
        WEBHOOK_URL,
        POLL_INTERVAL,
    )
    log.info("Thresholds: BUY≥%.0f  SELL≤%.0f", BUY_THRESHOLD, SELL_THRESHOLD)

    # Track last signal sent per pair to avoid duplicates
    last_signal: dict[str, str] = {}  # pair -> "buy" | "sell" | "neutral"

    while True:
        try:
            scores = get_latest_scores(SIGNAL_DB)
            if not scores:
                log.warning("No scores found in %s", SIGNAL_DB)
            else:
                for pair, (score, _sig) in scores.items():
                    symbol = PAIR_MAP.get(pair)
                    if not symbol:
                        continue

                    if score >= BUY_THRESHOLD:
                        desired = "buy"
                    elif score <= SELL_THRESHOLD:
                        desired = "sell"
                    else:
                        desired = "neutral"

                    prev = last_signal.get(pair, "neutral")
                    if desired != prev and desired != "neutral":
                        if send_signal(symbol, desired):
                            last_signal[pair] = desired
                    elif desired == "neutral" and prev != "neutral":
                        # Score returned to neutral zone — reset state
                        last_signal[pair] = "neutral"
                        log.info(
                            "%s score=%.1f → neutral (was %s), no signal sent",
                            pair,
                            score,
                            prev,
                        )
                    else:
                        log.debug(
                            "%s score=%.1f → %s (unchanged)", pair, score, desired
                        )

        except Exception:
            log.exception("Error in poll cycle")

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
