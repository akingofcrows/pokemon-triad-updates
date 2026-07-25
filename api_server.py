"""TTMMO API Server — Flask + MySQL backend for Pokemon Triple Triad."""
import hashlib
import json
import os
import secrets

from flask import Flask, jsonify, request
import mysql.connector

app = Flask(__name__)

# ── Database config ──────────────────────────────────────────────────────
# Connects to Linux MySQL via SSH tunnel on port 3307
DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "127.0.0.1"),
    "port": int(os.environ.get("DB_PORT", 3307)),
    "user": os.environ.get("DB_USER", "fablewood_user"),
    "password": os.environ.get("DB_PASS", "StrongStr0ngPass!"),
    "database": os.environ.get("DB_NAME", "cardmmo"),
}


def get_db():
    return mysql.connector.connect(**DB_CONFIG)


def init_db():
    """Create triad-prefixed tables inside the cardmmo database."""
    db = get_db()
    cur = db.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS triad_users (
            id INT AUTO_INCREMENT PRIMARY KEY,
            username VARCHAR(64) UNIQUE NOT NULL,
            password_hash VARCHAR(128) NOT NULL,
            token VARCHAR(128) UNIQUE,
            profile_json TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS triad_cards (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            card_id VARCHAR(64) NOT NULL,
            xp INT DEFAULT 0,
            level INT DEFAULT 1,
            FOREIGN KEY (user_id) REFERENCES triad_users(id),
            UNIQUE KEY user_card (user_id, card_id)
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
    db.commit()
    cur.close()
    db.close()


def _get_profile(user_id, db):
    """Load the user's profile_json, or return an empty dict."""
    cur = db.cursor(dictionary=True)
    cur.execute("SELECT profile_json FROM triad_users WHERE id = %s", (user_id,))
    row = cur.fetchone()
    cur.close()
    if row and row["profile_json"]:
        try:
            return json.loads(row["profile_json"])
        except json.JSONDecodeError:
            pass
    return {}

def _save_profile(user_id, profile, db):
    """Persist the profile_json dict."""
    cur = db.cursor()
    cur.execute("UPDATE triad_users SET profile_json = %s WHERE id = %s",
                (json.dumps(profile), user_id))
    db.commit()
    cur.close()


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
    user_id = cur.lastrowid

    # Grant starter Pokémon cards
    starter_cards = [
        "card_bulbasaur_1", "card_charmander_1", "card_squirtle_1",
        "card_pikachu_1", "card_eevee_1", "card_oddish_1",
        "card_rattata_1", "card_pidgey_1", "card_caterpie_1",
        "card_weedle_1", "card_spearow_1", "card_nidoranf_1",
        "card_nidoranm_1", "card_zubat_1", "card_geodude_1",
    ]
    for card_id in starter_cards:
        cur.execute(
            "INSERT INTO triad_cards (user_id, card_id, xp) VALUES (%s, %s, 0) "
            "ON DUPLICATE KEY UPDATE xp = xp",
            (user_id, card_id),
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

    # Owned card ids from triad_cards
    cur.execute("SELECT card_id FROM triad_cards WHERE user_id = %s", (user["id"],))
    owned_card_ids = [r["card_id"] for r in cur.fetchall()]

    # Full profile
    profile = _get_profile(user["id"], db)

    # User row for username / joined_at
    cur.execute("SELECT username, created_at FROM triad_users WHERE id = %s", (user["id"],))
    row = cur.fetchone()
    cur.close()
    db.close()

    return jsonify({
        "playerName": row["username"],
        "ownedCardIds": owned_card_ids,
        "wins": profile.get("wins", 0),
        "losses": profile.get("losses", 0),
        "draws": profile.get("draws", 0),
        "money": profile.get("money", 0),
        "joinedAt": str(row["created_at"]) if row["created_at"] else None,
        "trainerName": profile.get("trainerName"),
        "gender": profile.get("gender"),
        "skinTone": profile.get("skinTone"),
        "hairPath": profile.get("hairPath"),
        "topPath": profile.get("topPath"),
        "bottomPath": profile.get("bottomPath"),
        "hatPath": profile.get("hatPath"),
    })


@app.route("/api/me/character", methods=["PUT"])
def put_character():
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()
    db = get_db()
    profile = _get_profile(user["id"], db)
    # Merge trainer appearance fields
    for key in ("trainerName", "gender", "skinTone", "hairPath", "topPath", "bottomPath", "hatPath"):
        if key in data:
            profile[key] = data[key]
    _save_profile(user["id"], profile, db)
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

    # Update win/loss/draw counters
    profile = _get_profile(user["id"], db)
    if outcome == "win":
        profile["wins"] = profile.get("wins", 0) + 1
    elif outcome == "loss":
        profile["losses"] = profile.get("losses", 0) + 1
    elif outcome == "draw":
        profile["draws"] = profile.get("draws", 0) + 1
    _save_profile(user["id"], profile, db)

    db.commit()
    cur.close()
    db.close()
    return jsonify({"levelUps": [], "evolutions": []})


@app.route("/api/me/cards", methods=["GET"])
def get_cards():
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    db = get_db()
    cur = db.cursor(dictionary=True)
    cur.execute("SELECT card_id, xp, level FROM triad_cards WHERE user_id = %s", (user["id"],))
    cards = cur.fetchall()
    cur.close()
    db.close()
    return jsonify(cards)


@app.route("/api/me/evolve", methods=["POST"])
def evolve():
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401
    return jsonify({"ok": True})


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

    db = get_db()
    cur = db.cursor()
    if deck_id:
        cur.execute(
            "UPDATE triad_decks SET name = %s, card_ids_json = %s, active = %s WHERE id = %s AND user_id = %s",
            (name, json.dumps(card_ids), int(is_default), deck_id, user["id"]),
        )
    else:
        import uuid
        deck_id = str(uuid.uuid4())
        cur.execute(
            "INSERT INTO triad_decks (id, user_id, name, card_ids_json, active) VALUES (%s, %s, %s, %s, %s)",
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


# ── Main ─────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=3001, debug=True)
