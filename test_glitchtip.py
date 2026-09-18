#!/usr/bin/env python3
"""
GlitchTip / Sentry SDK Verification Script
Sends a test message and a sample handled exception to GlitchTip to verify event ingestion.

Usage:
    python test_glitchtip.py
    python test_glitchtip.py --dsn "https://<key>@glitchtip.adisoc.com/<project_id>"
"""

import argparse
import os
import sys

DEFAULT_DSN = "https://c8cdeed822074c16b7500a3ca5e443ed@glitchtip.adisoc.com/1"


def test_glitchtip(dsn: str):
    try:
        import sentry_sdk
    except ImportError:
        print("[!] sentry-sdk not found. Please install it with:")
        print("    pip install sentry-sdk")
        sys.exit(1)

    print(f"[*] Initializing Sentry SDK with DSN: {dsn}")
    sentry_sdk.init(
        dsn=dsn,
        traces_sample_rate=1.0,
        environment="test",
        release="test-script@1.0.0",
    )

    # 1. Capture Informational Message
    print("[*] Sending test informational message...")
    msg_id = sentry_sdk.capture_message("Hello from GlitchTip verification test script!")
    print(f"[+] Message sent successfully! Event ID: {msg_id}")

    # 2. Capture Sample Handled Exception
    print("[*] Triggering and capturing a test exception...")
    try:
        # Deliberate ZeroDivisionError for test reporting
        result = 100 / 0
    except ZeroDivisionError as err:
        exc_id = sentry_sdk.capture_exception(err)
        print(f"[+] Exception captured successfully! Event ID: {exc_id}")

    # 3. Flush outgoing event queue
    print("[*] Flushing events to GlitchTip server...")
    sentry_sdk.flush(timeout=5)
    print("\n[SUCCESS] All test events successfully transmitted to GlitchTip!")
    print("    Check your GlitchTip dashboard at: https://glitchtip.adisoc.com")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Test GlitchTip event ingestion via Sentry SDK")
    parser.add_argument(
        "--dsn",
        default=os.environ.get("GLITCHTIP_DSN", DEFAULT_DSN),
        help="GlitchTip / Sentry DSN endpoint (default: %(default)s)",
    )
    args = parser.parse_args()

    test_glitchtip(args.dsn)
