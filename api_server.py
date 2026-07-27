"""TTMMO API Server — Flask + MySQL backend for Pokemon Triple Triad."""
import hashlib
import json
import os
import secrets

from flask import Flask, jsonify, request, send_from_directory
import mysql.connector

app = Flask(__name__)

# ── Database config ──────────────────────────────────────────────────────
# Connects to Linux MySQL via SSH tunnel on port 3307
DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "127.0.0.1"),
    "port": int(os.environ.get("DB_PORT", 3307)),
    "user": os.environ.get("DB_USER", "fablewood_user"),
    "password": os.environ.get("DB_PASS", "StrongStr0ngPass!"),
    "database": os.environ.get("DB_NAME", "pokemon_triad"),
}


def get_db():
    return mysql.connector.connect(**DB_CONFIG)


def init_db():
    """Create triad-prefixed tables inside the pokemon_triad database."""
    db = get_db()
    cur = db.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS triad_users (
            id INT AUTO_INCREMENT PRIMARY KEY,
            username VARCHAR(64) UNIQUE NOT NULL,
            password_hash VARCHAR(128) NOT NULL,
            token VARCHAR(128) UNIQUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS triad_characters (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL UNIQUE,
            trainer_name VARCHAR(64) UNIQUE,
            gender VARCHAR(16),
            skin_tone VARCHAR(32),
            hair_path VARCHAR(256),
            top_path VARCHAR(256),
            bottom_path VARCHAR(256),
            hat_path VARCHAR(256),
            friend_code VARCHAR(16) UNIQUE,
            location VARCHAR(128) DEFAULT 'Pallet Town',
            money INT DEFAULT 0,
            wins INT DEFAULT 0,
            losses INT DEFAULT 0,
            draws INT DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES triad_users(id)
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS triad_cards (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            card_id VARCHAR(64) NOT NULL,
            xp INT DEFAULT 0,
            level INT DEFAULT 1,
            bonus_north INT DEFAULT 0,
            bonus_south INT DEFAULT 0,
            bonus_east INT DEFAULT 0,
            bonus_west INT DEFAULT 0,
            is_shiny TINYINT DEFAULT 0,
            source VARCHAR(64) DEFAULT NULL,
            FOREIGN KEY (user_id) REFERENCES triad_users(id),
            UNIQUE KEY user_card (user_id, card_id)
        )
    """)
    # Migration: add columns if table existed before
    for col, coldef in [
        ("is_shiny", "TINYINT DEFAULT 0"),
        ("source", "VARCHAR(64) DEFAULT NULL"),
        ("bonus_north", "INT DEFAULT 0"),
        ("bonus_south", "INT DEFAULT 0"),
        ("bonus_east", "INT DEFAULT 0"),
        ("bonus_west", "INT DEFAULT 0"),
    ]:
        try:
            cur.execute(f"ALTER TABLE triad_cards ADD COLUMN {col} {coldef}")
        except:
            pass
    cur.execute("""
        CREATE TABLE IF NOT EXISTS triad_favorites (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            card_id VARCHAR(64) NOT NULL,
            sort_order INT DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES triad_users(id),
            UNIQUE KEY user_fav (user_id, card_id)
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS triad_decks (
            id VARCHAR(64) PRIMARY KEY,
            user_id INT NOT NULL,
            name VARCHAR(128) NOT NULL,
            card_ids_json TEXT,
            active TINYINT DEFAULT 0,
            FOREIGN KEY (user_id) REFERENCES triad_users(id)
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS triad_chat (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            sender_name VARCHAR(64) NOT NULL,
            message TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES triad_users(id)
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS triad_gifts (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            from_username VARCHAR(64),
            gift_type VARCHAR(32) NOT NULL DEFAULT 'item',
            item_id VARCHAR(64),
            quantity INT DEFAULT 1,
            message VARCHAR(512),
            bonus_north INT DEFAULT 0,
            bonus_south INT DEFAULT 0,
            bonus_east INT DEFAULT 0,
            bonus_west INT DEFAULT 0,
            is_shiny TINYINT DEFAULT 0,
            claimed TINYINT DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES triad_users(id)
        )
    """)
    # Drop deprecated profile_json column if it exists
    try:
        cur.execute("ALTER TABLE triad_users DROP COLUMN profile_json")
    except:
        pass
    db.commit()
    cur.close()
    db.close()


def _get_character(user_id, db):
    """Load the character row, or return an empty dict."""
    cur = db.cursor(dictionary=True)
    cur.execute("SELECT * FROM triad_characters WHERE user_id = %s", (user_id,))
    row = cur.fetchone()
    cur.close()
    if not row:
        return {}
    # Map snake_case DB columns → camelCase for the rest of the code
    return {
        "trainerName": row.get("trainer_name"),
        "gender": row.get("gender"),
        "skinTone": row.get("skin_tone"),
        "hairPath": row.get("hair_path"),
        "topPath": row.get("top_path"),
        "bottomPath": row.get("bottom_path"),
        "hatPath": row.get("hat_path"),
        "friendCode": row.get("friend_code"),
        "location": row.get("location"),
        "money": row.get("money"),
        "wins": row.get("wins"),
        "losses": row.get("losses"),
        "draws": row.get("draws"),
    }

def _ensure_character(user_id, db):
    """Create a default character row if one doesn't exist, return the dict."""
    c = _get_character(user_id, db)
    if not c:
        cur = db.cursor()
        cur.execute("INSERT INTO triad_characters (user_id, location) VALUES (%s, 'Pallet Town')", (user_id,))
        db.commit()
        cur.close()
        return {"location": "Pallet Town"}
    return c

def _save_character(user_id, fields, db):
    """Persist character fields dict."""
    if not fields:
        return
    cur = db.cursor()
    cols = []
    vals = []
    for k, v in fields.items():
        col = _char_col(k)
        if col:
            cols.append(f"{col} = %s")
            vals.append(v)
    if cols:
        vals.append(user_id)
        cur.execute(f"UPDATE triad_characters SET {', '.join(cols)} WHERE user_id = %s", vals)
        db.commit()
    cur.close()

def _char_col(key):
    """Map JSON camelCase keys to database snake_case columns."""
    return {
        "trainerName": "trainer_name", "gender": "gender", "skinTone": "skin_tone",
        "hairPath": "hair_path", "topPath": "top_path", "bottomPath": "bottom_path",
        "hatPath": "hat_path", "friendCode": "friend_code", "location": "location",
        "money": "money", "wins": "wins", "losses": "losses", "draws": "draws",
    }.get(key)


# ── Auth helpers ─────────────────────────────────────────────────────────
def _hash(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()


def _require_auth():
    token = request.headers.get("Authorization", "").replace("Bearer ", "")
    if not token:
        return None
    db = get_db()
    cur = db.cursor(dictionary=True)
    cur.execute("SELECT id, username FROM triad_users WHERE token = %s", (token,))
    user = cur.fetchone()
    cur.close()
    db.close()
    return user


# ── Routes ───────────────────────────────────────────────────────────────
@app.route("/api/register", methods=["POST"])
def register():
    data = request.get_json()
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""
    if not username or not password:
        return jsonify({"error": "Username and password required"}), 400
    if len(username) < 3:
        return jsonify({"error": "Username must be at least 3 characters"}), 400

    db = get_db()
    cur = db.cursor(dictionary=True)
    cur.execute("SELECT id FROM triad_users WHERE username = %s", (username,))
    if cur.fetchone():
        cur.close()
        db.close()
        return jsonify({"error": "Username already taken"}), 409

    token = secrets.token_hex(32)
    cur.execute(
        "INSERT INTO triad_users (username, password_hash, token) VALUES (%s, %s, %s)",
        (username, _hash(password), token),
    )
    db.commit()
    cur.close()
    db.close()
    return jsonify({"token": token, "username": username})


@app.route("/api/login", methods=["POST"])
def login():
    data = request.get_json()
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""

    db = get_db()
    cur = db.cursor(dictionary=True)
    cur.execute(
        "SELECT id, token FROM triad_users WHERE username = %s AND password_hash = %s",
        (username, _hash(password)),
    )
    user = cur.fetchone()
    if not user:
        cur.close()
        db.close()
        return jsonify({"error": "Invalid username or password"}), 401

    if not user["token"]:
        user["token"] = secrets.token_hex(32)
        cur.execute("UPDATE triad_users SET token = %s WHERE id = %s", (user["token"], user["id"]))
        db.commit()

    cur.close()
    db.close()
    return jsonify({"token": user["token"], "username": username})


@app.route("/api/me", methods=["GET"])
def get_me():
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    db = get_db()
    cur = db.cursor(dictionary=True)

    # Owned card ids
    cur.execute("SELECT card_id FROM triad_cards WHERE user_id = %s", (user["id"],))
    owned_card_ids = [r["card_id"] for r in cur.fetchall()]

    # Character data
    char = _ensure_character(user["id"], db)
    friend_code = char.get("friendCode")
    if not friend_code:
        friend_code = _generate_friend_code(db)
        _save_character(user["id"], {"friendCode": friend_code}, db)

    # User row for username / joined_at
    cur.execute("SELECT username, created_at FROM triad_users WHERE id = %s", (user["id"],))
    row = cur.fetchone()

    # Get favorites and gift count before closing DB connection
    fav_ids = _get_favorites(user["id"], db)
    gift_count = _gift_count(user["id"], db)

    cur.close()
    db.close()

    return jsonify({
        "playerName": row["username"],
        "ownedCardIds": owned_card_ids,
        "wins": char.get("wins", 0),
        "losses": char.get("losses", 0),
        "draws": char.get("draws", 0),
        "money": char.get("money", 0),
        "joinedAt": str(row["created_at"]) if row["created_at"] else None,
        "trainerName": char.get("trainerName"),
        "gender": char.get("gender"),
        "skinTone": char.get("skinTone"),
        "hairPath": char.get("hairPath"),
        "topPath": char.get("topPath"),
        "bottomPath": char.get("bottomPath"),
        "hatPath": char.get("hatPath"),
        "friendCode": friend_code,
        "location": char.get("location", "Pallet Town"),
        "favoriteCardIds": fav_ids,
        "giftCount": gift_count,
    })


@app.route("/api/me/character", methods=["PUT"])
def put_character():
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()
    trainer_name = data.get("trainerName", "").strip()
    db = get_db()
    cur = db.cursor(dictionary=True)

    # Check trainer name uniqueness (exclude current user)
    if trainer_name:
        cur.execute(
            "SELECT COUNT(*) as cnt FROM triad_characters WHERE user_id != %s AND trainer_name = %s",
            (user["id"], trainer_name),
        )
        if cur.fetchone()["cnt"] > 0:
            cur.close()
            db.close()
            return jsonify({"error": "That trainer name is already taken."}), 409

    cur.close()

    # Ensure character row exists
    char = _ensure_character(user["id"], db)
    updates = {}
    if not char.get("friendCode"):
        updates["friendCode"] = _generate_friend_code(db)
    if not char.get("location"):
        updates["location"] = "Your Bedroom"
    for key in ("trainerName", "gender", "skinTone", "hairPath", "topPath", "bottomPath", "hatPath"):
        if key in data:
            updates[key] = data[key]
    _save_character(user["id"], updates, db)
    db.close()
    return jsonify({"ok": True})


@app.route("/api/me/location", methods=["PUT"])
def put_location():
    """Update the player's current location."""
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()
    loc = data.get("location", "").strip() if data else ""
    if not loc:
        return jsonify({"error": "location is required."}), 400

    db = get_db()
    _ensure_character(user["id"], db)
    _save_character(user["id"], {"location": loc}, db)
    db.close()
    return jsonify({"ok": True, "location": loc})


def _generate_friend_code(db):
    """Generate a unique 12-digit friend code not already in use."""
    import random
    cur = db.cursor(dictionary=True)
    for _ in range(100):
        code = ''.join(str(random.randint(0, 9)) for _ in range(12))
        cur.execute("SELECT COUNT(*) as cnt FROM triad_characters WHERE friend_code = %s", (code,))
        if cur.fetchone()["cnt"] == 0:
            cur.close()
            return code
    cur.close()
    import time
    return str(int(time.time() * 1000))[-12:].zfill(12)


@app.route("/api/me/check-name", methods=["GET"])
def check_name():
    """Returns {available: true} if the trainer name is not taken."""
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    name = request.args.get("name", "").strip()
    if not name:
        return jsonify({"available": False, "error": "Name is required."})

    db = get_db()
    cur = db.cursor(dictionary=True)
    cur.execute(
        "SELECT COUNT(*) as cnt FROM triad_characters WHERE user_id != %s AND trainer_name = %s",
        (user["id"], name),
    )
    row = cur.fetchone()
    cur.close()
    db.close()
    return jsonify({"available": row["cnt"] == 0})


@app.route("/api/me/character", methods=["DELETE"])
def delete_character():
    """Delete the player's character profile and all cards."""
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json() or {}
    confirm_name = (data.get("trainerName") or "").strip()
    if not confirm_name:
        return jsonify({"error": "Trainer name required to confirm deletion."}), 400

    db = get_db()
    cur = db.cursor(dictionary=True)
    char = _get_character(user["id"], db)
    current_name = (char.get("trainerName") or "").strip()
    if current_name.lower() != confirm_name.lower():
        cur.close()
        db.close()
        return jsonify({"error": "Trainer name does not match."}), 403

    cur.execute("DELETE FROM triad_cards WHERE user_id = %s", (user["id"],))
    cur.execute("DELETE FROM triad_characters WHERE user_id = %s", (user["id"],))
    db.commit()
    cur.close()
    db.close()
    return jsonify({"ok": True})


@app.route("/api/me/match-result", methods=["POST"])
def post_match():
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()
    captures = data.get("captures") or {}
    outcome = data.get("outcome", "")

    db = get_db()
    cur = db.cursor()

    # Award XP for captures
    for card_id, count in captures.items():
        cur.execute(
            "INSERT INTO triad_cards (user_id, card_id, xp) VALUES (%s, %s, %s) "
            "ON DUPLICATE KEY UPDATE xp = xp + %s",
            (user["id"], card_id, count, count),
        )

    # Update win/loss/draw counters on character
    _ensure_character(user["id"], db)
    field = {"win": "wins", "loss": "losses", "draw": "draws"}.get(outcome)
    if field:
        cur.execute(f"UPDATE triad_characters SET {field} = {field} + 1 WHERE user_id = %s", (user["id"],))

    db.commit()
    cur.close()
    db.close()
    return jsonify({"levelUps": [], "evolutions": []})


@app.route("/api/me/claim-starter", methods=["POST"])
def claim_starter():
    """Grant the chosen starter deck cards to the player.
    Accepts `cardIds` (list of strings) or `cards` (list of {cardId, shiny})."""
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()
    # Support both old flat list and new {cardId, shiny} format
    raw_cards = data.get("cards") or data.get("cardIds") or []
    if not raw_cards:
        return jsonify({"error": "No cards provided"}), 400

    db = get_db()
    cur = db.cursor()
    for entry in raw_cards:
        if isinstance(entry, dict):
            card_id = entry.get("cardId")
            shiny = 1 if entry.get("shiny") else 0
        else:
            card_id = entry
            shiny = 0
        cur.execute(
            "INSERT INTO triad_cards (user_id, card_id, xp, is_shiny, source) VALUES (%s, %s, 0, %s, 'starter_deck') "
            "ON DUPLICATE KEY UPDATE xp = xp",
            (user["id"], card_id, shiny),
        )
    db.commit()
    cur.close()
    db.close()
    return jsonify({"ok": True, "granted": len(raw_cards)})


@app.route("/api/me/cards", methods=["PUT"])
def put_cards():
    """Save card growth data (XP, level, bonuses) from the client."""
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    data = request.get_json()
    cards = data.get("cards") or []
    db = get_db()
    cur = db.cursor()
    for c in cards:
        cur.execute(
            """INSERT INTO triad_cards (user_id, card_id, xp, level,
               bonus_north, bonus_south, bonus_east, bonus_west, is_shiny, source)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
               ON DUPLICATE KEY UPDATE
               xp = VALUES(xp), level = VALUES(level),
               bonus_north = VALUES(bonus_north), bonus_south = VALUES(bonus_south),
               bonus_east = VALUES(bonus_east), bonus_west = VALUES(bonus_west),
               is_shiny = VALUES(is_shiny), source = VALUES(source)""",
            (user["id"], c.get("cardId"), c.get("xp", 0), c.get("level", 1),
             c.get("bonusNorth", 0), c.get("bonusSouth", 0),
             c.get("bonusEast", 0), c.get("bonusWest", 0),
             1 if c.get("shiny") else 0, c.get("source")),
        )
    db.commit()
    cur.close()
    db.close()
    return jsonify({"ok": True})


@app.route("/api/me/cards", methods=["GET"])
def get_cards():
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    db = get_db()
    cur = db.cursor(dictionary=True)
    cur.execute("""
        SELECT card_id AS cardId, xp, level,
               bonus_north AS bonusNorth, bonus_south AS bonusSouth,
               bonus_east AS bonusEast, bonus_west AS bonusWest,
               is_shiny AS shiny, source
        FROM triad_cards WHERE user_id = %s
    """, (user["id"],))
    cards = cur.fetchall()
    cur.close()
    db.close()
    return jsonify(cards)


def _get_favorites(user_id, db):
    cur = db.cursor(dictionary=True)
    cur.execute("SELECT card_id FROM triad_favorites WHERE user_id = %s ORDER BY sort_order", (user_id,))
    favs = [r["card_id"] for r in cur.fetchall()]
    cur.close()
    return favs


def _gift_count(user_id, db):
    cur = db.cursor(dictionary=True)
    cur.execute("SELECT COUNT(*) as cnt FROM triad_gifts WHERE user_id = %s AND claimed = 0", (user_id,))
    row = cur.fetchone()
    cur.close()
    return row["cnt"] if row else 0


@app.route("/api/me/favorites", methods=["GET"])
def get_favorites():
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    db = get_db()
    favs = _get_favorites(user["id"], db)
    db.close()
    return jsonify(favs)


@app.route("/api/me/favorites", methods=["PUT"])
def put_favorites():
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    data = request.get_json()
    card_ids = data.get("cardIds") or []
    if len(card_ids) > 3:
        return jsonify({"error": "Max 3 favorites"}), 400
    db = get_db()
    cur = db.cursor()
    cur.execute("DELETE FROM triad_favorites WHERE user_id = %s", (user["id"],))
    for i, card_id in enumerate(card_ids):
        cur.execute(
            "INSERT INTO triad_favorites (user_id, card_id, sort_order) VALUES (%s, %s, %s)",
            (user["id"], card_id, i),
        )
    db.commit()
    cur.close()
    db.close()
    return jsonify({"ok": True, "favoriteCardIds": card_ids})


@app.route("/api/me/evolve", methods=["POST"])
def evolve():
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    return jsonify({"ok": True})


@app.route("/api/chat", methods=["GET"])
def get_chat():
    """Return the last 50 chat messages (public, no auth required to read)."""
    db = get_db()
    cur = db.cursor(dictionary=True)
    cur.execute(
        "SELECT c.id, c.sender_name AS sender, c.message AS text, c.created_at "
        "FROM triad_chat c ORDER BY c.id DESC LIMIT 50"
    )
    rows = cur.fetchall()
    cur.close()
    db.close()
    rows.reverse()
    for r in rows:
        r["created_at"] = str(r["created_at"])
    return jsonify(rows)


@app.route("/api/chat", methods=["POST"])
def post_chat():
    """Send a chat message. Requires auth."""
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    data = request.get_json()
    text = (data.get("text") or "").strip()
    sender = (data.get("sender") or user["username"]).strip()
    if not text or len(text) > 500:
        return jsonify({"error": "Message must be 1-500 characters"}), 400

    db = get_db()
    cur = db.cursor()
    cur.execute(
        "INSERT INTO triad_chat (user_id, sender_name, message) VALUES (%s, %s, %s)",
        (user["id"], sender, text),
    )
    db.commit()
    cur.close()
    db.close()
    return jsonify({"ok": True})


@app.route("/api/me/gifts", methods=["GET"])
def get_gifts():
    """Return unclaimed gifts for the authenticated user."""
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    db = get_db()
    cur = db.cursor(dictionary=True)
    cur.execute(
        "SELECT id, gift_type, item_id, quantity, message, from_user_id, claimed, created_at "
        "FROM triad_gifts WHERE user_id = %s AND claimed = 0 ORDER BY created_at DESC",
        (user["id"],),
    )
    gifts = cur.fetchall()
    # Also get count of all unclaimed for badge
    cur.execute("SELECT COUNT(*) as cnt FROM triad_gifts WHERE user_id = %s AND claimed = 0", (user["id"],))
    count = cur.fetchone()["cnt"]
    cur.close()
    db.close()
    for g in gifts:
        g["created_at"] = str(g["created_at"])
    return jsonify({"gifts": gifts, "count": count})


@app.route("/api/me/gifts/<int:gift_id>/claim", methods=["POST"])
def claim_gift(gift_id):
    """Mark a gift as claimed."""
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    db = get_db()
    cur = db.cursor(dictionary=True)
    cur.execute("SELECT * FROM triad_gifts WHERE id = %s AND user_id = %s AND claimed = 0", (gift_id, user["id"]))
    gift = cur.fetchone()
    if not gift:
        cur.close()
        db.close()
        return jsonify({"error": "Gift not found or already claimed"}), 404
    cur.execute("UPDATE triad_gifts SET claimed = 1 WHERE id = %s", (gift_id,))
    # Add the gifted item to player's collection with bonus stats
    if gift["gift_type"] == "item" and gift["item_id"]:
        from_user = gift.get("from_username") or "Admin"
        source = f"Gift from {from_user} {gift['created_at'].strftime('%m/%d/%Y')}"
        is_shiny = gift.get("is_shiny", 0)
        for _ in range(gift.get("quantity", 1)):
            cur.execute(
                "INSERT INTO triad_cards (user_id, card_id, xp, level, "
                "bonus_north, bonus_south, bonus_east, bonus_west, "
                "is_shiny, source) "
                "VALUES (%s, %s, 0, 1, %s, %s, %s, %s, %s, %s) "
                "ON DUPLICATE KEY UPDATE xp = xp",
                (user["id"], gift["item_id"],
                 gift.get("bonus_north", 0), gift.get("bonus_south", 0),
                 gift.get("bonus_east", 0), gift.get("bonus_west", 0),
                 is_shiny, source),
            )
    db.commit()
    cur.close()
    db.close()
    return jsonify({"ok": True, "gift": {
        "type": gift["gift_type"], "itemId": gift["item_id"],
        "quantity": gift["quantity"], "message": gift["message"],
    }})


# Admin: grant gift (protected by simple admin key)
ADMIN_KEY = os.environ.get("ADMIN_KEY", "triad-admin-2024")

def _require_admin():
    key = request.headers.get("X-Admin-Key", "")
    return key == ADMIN_KEY


@app.route("/api/admin/gift", methods=["POST"])
def admin_grant_gift():
    """Grant a gift to a user. Requires X-Admin-Key header."""
    if not _require_admin():
        return jsonify({"error": "Unauthorized"}), 401
    data = request.get_json()
    username = (data.get("username") or "").strip()
    gift_type = data.get("giftType", "item")
    item_id = data.get("itemId", "")
    quantity = int(data.get("quantity", 1))
    message = (data.get("message") or "A gift from the admin!").strip()
    bn = int(data.get("bonusNorth", 0))
    bs = int(data.get("bonusSouth", 0))
    be = int(data.get("bonusEast", 0))
    bw = int(data.get("bonusWest", 0))
    shiny = 1 if data.get("shiny") else 0

    if not username:
        return jsonify({"error": "username required"}), 400

    db = get_db()
    cur = db.cursor(dictionary=True)
    cur.execute("SELECT id FROM triad_users WHERE username = %s", (username,))
    row = cur.fetchone()
    if not row:
        cur.close()
        db.close()
        return jsonify({"error": "User not found"}), 404

    cur.execute(
        "INSERT INTO triad_gifts (user_id, from_username, gift_type, item_id, quantity, message, "
        "bonus_north, bonus_south, bonus_east, bonus_west, is_shiny) "
        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
        (row["id"], "Admin", gift_type, item_id, quantity, message, bn, bs, be, bw, shiny),
    )
    db.commit()
    cur.close()
    db.close()
    return jsonify({"ok": True, "username": username})


@app.route("/api/decks", methods=["GET"])
def get_decks():
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    db = get_db()
    cur = db.cursor(dictionary=True)
    cur.execute("SELECT id, name, card_ids_json, active FROM triad_decks WHERE user_id = %s", (user["id"],))
    rows = cur.fetchall()
    cur.close()
    db.close()

    decks = []
    for r in rows:
        card_ids = []
        if r["card_ids_json"]:
            try:
                card_ids = json.loads(r["card_ids_json"])
            except json.JSONDecodeError:
                pass
        decks.append({
            "id": r["id"],
            "name": r["name"],
            "cardIds": card_ids,
            "isDefault": bool(r["active"]),
        })
    return jsonify(decks)


@app.route("/api/decks", methods=["PUT"])
def put_deck():
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()
    deck_id = str(data.get("id") or "")
    name = data.get("name", "Untitled")
    card_ids = data.get("cardIds", [])
    is_default = data.get("isDefault", False)

    if not deck_id:
        import uuid
        deck_id = str(uuid.uuid4())

    db = get_db()
    cur = db.cursor()
    cur.execute(
        "INSERT INTO triad_decks (id, user_id, name, card_ids_json, active) "
        "VALUES (%s, %s, %s, %s, %s) "
        "ON DUPLICATE KEY UPDATE name = VALUES(name), card_ids_json = VALUES(card_ids_json), active = VALUES(active)",
        (deck_id, user["id"], name, json.dumps(card_ids), int(is_default)),
    )
    db.commit()
    cur.close()
    db.close()
    return jsonify({"id": deck_id, "name": name, "cardIds": card_ids, "isDefault": is_default})


@app.route("/api/decks/<deck_id>/activate", methods=["POST"])
def activate_deck(deck_id):
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    db = get_db()
    cur = db.cursor()
    cur.execute("UPDATE triad_decks SET active = 0 WHERE user_id = %s", (user["id"],))
    cur.execute(
        "UPDATE triad_decks SET active = 1 WHERE id = %s AND user_id = %s",
        (deck_id, user["id"]),
    )
    db.commit()
    cur.close()
    db.close()
    return jsonify({"ok": True})


@app.route("/api/decks/<deck_id>", methods=["DELETE"])
def delete_deck(deck_id):
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    db = get_db()
    cur = db.cursor()
    cur.execute("DELETE FROM triad_decks WHERE id = %s AND user_id = %s", (deck_id, user["id"]))
    db.commit()
    cur.close()
    db.close()
    return jsonify({"ok": True})


# ── Asset delivery (delta updates) ──────────────────────────────────────
ASSETS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")

@app.route("/api/assets/manifest", methods=["GET"])
def asset_manifest():
    """Returns {version, files: {path: md5}} for all cached assets."""
    manifest_path = os.path.join(ASSETS_DIR, "manifest.json")
    if os.path.exists(manifest_path):
        with open(manifest_path, "r") as f:
            return jsonify(json.load(f))
    # Generate on-the-fly if no manifest file exists
    files = {}
    for root, _, filenames in os.walk(ASSETS_DIR):
        for fn in filenames:
            if fn == "manifest.json":
                continue
            full = os.path.join(root, fn)
            rel = os.path.relpath(full, ASSETS_DIR).replace("\\", "/")
            with open(full, "rb") as f:
                files[rel] = hashlib.md5(f.read()).hexdigest()
    return jsonify({"version": 1, "files": files})

@app.route("/api/assets/<path:filepath>", methods=["GET"])
def serve_asset(filepath):
    """Serve individual asset files from the assets directory."""
    return send_from_directory(ASSETS_DIR, filepath)

# ── Main ─────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=3001, debug=False)
