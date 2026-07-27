#!/usr/bin/env python3
"""Admin CLI tool: grant gifts to players."""
import sys, os, argparse, requests

API = os.environ.get("API_URL", "http://127.0.0.1:3001/api")
KEY = os.environ.get("ADMIN_KEY", "triad-admin-2024")

def grant(username, gift_type="item", item_id="", quantity=1, message=""):
    r = requests.post(f"{API}/admin/gift", json={
        "username": username, "giftType": gift_type,
        "itemId": item_id, "quantity": quantity, "message": message,
    }, headers={"X-Admin-Key": KEY, "Content-Type": "application/json"})
    print(r.json() if r.ok else f"Error {r.status_code}: {r.text}")

if __name__ == "__main__":
    p = argparse.ArgumentParser(description="Grant gifts to players")
    p.add_argument("username")
    p.add_argument("--type", default="item")
    p.add_argument("--item", default="")
    p.add_argument("--qty", type=int, default=1)
    p.add_argument("--msg", default="A gift from the admin!")
    args = p.parse_args()
    grant(args.username, args.type, args.item, args.qty, args.msg)
