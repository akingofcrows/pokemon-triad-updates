"""TTMMO API Server — Flask + MySQL backend for Pokemon Triple Triad."""
import hashlib
import json
import os
import secrets

from flask import Flask, jsonify, request
import mysql.connector

app = Flask(__name__)

# ── Database config ──────────────────────────────────────────────────────
DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "localhost"),
    "port": int(os.environ.get("DB_PORT", 3306)),
    "user": os.environ.get("DB_USER", "root"),
    "password": os.environ.get("DB_PASS", "Midnight1"),
    "database": os.environ.get("DB_NAME", "pokemon_triad"),
}


def get_db():
    return mysql.connector.connect(**DB_CONFIG)


def init_db():
    """Create tables if they don't exist."""
    db = get_db()
    cur = db.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INT AUTO_INCREMENT PRIMARY KEY,
            username VARCHAR(64) UNIQUE NOT NULL,
            password_hash VARCHAR(128) NOT NULL,
            token VARCHAR(128) UNIQUE,
            character_json TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS cards (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            card_id VARCHAR(64) NOT NULL,
            xp INT DEFAULT 0,
            level INT DEFAULT 1,
            FOREIGN KEY (user_id) REFERENCES users(id),
            UNIQUE KEY user_card (user_id, card_id)
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS decks (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            name VARCHAR(128) NOT NULL,
            card_ids TEXT,
            active TINYINT DEFAULT 0,
            FOREIGN KEY (user_id) REFERENCES users(id)
        )
    """)
    db.commit()
    cur.close()
    db.close()


# ── Auth helpers ─────────────────────────────────────────────────────────
def _hash(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()


def _require_auth():
    token = request.headers.get("Authorization", "").replace("Bearer ", "")
    if not token:
        return None
    db = get_db()
    cur = db.cursor(dictionary=True)
    cur.execute("SELECT id, username FROM users WHERE token = %s", (token,))
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
    cur.execute("SELECT id FROM users WHERE username = %s", (username,))
    if cur.fetchone():
        cur.close()
        db.close()
        return jsonify({"error": "Username already taken"}), 409

    token = secrets.token_hex(32)
    cur.execute(
        "INSERT INTO users (username, password_hash, token) VALUES (%s, %s, %s)",
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
        "SELECT id, token FROM users WHERE username = %s AND password_hash = %s",
        (username, _hash(password)),
    )
    user = cur.fetchone()
    if not user:
        cur.close()
        db.close()
        return jsonify({"error": "Invalid username or password"}), 401

    if not user["token"]:
        user["token"] = secrets.token_hex(32)
        cur.execute("UPDATE users SET token = %s WHERE id = %s", (user["token"], user["id"]))
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
    cur.execute("SELECT username, character_json FROM users WHERE id = %s", (user["id"],))
    row = cur.fetchone()
    cur.close()
    db.close()

    character = None
    if row and row["character_json"]:
        try:
            character = json.loads(row["character_json"])
        except json.JSONDecodeError:
            character = None

    return jsonify({
        "username": row["username"],
        "character": character,
    })


@app.route("/api/me/character", methods=["PUT"])
def put_character():
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()
    db = get_db()
    cur = db.cursor()
    cur.execute(
        "UPDATE users SET character_json = %s WHERE id = %s",
        (json.dumps(data), user["id"]),
    )
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

    db = get_db()
    cur = db.cursor()
    for card_id, count in captures.items():
        cur.execute(
            "INSERT INTO cards (user_id, card_id, xp) VALUES (%s, %s, %s) "
            "ON DUPLICATE KEY UPDATE xp = xp + %s",
            (user["id"], card_id, count, count),
        )
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
    cur.execute("SELECT card_id, xp, level FROM cards WHERE user_id = %s", (user["id"],))
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
    cur.execute("SELECT * FROM decks WHERE user_id = %s", (user["id"],))
    decks = cur.fetchall()
    cur.close()
    db.close()
    return jsonify(decks)


@app.route("/api/decks", methods=["PUT"])
def put_deck():
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json()
    deck_id = data.get("id")
    name = data.get("name", "Untitled")
    card_ids = json.dumps(data.get("cardIds", []))

    db = get_db()
    cur = db.cursor()
    if deck_id:
        cur.execute(
            "UPDATE decks SET name = %s, card_ids = %s WHERE id = %s AND user_id = %s",
            (name, card_ids, deck_id, user["id"]),
        )
    else:
        cur.execute(
            "INSERT INTO decks (user_id, name, card_ids) VALUES (%s, %s, %s)",
            (user["id"], name, card_ids),
        )
        deck_id = cur.lastrowid
    db.commit()
    cur.close()
    db.close()
    return jsonify({"id": deck_id})


@app.route("/api/decks/<deck_id>/activate", methods=["POST"])
def activate_deck(deck_id):
    user = _require_auth()
    if not user:
        return jsonify({"error": "Unauthorized"}), 401

    db = get_db()
    cur = db.cursor()
    cur.execute("UPDATE decks SET active = 0 WHERE user_id = %s", (user["id"],))
    cur.execute(
        "UPDATE decks SET active = 1 WHERE id = %s AND user_id = %s",
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
    cur.execute("DELETE FROM decks WHERE id = %s AND user_id = %s", (deck_id, user["id"]))
    db.commit()
    cur.close()
    db.close()
    return jsonify({"ok": True})


# ── Main ─────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=3001, debug=True)
