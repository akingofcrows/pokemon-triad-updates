#!/usr/bin/env python3
"""Admin CLI tool: grant gifts to players."""
import sys, os, argparse, json, requests

API = os.environ.get("API_URL", "https://unaggravated-dispersively-grayce.ngrok-free.dev/api")
KEY = os.environ.get("ADMIN_KEY", "triad-admin-2024")

def grant(username, gift_type="item", item_id="", quantity=1, message="",
          bonus_north=0, bonus_south=0, bonus_east=0, bonus_west=0, shiny=False):
    r = requests.post(f"{API}/admin/gift", json={
        "username": username, "giftType": gift_type,
        "itemId": item_id, "quantity": quantity, "message": message,
        "bonusNorth": bonus_north, "bonusSouth": bonus_south,
        "bonusEast": bonus_east, "bonusWest": bonus_west,
        "shiny": shiny,
    }, headers={"X-Admin-Key": KEY, "Content-Type": "application/json"})
    print(r.json() if r.ok else f"Error {r.status_code}: {r.text}")

if __name__ == "__main__":
    p = argparse.ArgumentParser(description="Grant gifts to players")
    p.add_argument("username")
    p.add_argument("--type", default="item")
    p.add_argument("--item", default="")
    p.add_argument("--qty", type=int, default=1)
    p.add_argument("--msg", default="A gift from the admin!")
    p.add_argument("--bn", type=int, default=0, help="bonus north")
    p.add_argument("--bs", type=int, default=0, help="bonus south")
    p.add_argument("--be", type=int, default=0, help="bonus east")
    p.add_argument("--bw", type=int, default=0, help="bonus west")
    p.add_argument("--shiny", action="store_true", help="mark as shiny")
    args = p.parse_args()
    grant(args.username, args.type, args.item, args.qty, args.msg,
          args.bn, args.bs, args.be, args.bw, args.shiny)
