"""Revert Ivysaur → Bulbasaur via the TTMMO API for a given user."""
import sys, os, json, requests, urllib3

# Disable SSL warnings for ngrok
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Try multiple server URLs (same order as the app)
CANDIDATES = [
    "https://api.playfablewood.com/api",
    "https://unaggravated-dispersively-grayce.ngrok-free.dev/api",
    "http://100.65.103.71:3001/api",
]

def find_api():
    for url in CANDIDATES:
        try:
            r = requests.get(f"{url}/me", headers={"ngrok-skip-browser-warning": "true"},
                           timeout=5, verify=False)
            if r.status_code in (200, 401):
                print(f"Using server: {url}")
                return url
        except Exception as e:
            print(f"  {url}: {e}")
    print("No server reachable!")
    sys.exit(1)

API = find_api()
USERNAME = sys.argv[1] if len(sys.argv) > 1 else "akingofcrows"
PASSWORD = sys.argv[2] if len(sys.argv) > 2 else ""

if not PASSWORD:
    PASSWORD = input(f"Password for {USERNAME}: ")

# 1. Login
print(f"Logging in as {USERNAME}...")
r = requests.post(f"{API}/login", json={"username": USERNAME, "password": PASSWORD},
                  headers={"ngrok-skip-browser-warning": "true"}, verify=False)
if not r.ok:
    print(f"Login failed: {r.status_code} {r.text}")
    sys.exit(1)
token = r.json()["token"]
headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json",
           "ngrok-skip-browser-warning": "true"}
print("Logged in!")

# 2. Get all card instances
r = requests.get(f"{API}/me/cards", headers=headers, verify=False)
if not r.ok:
    print(f"Get cards failed: {r.status_code} {r.text}")
    sys.exit(1)
cards = r.json()
print(f"Found {len(cards)} card instances")

# 3. Find Ivysaur instances
ivys = [c for c in cards if c.get("cardId") == "card_ivysaur_1"]
print(f"Found {len(ivys)} Ivysaur instance(s)")

for ivy in ivys:
    inst_id = ivy.get("instanceId") or ivy.get("id")
    is_shiny = ivy.get("shiny") or ivy.get("isShiny")
    shiny_str = "shiny" if is_shiny else "regular"
    print(f"  Reverting instance {inst_id} ({shiny_str})...")
    r = requests.post(f"{API}/me/evolve", json={
        "cardId": "card_ivysaur_1",
        "toId": "card_bulbasaur_1",
        "instanceId": inst_id,
    }, headers=headers, verify=False)
    if r.ok:
        print(f"    ✓ Reverted to Bulbasaur")
    else:
        print(f"    ✗ Failed: {r.status_code} {r.text}")

print("Done!")
