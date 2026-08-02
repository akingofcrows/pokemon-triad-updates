"""Quick check: what cards does a user have?"""
import sys, requests, urllib3, json
urllib3.disable_warnings()

API = "https://api.playfablewood.com/api"
USERNAME = sys.argv[1] if len(sys.argv) > 1 else "akingofcrows"
PASSWORD = sys.argv[2] if len(sys.argv) > 2 else "Midnight1"

# Login
r = requests.post(f"{API}/login", json={"username": USERNAME, "password": PASSWORD},
                  headers={"ngrok-skip-browser-warning": "true"}, verify=False)
if not r.ok:
    print(f"Login failed: {r.status_code}")
    sys.exit(1)
token = r.json()["token"]
h = {"Authorization": f"Bearer {token}", "Content-Type": "application/json",
     "ngrok-skip-browser-warning": "true"}

# Filter argument
filter_str = (sys.argv[3] if len(sys.argv) > 3 else "").lower()

# Get card instances
r = requests.get(f"{API}/me/cards", headers=h, verify=False)
cards = r.json()
print(f"Total instances: {len(cards)}")
for c in cards:
    cid = c.get("cardId", "")
    if filter_str and filter_str not in cid.lower():
        continue
    shiny = "⭐" if c.get("shiny") else "  "
    lv = c.get("level", "?")
    print(f"  [{shiny}] {cid} Lv.{lv}  (inst={c.get('instanceId')})")

# Also check ownedCardIds from /me for filtered cards
r = requests.get(f"{API}/me", headers=h, verify=False)
me = r.json()
owned = me.get("ownedCardIds", [])
matches = [cid for cid in owned if filter_str in cid.lower()] if filter_str else []
if matches:
    print(f"\nownedCardIds matches: {matches}")
