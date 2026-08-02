"""Revert all Ivysaur instances back to Bulbasaur for a specific user."""
import json
import mysql.connector
import sys

USERNAME = sys.argv[1] if len(sys.argv) > 1 else "akingofcrows"

db = mysql.connector.connect(
    host="127.0.0.1", port=3306,
    user="fablewood_user", password="StrongStr0ngPass!",
    database="pokemon_triad")

cur = db.cursor()

# Find user
cur.execute("SELECT id FROM triad_users WHERE username = %s", (USERNAME,))
user = cur.fetchone()
if not user:
    print(f"User '{USERNAME}' not found!")
    db.close()
    sys.exit(1)
user_id = user[0]
print(f"User: {USERNAME} (id={user_id})")

# Revert all card instances: ivysaur → bulbasaur (both shiny and regular)
cur.execute("""
    SELECT id, card_id, is_shiny
    FROM triad_card_instances
    WHERE user_id = %s AND card_id = 'card_ivysaur_1'
""", (user_id,))
ivys = cur.fetchall()
print(f"Found {len(ivys)} Ivysaur instance(s)")

for inst in ivys:
    inst_id, card_id, is_shiny = inst
    shiny_str = "shiny" if is_shiny else "regular"
    cur.execute("""
        UPDATE triad_card_instances
        SET card_id = 'card_bulbasaur_1', level = 1, xp = 0,
            bonus_north = 0, bonus_south = 0, bonus_east = 0, bonus_west = 0
        WHERE id = %s
    """, (inst_id,))
    print(f"  Instance {inst_id} ({shiny_str}): Ivysaur → Bulbasaur (reset to Lv.1)")

# Fix decks that reference ivysaur
cur.execute("SELECT id, card_ids_json FROM triad_decks WHERE user_id = %s", (user_id,))
for row in cur.fetchall():
    card_ids = json.loads(row[1])
    if 'card_ivysaur_1' in card_ids:
        updated = ['card_bulbasaur_1' if cid == 'card_ivysaur_1' else cid for cid in card_ids]
        cur.execute("UPDATE triad_decks SET card_ids_json = %s WHERE id = %s",
                    (json.dumps(updated), row[0]))
        print(f"  Fixed deck {row[0]}")

db.commit()
print("Done! All Ivysaurs reverted to Bulbasaurs.")
db.close()
