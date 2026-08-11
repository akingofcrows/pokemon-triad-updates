import mysql.connector, os
db = mysql.connector.connect(
    host="127.0.0.1", port=int(os.environ.get("DB_PORT", 3307)),
    user="fablewood_user", password="StrongStr0ngPass!",
    database="pokemon_triad")
cur = db.cursor()

# Add the column if it doesn't exist
try:
    cur.execute("ALTER TABLE triad_cards ADD COLUMN is_reverse_holo TINYINT DEFAULT 0")
    print("Added is_reverse_holo column")
except Exception as e:
    print(f"Column might already exist: {e}")

# Show all Lorelai (trainer_lorelei) cards for user 1
cur.execute("SELECT id, card_id, level, is_shiny, is_reverse_holo FROM triad_cards WHERE user_id=1 AND card_id='trainer_lorelei'")
rows = cur.fetchall()
print(f"\nLorelai cards for user 1:")
for r in rows:
    print(f"  instance_id={r[0]}  card={r[1]}  Lv.{r[2]}  shiny={r[3]}  rev_holo={r[4]}")

# Set the first level 1 non-shiny Lorelai to reverse holo
cur.execute("UPDATE triad_cards SET is_reverse_holo=1 WHERE user_id=1 AND card_id='trainer_lorelei' AND level=1 AND is_shiny=0 LIMIT 1")
db.commit()
print(f"\nUpdated {cur.rowcount} rows to reverse holo")
db.close()
