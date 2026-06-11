#!/usr/bin/env python3
"""
ICT SMC EA — AI Signal Bridge V1.0
Runs alongside ICT_SMC_EA_V1.6 and provides trade predictions.

HOW IT WORKS:
  1. EA writes market state → ICT_SMC_AI_Request.txt
  2. This script reads the request and runs a prediction model
  3. This script writes prediction → ICT_SMC_AI_Signal.txt
  4. EA reads the signal and uses it as a score bonus / hard gate

SETUP:
  1. Find your MT5 Common Files folder:
       MT5 → File → Open Data Folder → then go up to:
       C:/Users/YOUR_NAME/AppData/Roaming/MetaQuotes/Terminal/Common/Files
  2. Set MT5_FILES_PATH below to that folder
  3. In EA settings: UseAIFilter = true
  4. Run this script: python ai_signal_bridge.py
  5. Leave it running while MT5 is open

SIGNAL FILE FORMAT written by this script:
  DIRECTION,CONFIDENCE,TIMESTAMP
  e.g.:  BUY,0.82,2024.01.15 10:30:00
         SELL,0.71,2024.01.15 10:30:00
         SKIP,0.0,2024.01.15 10:30:00

REQUEST FILE FORMAT written by EA:
  timestamp,symbol,direction,mss,bos,sweep,score,ote_pct,atr_pips,spread,hour,dow,session
  e.g.:  2024.01.15 10:30,XAUUSD,BUY,1,1,0,65,0.6850,12.5,0.3,10,1,LONDON
"""

import os
import time
from datetime import datetime

# ════════════════════════════════════════════════════════════════
# PATH — auto-detected from script location (no manual setup needed)
# Place this script in MT5 Common Files folder and it works automatically.
# ════════════════════════════════════════════════════════════════
MT5_FILES_PATH = os.path.dirname(os.path.abspath(__file__))

REQUEST_FILE = os.path.join(MT5_FILES_PATH, "ICT_SMC_AI_Request.txt")
SIGNAL_FILE  = os.path.join(MT5_FILES_PATH, "ICT_SMC_AI_Signal.txt")

# ════════════════════════════════════════════════════════════════
# PREDICTION MODEL
# Replace the body of predict() with your trained ML model.
#
# To train a real model:
#   1. Collect trade CSV logs from the EA (they are in MT5 Files folder)
#   2. Run train_model.py to build and save model.pkl
#   3. Load model here: model = joblib.load('model.pkl')
#   4. Return: model.predict_proba([feature_vector])[0]
# ════════════════════════════════════════════════════════════════
def predict(features: dict) -> tuple:
    """
    Returns (direction, confidence) tuple.
    direction : 'BUY', 'SELL', or 'SKIP'
    confidence: 0.0 – 1.0

    Current implementation: rule-based scoring.
    Replace with trained ML model after collecting backtest history.
    """
    direction = features.get('direction', 'BUY')
    score     = float(features.get('score', 50))
    mss       = int(features.get('mss', 0))
    bos       = int(features.get('bos', 0))
    sweep     = int(features.get('sweep', 0))
    ote_pct   = float(features.get('ote_pct', 0.70))
    hour      = int(features.get('hour', 12))
    session   = features.get('session', 'OTHER')

    # ── Base confidence from EA score ─────────────────────────
    # EA score 50 → 0.60 confidence, score 100 → 0.90 confidence
    confidence = score / 100.0 * 0.60 + 0.30

    # ── ICT structure bonuses ──────────────────────────────────
    if mss:   confidence += 0.05   # MSS confirmed
    if bos:   confidence += 0.05   # BOS confirmed
    if sweep: confidence += 0.03   # Liquidity sweep done

    # ── Session quality ────────────────────────────────────────
    if session == 'OVERLAP':  confidence += 0.06   # London+NY overlap: best hours
    elif session == 'LONDON': confidence += 0.03
    elif session == 'NEWYORK': confidence += 0.03

    # ── OTE sweet spot bonus (near 70.5%) ─────────────────────
    if 0.67 <= ote_pct <= 0.73:
        confidence += 0.04
    elif 0.60 <= ote_pct <= 0.80:
        confidence += 0.02

    # ── Low-quality hour penalty ───────────────────────────────
    if hour in (0, 1, 2, 3, 22, 23):
        confidence -= 0.08   # dead hours

    # ── Clamp ─────────────────────────────────────────────────
    confidence = max(0.0, min(1.0, confidence))

    if confidence < 0.55:
        return 'SKIP', confidence
    return direction, confidence


# ════════════════════════════════════════════════════════════════
# ENGINE — do not modify below unless you know what you're doing
# ════════════════════════════════════════════════════════════════
def parse_request(line: str) -> dict:
    keys = ['timestamp', 'symbol', 'direction', 'mss', 'bos', 'sweep',
            'score', 'ote_pct', 'atr_pips', 'spread', 'hour', 'dow', 'session']
    parts = [p.strip() for p in line.strip().split(',')]
    if len(parts) < len(keys):
        return {}
    return dict(zip(keys, parts))


def write_signal(direction: str, confidence: float):
    ts = datetime.now().strftime("%Y.%m.%d %H:%M:%S")
    try:
        with open(SIGNAL_FILE, 'w') as f:
            f.write(f"{direction},{confidence:.4f},{ts}\n")
    except Exception as e:
        print(f"  [ERROR] Cannot write signal file: {e}")


def main():
    print("=" * 60)
    print("  ICT SMC EA — AI Signal Bridge V1.0")
    print("  For use with ICT_SMC_EA_V1.6")
    print(f"  Request : {REQUEST_FILE}")
    print(f"  Signal  : {SIGNAL_FILE}")
    print("=" * 60)

    if not os.path.isdir(MT5_FILES_PATH):
        print(f"\n  [ERROR] MT5 Files folder not found:")
        print(f"  {MT5_FILES_PATH}")
        print("\n  Please edit MT5_FILES_PATH in this script.")
        print("  Find it in MT5: File → Open Data Folder → Common → Files")
        return

    print("\n  [READY] Watching for trade requests... (Ctrl+C to stop)\n")
    print(f"  {'Time':8s}  {'Status':8s}  {'Direction':6s}  {'Conf':6s}  Request")
    print(f"  {'-'*8}  {'-'*8}  {'-'*6}  {'-'*6}  {'-'*40}")

    last_line = ""
    last_mtime = 0
    idle_ticks = 0

    try:
        while True:
            time.sleep(0.5)
            idle_ticks += 1

            if not os.path.exists(REQUEST_FILE):
                if idle_ticks % 30 == 0:
                    print(f"  [{datetime.now().strftime('%H:%M:%S')}]  waiting...  (no request file yet)")
                continue

            mtime = os.path.getmtime(REQUEST_FILE)
            if mtime == last_mtime:
                continue
            last_mtime = mtime

            try:
                with open(REQUEST_FILE, 'r') as f:
                    line = f.read().strip()
            except Exception:
                continue

            if not line or line == last_line:
                continue

            last_line = line
            idle_ticks = 0

            features = parse_request(line)
            if not features:
                print(f"  [{datetime.now().strftime('%H:%M:%S')}]  [WARN] Could not parse request: {line[:50]}")
                continue

            direction, confidence = predict(features)
            write_signal(direction, confidence)

            status  = "SIGNAL" if direction != 'SKIP' else "SKIP  "
            preview = f"{features.get('symbol','?')} {features.get('session','?')} score={features.get('score','?')} ote={float(features.get('ote_pct',0)):.2f}"
            print(f"  [{datetime.now().strftime('%H:%M:%S')}]  {status}  {direction:6s}  {confidence:.3f}  {preview}")

    except KeyboardInterrupt:
        print("\n\n  [STOPPED] AI Signal Bridge stopped.")
        print("  The EA will continue with UseAIFilter but no signal (AIRequireSignal=false = safe).")


if __name__ == "__main__":
    main()
