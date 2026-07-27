#!/usr/bin/env python3
"""Migrate user 'akingofcrows' from cardmmo → pokemon_triad (new character schema)."""
import json
import mysql.connector

OLD = {"host": "127.0.0.1", "port": 3306, "user": "fablewood_user", "password": "StrongStr0ngPass!", "database": "cardmmo"}
NEW = {"host": "127.0.0.1", "port": 3306, "user": "fablewood_user", "password": "StrongStr0ngPass!", "database": "pokemon_triad"}

old = mysql.connector.connect(**OLD)
new = mysql.connector.connect(**NEW)

oc = old.cursor(dictionary=True)
nc = new.cursor()

# 1. Copy user (no profile_json anymore)
oc.execute("SELECT * FROM triad_users WHERE username = 'akingofcrows'")
user = oc.fetchone()
if not user:
    print("User 'akingofcrows' not found in cardmmo!")
    exit(1)

nc.execute("SELECT id FROM triad_users WHERE username = 'akingofcrows'")
existing = nc.fetchone()

if existing:
    new_user_id = existing[0]
    print(f"User already in pokemon_triad (id={new_user_id})")
else:
    nc.execute(
        "INSERT INTO triad_users (username, password_hash, token, created_at) VALUES (%s,%s,%s,%s)",
        (user['username'], user['password_hash'], user['token'], user['created_at'])
    )
    new_user_id = nc.lastrowid
    print(f"Copied user (old id={user['id']} → new id={new_user_id})")

old_user_id = user['id']

# 2. Migrate profile_json → triad_characters
if user.get('profile_json'):
    try:
        profile = json.loads(user['profile_json'])
        char_fields = {
            "trainer_name": profile.get("trainerName"),
            "gender": profile.get("gender"),
            "skin_tone": profile.get("skinTone"),
            "hair_path": profile.get("hairPath"),
            "top_path": profile.get("topPath"),
            "bottom_path": profile.get("bottomPath"),
            "hat_path": profile.get("hatPath"),
            "friend_code": profile.get("friendCode"),
            "location": profile.get("location", "Pallet Town"),
            "money": profile.get("money", 0),
            "wins": profile.get("wins", 0),
            "losses": profile.get("losses", 0),
            "draws": profile.get("draws", 0),
        }
        char_fields = {k: v for k, v in char_fields.items() if v is not None}
        cols = ", ".join(char_fields.keys())
        placeholders = ", ".join(["%s"] * len(char_fields))
        nc.execute(
            f"INSERT INTO triad_characters (user_id, {cols}) VALUES (%s, {placeholders}) "
            "ON DUPLICATE KEY UPDATE " + ", ".join(f"{k}=VALUES({k})" for k in char_fields),
            (new_user_id, *char_fields.values())
        )
        print(f"Migrated character data: {list(char_fields.keys())}")

        # Migrate favorites from old profile_json
        fav_ids = profile.get("favoriteCardIds") or []
        if fav_ids:
            for i, fid in enumerate(fav_ids[:3]):
                nc.execute(
                    "INSERT IGNORE INTO triad_favorites (user_id, card_id, sort_order) VALUES (%s, %s, %s)",
                    (new_user_id, fid, i)
                )
            print(f"Migrated {len(fav_ids[:3])} favorites")

        # Migrate decks from old profile_json
        old_decks = profile.get("decks") or []
        if old_decks:
            for d in old_decks:
                did = d.get("id", "")
                dname = d.get("name", "Deck")
                card_ids = d.get("cardIds", [])
                is_default = d.get("isDefault", False)
                if not did:
                    continue
                nc.execute(
                    "INSERT INTO triad_decks (id, user_id, name, card_ids_json, active) "
                    "VALUES (%s, %s, %s, %s, %s) "
                    "ON DUPLICATE KEY UPDATE name=VALUES(name), card_ids_json=VALUES(card_ids_json), active=VALUES(active)",
                    (did, new_user_id, dname, json.dumps(card_ids), int(is_default))
                )
            print(f"Migrated {len(old_decks)} decks from profile_json")
    except json.JSONDecodeError:
        print("Skipped profile_json — invalid JSON")
else:
    print("No profile_json found, creating blank character")
    nc.execute("INSERT IGNORE INTO triad_characters (user_id) VALUES (%s)", (new_user_id,))

# 3. Copy cards
oc.execute("SELECT * FROM triad_cards WHERE user_id = %s", (old_user_id,))
cards = oc.fetchall()
print(f"Found {len(cards)} cards to migrate")
for c in cards:
    nc.execute("SELECT id FROM triad_cards WHERE user_id = %s AND card_id = %s", (new_user_id, c['card_id']))
    if nc.fetchone():
        continue
    nc.execute(
        "INSERT INTO triad_cards (user_id, card_id, xp, level, is_shiny, source) VALUES (%s,%s,%s,%s,%s,%s)",
        (new_user_id, c['card_id'], c.get('xp', 0), c.get('level', 1), c.get('is_shiny', 0), c.get('source'))
    )

# 4. Copy decks
oc.execute("SELECT * FROM triad_decks WHERE user_id = %s", (old_user_id,))
decks = oc.fetchall()
print(f"Found {len(decks)} decks to migrate")
for d in decks:
    nc.execute("SELECT id FROM triad_decks WHERE id = %s", (d['id'],))
    if nc.fetchone():
        continue
    nc.execute(
        "INSERT INTO triad_decks (id, user_id, name, card_ids_json, active) VALUES (%s,%s,%s,%s,%s)",
        (d['id'], new_user_id, d['name'], d['card_ids_json'], d.get('active', 0))
    )

new.commit()
print(f"Done! {len(cards)} cards, {len(decks)} decks migrated.")
oc.close(); nc.close(); old.close(); new.close()
