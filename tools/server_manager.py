"""TTMMO Server Manager — Full Admin GUI with DB browsing, editing, and game tools."""
import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox, simpledialog
import threading
import os
import json

# PIL for sprite previews (optional)
try:
    from PIL import Image, ImageTk
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

try:
    import paramiko
except ImportError:
    import subprocess; subprocess.check_call(["pip", "install", "paramiko"]); import paramiko

SERVER_HOST = "100.65.103.71"
SERVER_USER = "akingofcrows"
SERVER_PORT = 22
DB_NAME = "pokemon_triad"
DB_USER = "fablewood_user"
DB_PASS = "StrongStr0ngPass!"
SSH_PASSWORD = "Midnight1"

class App:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("TTMMO Server Manager")
        self.root.geometry("960x680")
        self.root.configure(bg="#1a1a2e")
        self.ssh = None
        self._password = SSH_PASSWORD

        self._build_header()
        self._build_tabs()
        self._status("Connecting...", "#f39c12")

        self.root.after(100, lambda: threading.Thread(target=self._connect, daemon=True).start())
        self.root.mainloop()

    # ── Header ─────────────────────────────────────────────────────────
    def _build_header(self):
        f = tk.Frame(self.root, bg="#0f3460", height=50)
        f.pack(fill=tk.X)
        f.pack_propagate(False)
        tk.Label(f, text="TTMMO Server Manager", font=("Segoe UI", 16, "bold"),
                 fg="#c9a44c", bg="#0f3460").pack(side=tk.LEFT, padx=15, pady=8)
        self.status_lbl = tk.Label(f, text="● Disconnected", font=("Segoe UI", 10),
                                    fg="#e74c3c", bg="#0f3460")
        self.status_lbl.pack(side=tk.RIGHT, padx=15)

    # ── Tabs ───────────────────────────────────────────────────────────
    def _build_tabs(self):
        nb = ttk.Notebook(self.root)
        nb.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)

        style = ttk.Style()
        style.theme_use("clam")
        style.configure("TNotebook", background="#1a1a2e", borderwidth=0)
        style.configure("TNotebook.Tab", background="#16213e", foreground="#ccc",
                        padding=[18, 6], font=("Segoe UI", 10))
        style.map("TNotebook.Tab", background=[("selected", "#0f3460")],
                  foreground=[("selected", "#c9a44c")])

        self._tab_dashboard(nb)
        self._tab_players(nb)
        self._tab_cards(nb)
        self._tab_gifts(nb)
        self._tab_story(nb)
        self._tab_decks(nb)
        self._tab_card_db(nb)
        self._tab_sets(nb)
        self._tab_logs(nb)
        nb.bind("<<NotebookTabChanged>>", self._on_tab_change)

    # ── SSH ────────────────────────────────────────────────────────────
    def _connect(self):
        try:
            self.ssh = paramiko.SSHClient()
            self.ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            self.ssh.connect(SERVER_HOST, port=SERVER_PORT, username=SERVER_USER,
                           password=self._password, timeout=10, banner_timeout=10)
            self._status("● Connected via Tailscale", "#2ecc71")
            self.root.after(0, self._refresh_dashboard)
        except Exception as e:
            self._status(f"SSH failed: {e}", "#e74c3c")

    def _ensure(self):
        if self.ssh and self.ssh.get_transport() and self.ssh.get_transport().is_active():
            return True
        try:
            self.ssh = paramiko.SSHClient()
            self.ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            self.ssh.connect(SERVER_HOST, port=SERVER_PORT, username=SERVER_USER,
                           password=self._password, timeout=8, banner_timeout=10)
            return True
        except:
            return False

    def _run(self, cmd, timeout=15):
        if not self._ensure():
            return None
        try:
            _, stdout, stderr = self.ssh.exec_command(cmd, timeout=timeout)
            out = stdout.read().decode(errors="replace")
            err = stderr.read().decode(errors="replace")
            return out + err
        except Exception as e:
            return f"Error: {e}"

    def _db(self, sql, timeout=15):
        """Run SQL and return list of dicts."""
        safe = sql.replace("'", "'\"'\"'")
        raw = self._run(f"mysql -u {DB_USER} -p{DB_PASS} -h 127.0.0.1 {DB_NAME} -e '{safe}' --batch 2>&1", timeout)
        if raw is None:
            return None
        if "Error:" in raw and "ERROR" in raw:
            return raw
        lines = [l for l in raw.strip().split("\n") if l]
        if len(lines) < 2:
            return []
        headers = [h.strip() for h in lines[0].split("\t")]
        rows = []
        for line in lines[1:]:
            vals = line.split("\t")
            row = {}
            for i, h in enumerate(headers):
                row[h] = vals[i] if i < len(vals) else ""
            rows.append(row)
        return rows

    def _status(self, text, color):
        self.root.after(0, lambda: self.status_lbl.config(text=text, fg=color))

    # ── TAB: Dashboard ─────────────────────────────────────────────────
    def _tab_dashboard(self, nb):
        f = tk.Frame(nb, bg="#1a1a2e")
        nb.add(f, text="📊 Dashboard")

        self.dash_text = scrolledtext.ScrolledText(f, bg="#0d1117", fg="#eee",
            font=("Consolas", 11), height=20)
        self.dash_text.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        bf = tk.Frame(f, bg="#1a1a2e")
        bf.pack(pady=5)
        tk.Button(bf, text="🔄 Refresh", bg="#3498db", fg="white", font=("Segoe UI", 10, "bold"),
                  relief=tk.FLAT, padx=20, pady=6,
                  command=lambda: threading.Thread(target=self._refresh_dashboard, daemon=True).start()).pack(side=tk.LEFT, padx=5)
        tk.Button(bf, text="🔁 Restart Server", bg="#e74c3c", fg="white", font=("Segoe UI", 10, "bold"),
                  relief=tk.FLAT, padx=20, pady=6,
                  command=lambda: threading.Thread(target=self._restart_server, daemon=True).start()).pack(side=tk.LEFT, padx=5)
        tk.Button(bf, text="🌐 Restart ngrok", bg="#9b59b6", fg="white", font=("Segoe UI", 10, "bold"),
                  relief=tk.FLAT, padx=20, pady=6,
                  command=lambda: threading.Thread(target=self._restart_ngrok, daemon=True).start()).pack(side=tk.LEFT, padx=5)

    def _refresh_dashboard(self):
        self.dash_text.delete(1.0, tk.END)

        # Flask
        f = self._run("curl -s -o /dev/null -w '%{http_code}' http://localhost:3001/api/me")
        flask_ok = f and ("401" in f or "200" in f)

        # MariaDB
        db = self._db("SELECT 1 AS test")
        db_ok = isinstance(db, list)

        # ngrok
        n = self._run("curl -s http://localhost:4040/api/tunnels 2>&1 | python3 -c \"import sys,json;d=json.load(sys.stdin);print(d['tunnels'][0]['public_url'])\" 2>&1")
        ngrok_url = n.strip() if n and "ngrok" in n else "Not running"

        # Stats
        users = self._db("SELECT COUNT(*) AS cnt FROM triad_users")
        chars = self._db("SELECT COUNT(*) AS cnt FROM triad_characters")
        cards = self._db("SELECT COUNT(*) AS cnt FROM triad_cards")
        gifts = self._db("SELECT COUNT(*) AS cnt FROM triad_gifts WHERE claimed=0")
        uptime = self._run("uptime")

        def _out(t):
            self.dash_text.insert(tk.END, t + "\n")

        def _cnt(r):
            return r[0]['cnt'] if isinstance(r, list) and r else '0'

        _out(f"Flask Server:  {'🟢 Running' if flask_ok else '🔴 Down'}")
        _out(f"Database:      {'🟢 Connected' if db_ok else '🔴 Disconnected'}")
        _out(f"ngrok:         {'🟢 ' + ngrok_url if 'ngrok' in ngrok_url else '🔴 ' + ngrok_url}")
        _out(f"─────────────────────────────────────────────")
        _out(f"Users:         {_cnt(users)}")
        _out(f"Characters:    {_cnt(chars)}")
        _out(f"Cards:         {_cnt(cards)}")
        _out(f"Unclaimed Gifts: {_cnt(gifts)}")
        _out(f"─────────────────────────────────────────────")
        _out(f"Server Uptime: {uptime.strip() if uptime else '?'}")

    def _restart_server(self):
        self._run("fuser -k 3001/tcp 2>/dev/null; sleep 1")
        r = self._run("cd ~ && DB_PORT=3306 nohup python3 api_server.py > /tmp/api.log 2>&1 & sleep 2 && tail -2 /tmp/api.log")
        self.root.after(0, self._refresh_dashboard)

    def _restart_ngrok(self):
        self._run("killall ngrok 2>/dev/null; sleep 2")
        r = self._run("cd ~ && nohup ./ngrok http 3001 > /tmp/ngrok.log 2>&1 & sleep 5 && curl -s http://localhost:4040/api/tunnels 2>&1 | python3 -c \"import sys,json;d=json.load(sys.stdin);print(d['tunnels'][0]['public_url'])\"")
        self.root.after(0, self._refresh_dashboard)

    # ── TAB: Players ───────────────────────────────────────────────────
    def _tab_players(self, nb):
        f = tk.Frame(nb, bg="#1a1a2e")
        nb.add(f, text="👤 Players")
        self._data_tab(f, "players",
            query="SELECT u.id, u.username, c.trainer_name, c.gender, c.money, c.wins, c.losses, c.draws, c.location, u.created_at FROM triad_users u LEFT JOIN triad_characters c ON c.user_id=u.id ORDER BY u.id DESC LIMIT 100",
            columns=("ID","Username","Trainer","Gender","Money","Wins","Losses","Draws","Location","Created"),
            widths=(40,100,120,50,60,40,40,40,100,140),
            db_cols=("id","username","trainer_name","gender","money","wins","losses","draws","location","created_at"),
            edit_table="triad_characters",
            edit_where="user_id",
            edit_fields=["trainer_name","money","wins","losses","draws","location"],
            delete_table="triad_users",
            delete_where="id",
            delete_msg="Delete this user and ALL their cards, decks, and progress?")

    # ── TAB: Cards ─────────────────────────────────────────────────────
    def _tab_cards(self, nb):
        f = tk.Frame(nb, bg="#1a1a2e")
        nb.add(f, text="🃏 Cards")
        top = tk.Frame(f, bg="#1a1a2e")
        top.pack(fill=tk.X, padx=10, pady=5)
        tk.Label(top, text="Filter by User ID:", fg="#ccc", bg="#1a1a2e",
                 font=("Segoe UI", 10)).pack(side=tk.LEFT)
        self.card_filter = tk.Entry(top, bg="#16213e", fg="#eee", insertbackground="#eee",
                                     font=("Consolas", 10), width=10)
        self.card_filter.pack(side=tk.LEFT, padx=5)
        tk.Button(top, text="🔍 Search", bg="#3498db", fg="white", relief=tk.FLAT, padx=12, pady=3,
                  command=lambda: threading.Thread(target=self._refresh_cards, daemon=True).start()).pack(side=tk.LEFT, padx=5)
        tk.Button(top, text="🔄 All Cards", bg="#2ecc71", fg="white", relief=tk.FLAT, padx=12, pady=3,
                  command=lambda: threading.Thread(target=self._refresh_cards_all, daemon=True).start()).pack(side=tk.LEFT, padx=5)

        self._data_tab(f, "cards",
            query="SELECT id, user_id, card_id, xp, level, bonus_north, bonus_south, bonus_east, bonus_west, is_shiny, source FROM triad_cards ORDER BY id DESC LIMIT 200",
            columns=("ID","User","Card ID","XP","Lv","N","S","E","W","Shiny","Source"),
            widths=(40,40,120,50,30,25,25,25,25,40,140),
            db_cols=("id","user_id","card_id","xp","level","bonus_north","bonus_south","bonus_east","bonus_west","is_shiny","source"),
            edit_table="triad_cards",
            edit_where="id",
            edit_fields=["xp","level","bonus_north","bonus_south","bonus_east","bonus_west","is_shiny"],
            delete_table="triad_cards",
            delete_where="id",
            delete_msg="Delete this card instance?")

    def _refresh_cards(self):
        uid = self.card_filter.get().strip()
        if uid:
            self._tv["cards"]["tv"].delete(*self._tv["cards"]["tv"].get_children())
            q = f"SELECT id, user_id, card_id, xp, level, bonus_north, bonus_south, bonus_east, bonus_west, is_shiny, source FROM triad_cards WHERE user_id={uid} ORDER BY id DESC LIMIT 200"
            self._populate_tree("cards", q)

    def _refresh_cards_all(self):
        self.card_filter.delete(0, tk.END)
        self._tv["cards"]["tv"].delete(*self._tv["cards"]["tv"].get_children())
        self._populate_tree("cards")

    # ── TAB: Gifts ─────────────────────────────────────────────────────
    def _tab_gifts(self, nb):
        f = tk.Frame(nb, bg="#1a1a2e")
        nb.add(f, text="🎁 Gifts")

        # Send gift form
        form = tk.LabelFrame(f, text="Send Gift to Player", fg="#c9a44c", bg="#16213e",
                              font=("Segoe UI", 11, "bold"), padx=10, pady=10)
        form.pack(fill=tk.X, padx=10, pady=8)

        fields = [("Username:", "g_user"), ("Card ID:", "g_card"), ("Quantity:", "g_qty"),
                   ("Message:", "g_msg"), ("Shiny:", "g_shiny")]
        self._gift_vars = {}
        for i, (lbl, key) in enumerate(fields):
            tk.Label(form, text=lbl, fg="#ccc", bg="#16213e", font=("Segoe UI", 10)).grid(row=0, column=i*2, padx=3, sticky="e")
            if key == "g_shiny":
                v = tk.BooleanVar()
                tk.Checkbutton(form, variable=v, bg="#16213e", fg="#ccc",
                               selectcolor="#16213e").grid(row=0, column=i*2+1, padx=3, sticky="w")
                self._gift_vars[key] = v
            else:
                w = 18 if key == "g_msg" else 12
                e = tk.Entry(form, bg="#0d1117", fg="#eee", insertbackground="#eee",
                            font=("Consolas", 10), width=w)
                e.grid(row=0, column=i*2+1, padx=3)
                self._gift_vars[key] = e

        tk.Button(form, text="📨 Send Gift", bg="#e67e22", fg="white", font=("Segoe UI", 10, "bold"),
                  relief=tk.FLAT, padx=16, pady=4,
                  command=lambda: threading.Thread(target=self._send_gift, daemon=True).start()
                  ).grid(row=0, column=10, padx=8)

        # Gift history table
        self._data_tab(f, "gifts",
            query="SELECT id, user_id, from_username, gift_type, item_id, quantity, is_shiny, claimed, message, created_at FROM triad_gifts ORDER BY id DESC LIMIT 100",
            columns=("ID","UID","From","Type","Item","Qty","Shiny","Claimed","Message","Date"),
            widths=(35,35,80,50,100,35,40,55,180,140),
            db_cols=("id","user_id","from_username","gift_type","item_id","quantity","is_shiny","claimed","message","created_at"),
            edit_table=None, delete_table="triad_gifts", delete_where="id",
            delete_msg="Delete this gift?")

    def _send_gift(self):
        u = self._gift_vars["g_user"].get().strip()
        c = self._gift_vars["g_card"].get().strip()
        q = self._gift_vars["g_qty"].get().strip() or "1"
        m = self._gift_vars["g_msg"].get().strip()
        s = 1 if self._gift_vars["g_shiny"].get() else 0

        if not u or not c:
            messagebox.showwarning("Missing", "Username and Card ID are required.")
            return

        # Get user_id
        r = self._db(f"SELECT id FROM triad_users WHERE username='{u}'")
        if not isinstance(r, list) or not r:
            messagebox.showerror("Error", f"User '{u}' not found.")
            return
        uid = r[0]["id"]

        sql = f"INSERT INTO triad_gifts (user_id, from_username, gift_type, item_id, quantity, is_shiny, message) VALUES ({uid}, 'Admin', 'card', '{c}', {q}, {s}, '{m}')"
        raw = self._run(f"mysql -u {DB_USER} -p{DB_PASS} -h 127.0.0.1 {DB_NAME} -e \"{sql}\" 2>&1")
        if raw and "ERROR" in raw:
            messagebox.showerror("Error", raw)
        else:
            messagebox.showinfo("Success", f"Gift sent to {u}!")
            self._tv["gifts"]["tv"].delete(*self._tv["gifts"]["tv"].get_children())
            threading.Thread(target=lambda: self._populate_tree("gifts"), daemon=True).start()

    # ── TAB: Story ─────────────────────────────────────────────────────
    def _tab_story(self, nb):
        f = tk.Frame(nb, bg="#1a1a2e")
        nb.add(f, text="📖 Story")
        self._data_tab(f, "story",
            query="SELECT sp.id, sp.user_id, u.username, sp.location_id, sp.node_id, sp.completed, sp.first_clear, sp.times_cleared, sp.cleared_at FROM triad_story_progress sp LEFT JOIN triad_users u ON u.id=sp.user_id ORDER BY sp.id DESC LIMIT 200",
            columns=("ID","UID","User","Location","Node","Done","1st","Times","Cleared At"),
            widths=(35,35,100,120,120,40,30,45,140),
            db_cols=("id","user_id","username","location_id","node_id","completed","first_clear","times_cleared","cleared_at"),
            edit_table="triad_story_progress", edit_where="id",
            edit_fields=["completed","first_clear","times_cleared"],
            delete_table="triad_story_progress", delete_where="id",
            delete_msg="Delete this story progress entry?")

    # ── TAB: Decks ─────────────────────────────────────────────────────
    def _tab_decks(self, nb):
        f = tk.Frame(nb, bg="#1a1a2e")
        nb.add(f, text="🎴 Decks")
        self._data_tab(f, "decks",
            query="SELECT d.id, d.user_id, u.username, d.name, d.active, LENGTH(d.card_ids_json) as size, d.card_ids_json FROM triad_decks d LEFT JOIN triad_users u ON u.id=d.user_id ORDER BY d.user_id LIMIT 100",
            columns=("Deck ID","UID","User","Name","Active","JSON Len","Cards JSON"),
            widths=(300,35,100,140,45,60,400),
            db_cols=("id","user_id","username","name","active","size","card_ids_json"),
            edit_table="triad_decks", edit_where="id",
            edit_fields=["name","active"],
            delete_table="triad_decks", delete_where="id",
            delete_msg="Delete this deck?")

    # ── TAB: Card DB (local cards.json) ────────────────────────────────
    # Exact game mapping: card_bg.png column index per affinity
    AFFINITY_BG_INDEX = {
        "normal":0,"fighting":1,"rock":2,"fire":3,"water":4,
        "grass":5,"electric":6,"psychic":7,"dark":8,"dragon":9,
        "steel":10,"flying":11,"poison":12,"ground":13,"bug":14,
        "ice":15,"ghost":16,"fairy":17
    }
    RARITY_FRAME = {
        "common":"frame.png","uncommon":"frameU.png","rare":"frameR.png",
        "epic":"frameE.png","legendary":"frameL.png"
    }

    def _tab_card_db(self, nb):
        f = tk.Frame(nb, bg="#1a1a2e")
        nb.add(f, text="🃏 Card DB")

        card_path = os.path.join(os.path.dirname(__file__), "..", "assets", "data", "cards.json")
        self._cards_data = []
        try:
            with open(card_path, "r") as fh:
                self._cards_data = json.load(fh).get("cards", [])
        except Exception as e:
            tk.Label(f, text=f"Failed to load cards.json: {e}", fg="#e74c3c", bg="#1a1a2e",
                     font=("Segoe UI", 11)).pack(pady=30)
            return

        # Preload all card assets (same as game)
        self._card_assets = {}
        base = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        if HAS_PIL:
            try:
                self._card_assets["card_bg"] = Image.open(os.path.join(base, "assets","ui","card_bg.png")).convert("RGBA")
                self._card_assets["numbers"] = Image.open(os.path.join(base, "assets","ui","numbers.png")).convert("RGBA")
                # Load all frame variants
                for rkey, fname in self.RARITY_FRAME.items():
                    fp = os.path.join(base, "assets","ui",fname)
                    if os.path.exists(fp):
                        self._card_assets[f"frame_{rkey}"] = Image.open(fp).convert("RGBA")
                # Holo frame
                hfp = os.path.join(base, "assets","ui","holoframe.png")
                if os.path.exists(hfp):
                    self._card_assets["frame_holo"] = Image.open(hfp).convert("RGBA")
                # Type icons
                self._card_assets["types"] = {}
                for t in self.AFFINITY_BG_INDEX:
                    tp = os.path.join(base, "assets","ui","types",f"{t}.png")
                    if os.path.exists(tp):
                        self._card_assets["types"][t] = Image.open(tp).convert("RGBA")
            except Exception as e:
                self._card_assets["error"] = str(e)

        # ── Toolbar row 1: search, rarity, shiny, table toggle ──
        tb = tk.Frame(f, bg="#1a1a2e")
        tb.pack(fill=tk.X, padx=10, pady=(5,0))
        tk.Label(tb, text=f"{len(self._cards_data)} cards", fg="#2ecc71", bg="#1a1a2e",
                 font=("Segoe UI", 10)).pack(side=tk.LEFT, padx=5)

        tk.Label(tb, text="Search:", fg="#ccc", bg="#1a1a2e", font=("Segoe UI", 10)).pack(side=tk.LEFT, padx=(15,3))
        self.card_filter_entry = tk.Entry(tb, bg="#16213e", fg="#eee", insertbackground="#eee",
                                           font=("Consolas", 10), width=16)
        self.card_filter_entry.pack(side=tk.LEFT, padx=3)
        self.card_filter_entry.bind("<KeyRelease>", lambda e: self._render_card_gallery())

        tk.Label(tb, text="Rarity:", fg="#ccc", bg="#1a1a2e", font=("Segoe UI", 10)).pack(side=tk.LEFT, padx=(10,3))
        self.card_rarity_var = tk.StringVar(value="All")
        dd = ttk.Combobox(tb, textvariable=self.card_rarity_var, values=["All","common","uncommon","rare","holo"], state="readonly", width=9)
        dd.pack(side=tk.LEFT, padx=3)
        dd.bind("<<ComboboxSelected>>", lambda e: self._render_card_gallery())

        self._show_shiny = tk.BooleanVar(value=False)
        tk.Checkbutton(tb, text="✨ Shiny", variable=self._show_shiny,
                       bg="#1a1a2e", fg="#c9a44c", selectcolor="#1a1a2e",
                       font=("Segoe UI", 9, "bold"), activebackground="#1a1a2e", activeforeground="#c9a44c",
                       command=lambda: self._render_card_gallery()).pack(side=tk.LEFT, padx=(10,3))

        tk.Button(tb, text="📋 Table", bg="#7f8c8d", fg="white", font=("Segoe UI", 9),
                  relief=tk.FLAT, padx=10, pady=3,
                  command=self._toggle_card_view).pack(side=tk.RIGHT, padx=5)

        # ── Sub-tabs: Pokémon | Trainers | Items ──
        self._card_type_filter = tk.StringVar(value="Pokémon")
        sub_nb = ttk.Notebook(f)
        sub_nb.pack(fill=tk.X, padx=5, pady=(2,0))
        for label in ("Pokémon", "Trainers", "Items"):
            sf = tk.Frame(sub_nb, bg="#1a1a2e")
            sub_nb.add(sf, text=label)
        sub_nb.bind("<<NotebookTabChanged>>", lambda e: self._on_sub_tab_change(sub_nb))

        # ── Type icon filter bar ──
        self.card_type_var = tk.StringVar(value="All")
        type_bar = tk.Frame(f, bg="#1a1a2e")
        type_bar.pack(fill=tk.X, padx=10, pady=3)
        self._type_icon_photos = []
        self._type_icon_labels = {}
        self._selected_type_icon = None

        # "All" clear button
        all_btn = tk.Label(type_bar, text="ALL", fg="#ccc", bg="#333", font=("Segoe UI", 8, "bold"),
                           width=5, cursor="hand2")
        all_btn.pack(side=tk.LEFT, padx=1)
        all_btn.bind("<Button-1>", lambda e: self._select_type_icon(None))

        for aff in self.AFFINITY_BG_INDEX:
            if HAS_PIL and aff in self._card_assets.get("types", {}):
                ti = self._card_assets["types"][aff].resize((22, 22), Image.NEAREST)
                photo = ImageTk.PhotoImage(ti)
                self._type_icon_photos.append(photo)
                lbl = tk.Label(type_bar, image=photo, bg="#1a1a2e", cursor="hand2",
                               relief=tk.FLAT, bd=1)
                lbl.image = photo
                lbl.pack(side=tk.LEFT, padx=1)
                lbl.bind("<Button-1>", lambda e, a=aff: self._select_type_icon(a))
                self._type_icon_labels[aff] = lbl
            else:
                lbl = tk.Label(type_bar, text=aff[:3].title(), fg="#aaa", bg="#1a1a2e",
                               font=("Segoe UI", 7), width=5, cursor="hand2")
                lbl.pack(side=tk.LEFT, padx=1)
                lbl.bind("<Button-1>", lambda e, a=aff: self._select_type_icon(a))
                self._type_icon_labels[aff] = lbl

        # ── Scrollable canvas for gallery ──
        self._card_view_mode = "gallery"
        self._card_canvas_frame = tk.Frame(f, bg="#1a1a2e")
        self._card_canvas_frame.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)

        self.card_canvas = tk.Canvas(self._card_canvas_frame, bg="#0d1117", highlightthickness=0)
        self.card_scrollbar = ttk.Scrollbar(self._card_canvas_frame, orient=tk.VERTICAL, command=self.card_canvas.yview)
        self.card_scrollable = tk.Frame(self.card_canvas, bg="#0d1117")
        self.card_scrollable.bind("<Configure>", lambda e: self.card_canvas.configure(scrollregion=self.card_canvas.bbox("all")))
        self.card_canvas.create_window((0,0), window=self.card_scrollable, anchor="nw")
        self.card_canvas.configure(yscrollcommand=self.card_scrollbar.set)
        self.card_canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.card_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        # Mouse wheel scrolling
        def _mw(e):
            self.card_canvas.yview_scroll(int(-1*(e.delta/120)), "units")
        self.card_canvas.bind("<Enter>", lambda e: self.card_canvas.bind_all("<MouseWheel>", _mw))
        self.card_canvas.bind("<Leave>", lambda e: self.card_canvas.unbind_all("<MouseWheel>"))

        # Hidden table view
        self._card_table_frame = tk.Frame(f, bg="#1a1a2e")
        cols = ("#","Name","Rarity","Type","N","S","E","W","Worth","Card#","Starter","Holo","Evolves","ID")
        widths = (30,110,65,55,28,28,28,28,50,40,40,35,110,150)
        self.card_table_tv = ttk.Treeview(self._card_table_frame, columns=cols, show="headings", height=14)
        for c, w in zip(cols, widths):
            self.card_table_tv.heading(c, text=c, command=lambda col=c: self._sort_card_db(col))
            self.card_table_tv.column(c, width=w, minwidth=25)
        tv_sb = ttk.Scrollbar(self._card_table_frame, orient=tk.VERTICAL, command=self.card_table_tv.yview)
        self.card_table_tv.configure(yscrollcommand=tv_sb.set)
        self.card_table_tv.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        tv_sb.pack(side=tk.RIGHT, fill=tk.Y)
        self.card_table_tv.bind("<Double-1>", lambda e: self._preview_card_detail())

        self._tv["card_db"] = {"tv": self.card_table_tv, "info": {"columns": cols}}
        self._card_gallery_photos = []
        self._render_card_gallery()

    def _on_sub_tab_change(self, nb):
        idx = nb.index(nb.select())
        labels = ("Pokémon", "Trainers", "Items")
        if idx < len(labels):
            self._card_type_filter.set(labels[idx])
            self._render_card_gallery()

    def _select_type_icon(self, affinity):
        """Toggle type filter: click icon to select, click again or ALL to clear."""
        current = self.card_type_var.get()
        if affinity is None:
            self.card_type_var.set("All")
            # Reset all borders
            for lbl in self._type_icon_labels.values():
                lbl.configure(bg="#1a1a2e", bd=1, relief=tk.FLAT)
        elif current == affinity:
            self.card_type_var.set("All")
            self._type_icon_labels[affinity].configure(bg="#1a1a2e", bd=1, relief=tk.FLAT)
        else:
            # Reset previous
            for lbl in self._type_icon_labels.values():
                lbl.configure(bg="#1a1a2e", bd=1, relief=tk.FLAT)
            self.card_type_var.set(affinity)
            self._type_icon_labels[affinity].configure(bg="#c9a44c", bd=2, relief=tk.SOLID)
        self._render_card_gallery()

    def _toggle_card_view(self):
        if self._card_view_mode == "gallery":
            self._card_canvas_frame.pack_forget()
            self._card_table_frame.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
            self._card_view_mode = "table"
            self._filter_card_table()
        else:
            self._card_table_frame.pack_forget()
            self._card_canvas_frame.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
            self._card_view_mode = "gallery"
            self._render_card_gallery()

    def _filter_card_table(self):
        tv = self._tv["card_db"]["tv"]
        tv.delete(*tv.get_children())
        filt = self.card_filter_entry.get().lower()
        rarity = self.card_rarity_var.get()
        ctype = self.card_type_var.get()
        card_type_filter = getattr(self, '_card_type_filter', tk.StringVar(value="All")).get()
        # Build filtered list
        filtered = []
        for c in self._cards_data:
            if rarity != "All" and c.get("rarity") != rarity: continue
            if ctype != "All" and c.get("affinity") != ctype: continue
            if card_type_filter != "All":
                ct = c.get("cardType","pokemon")
                if card_type_filter == "Pokémon" and ct != "pokemon": continue
                if card_type_filter == "Trainers" and ct != "trainer": continue
                if card_type_filter == "Items" and ct != "item": continue
            if filt:
                if not (filt in c.get("name","").lower() or filt in c.get("id","").lower() or filt in c.get("affinity","").lower()):
                    continue
            filtered.append(c)
        # Sort by cardNumber
        def _sk(card):
            cn = card.get("cardNumber","")
            if cn and cn[0].isalpha(): return (9999, cn)
            parts = cn.replace("-",".").split(".")
            nums = [int(p) for p in parts if p.isdigit()] or [0]
            while len(nums) < 2: nums.append(0)
            return (nums[0], nums[1], cn)
        filtered.sort(key=_sk)
        for i, c in enumerate(filtered):
            v = c.get("values",{})
            tv.insert("", tk.END, values=(
                i+1, c.get("name",""), c.get("rarity",""), c.get("affinity",""),
                v.get("north",""), v.get("south",""), v.get("east",""), v.get("west",""),
                c.get("worth",""), c.get("cardNumber",""),
                "⭐" if c.get("isStarter") else "", "✨" if c.get("holo") else "",
                c.get("evolvesTo",""), c.get("id","")))

    def _render_card_gallery(self):
        if self._card_view_mode != "gallery":
            return
        for w in self.card_scrollable.winfo_children():
            w.destroy()
        self._card_gallery_photos.clear()

        if not HAS_PIL or "error" in self._card_assets:
            tk.Label(self.card_scrollable, text="Install Pillow: pip install Pillow",
                     fg="#e74c3c", bg="#0d1117", font=("Segoe UI",12)).pack(pady=40)
            return

        filt = self.card_filter_entry.get().lower()
        rarity = self.card_rarity_var.get()
        ctype = self.card_type_var.get()
        card_type_filter = getattr(self, '_card_type_filter', tk.StringVar(value="All")).get()
        filtered = []
        for c in self._cards_data:
            if rarity != "All" and c.get("rarity") != rarity: continue
            if ctype != "All" and c.get("affinity") != ctype: continue
            if card_type_filter != "All":
                ct = c.get("cardType","pokemon")
                if card_type_filter == "Pokémon" and ct != "pokemon": continue
                if card_type_filter == "Trainers" and ct != "trainer": continue
                if card_type_filter == "Items" and ct != "item": continue
            if filt:
                nm = c.get("name","").lower()
                cid = c.get("id","").lower()
                aff = c.get("affinity","").lower()
                if not (filt in nm or filt in cid or filt in aff): continue
            filtered.append(c)

        if not filtered:
            tk.Label(self.card_scrollable, text="No cards match",
                     fg="#999", bg="#0d1117", font=("Segoe UI",12)).pack(pady=40)
            return

        # Sort by cardNumber: "001", "001-1", "002", "T01", etc.
        def _sort_key(card):
            cn = card.get("cardNumber","")
            # Handle trainer/item prefixes: T01 → put after all numeric cards
            if cn and cn[0].isalpha():
                return (9999, cn)
            # "001-1" → (1, 1), "001" → (1, 0)
            parts = cn.replace("-", ".").split(".")
            nums = []
            for p in parts:
                try: nums.append(int(p))
                except: nums.append(0)
            while len(nums) < 2: nums.append(0)
            return (nums[0], nums[1], cn)
        filtered.sort(key=_sort_key)

        # Square cards: exact game resolution 128×128
        S = 128
        PAD = 2
        cw = self.card_canvas.winfo_width()
        COLS = max(1, (cw - 20) // (S + PAD*2)) if cw > 50 else 6
        base = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

        row_frame = None
        for idx, card in enumerate(filtered):
            col = idx % COLS
            if col == 0:
                row_frame = tk.Frame(self.card_scrollable, bg="#0d1117")
                row_frame.pack(fill=tk.X, padx=PAD, pady=1)
            try:
                card_img = self._paint_card_game(card, S, base)
                if card_img:
                    photo = ImageTk.PhotoImage(card_img)
                    self._card_gallery_photos.append(photo)
                    lbl = tk.Label(row_frame, image=photo, bg="#0d1117", cursor="hand2", relief=tk.FLAT, bd=0)
                    lbl.image = photo
                    lbl.pack(side=tk.LEFT, padx=PAD, pady=PAD)
                    lbl.bind("<Button-1>", lambda e, c=card: self._preview_card_detail(c))
            except Exception as ex:
                pass

        self.card_canvas.configure(scrollregion=self.card_canvas.bbox("all"))

    def _paint_card_game(self, card, S, base):
        """Render card exactly like the game's paintTriadCardFace()."""
        from PIL import ImageDraw, ImageFont
        affinity = card.get("affinity","normal")
        rarity = card.get("rarity","common")
        holo = card.get("holo", False)
        v = card.get("values",{})
        name = card.get("name","")

        # ── 1. Card background from spritesheet ──
        col_idx = self.AFFINITY_BG_INDEX.get(affinity, 0)
        card_bg = self._card_assets.get("card_bg")
        if card_bg:
            # card_bg is 2304×128, each cell is 128×128
            cell = card_bg.crop((col_idx * 128, 0, col_idx * 128 + 128, 128))
            bg = cell.resize((S, S), Image.NEAREST).convert("RGBA")
        else:
            bg = Image.new("RGBA", (S, S), "#333333")

        # ── 2. Artwork (use card.image path exactly like game) ──
        image_rel = card.get("image", "")  # e.g. "assets/pokemon/BULBASAUR.png"
        species_id = card.get("speciesId","").upper()
        shiny_mode = getattr(self, '_show_shiny', tk.BooleanVar(value=False)).get()
        sprite = None

        def _try_load(path):
            if os.path.exists(path):
                try: return Image.open(path).convert("RGBA")
                except: pass
            return None

        # Only Pokémon cards have shiny variants
        if shiny_mode and card.get("cardType","pokemon") == "pokemon":
            # Try card.image → shiny folder
            sprite = _try_load(os.path.join(base,
                image_rel.replace("assets/pokemon/", "assets/pokemon_shiny/").replace("/", os.sep)))
            # Try speciesId → shiny folder (handles naming mismatches like UNOWN_EX→UNOWN_!)
            if not sprite and species_id:
                sprite = _try_load(os.path.join(base, "assets", "pokemon_shiny", f"{species_id}.png"))

        # Regular fallbacks
        if not sprite and image_rel:
            sprite = _try_load(os.path.join(base, image_rel.replace("/", os.sep)))
        if not sprite and species_id:
            sprite = _try_load(os.path.join(base, "assets", "pokemon", f"{species_id}.png"))
        if sprite:
            # Crop from center to square, then scale to fill card
            sw, sh = sprite.size
            sq = min(sw, sh)
            cx, cy = (sw - sq)//2, (sh - sq)//2
            sprite = sprite.crop((cx, cy, cx+sq, cy+sq))
            sprite = sprite.resize((S, S), Image.NEAREST)
            bg.paste(sprite, (0, 0), sprite)

        draw = ImageDraw.Draw(bg)

        # ── 3. Numbers (N/S/E/W) no dropshadow ──
        num_sheet = self._card_assets.get("numbers")
        # Game positions in 128-space, scaled to S
        scale = S / 128.0
        # positions from game: North(7+12,7) West(7,7+12) East(7+24,7+12) South(7+12,7+24)
        num_positions = {
            "N": (int((7+12)*scale), int(7*scale), v.get("north",0)),
            "W": (int(7*scale), int((7+12)*scale), v.get("west",0)),
            "E": (int((7+24)*scale), int((7+12)*scale), v.get("east",0)),
            "S": (int((7+12)*scale), int((7+24)*scale), v.get("south",0)),
        }
        num_cell = int(16 * scale)  # each number cell is 16px source
        if num_sheet and num_cell >= 4:
            for side, (nx, ny, val) in num_positions.items():
                val_str = str(val)
                for di, ch in enumerate(val_str):
                    digit = int(ch)
                    sx = digit * 16
                    sy = 0  # row 0 = white numbers
                    try:
                        glyph = num_sheet.crop((sx, sy, sx+16, sy+16)).resize((num_cell, num_cell), Image.NEAREST)
                        bg.paste(glyph, (nx + di*num_cell, ny), glyph)
                    except:
                        pass

        # ── 4. Type icon (top-right corner, aspect-ratio fit, game-accurate dropshadow) ──
        type_icons = self._card_assets.get("types",{})
        if affinity in type_icons:
            box_w = int(22 * scale)
            box_h = int(36 * scale)
            ti_x = S - box_w - int(7 * scale)
            ti_y = int(7 * scale)
            ti_raw = type_icons[affinity]
            # Fit inside box preserving aspect ratio (letterboxing)
            ti_w, ti_h = ti_raw.size
            scale_fit = min(box_w / ti_w, box_h / ti_h)
            fit_w, fit_h = int(ti_w * scale_fit), int(ti_h * scale_fit)
            ti = ti_raw.resize((fit_w, fit_h), Image.NEAREST)
            # Center in box
            offset_x = (box_w - fit_w) // 2
            offset_y = (box_h - fit_h) // 2
            # Dropshadow: matches game's paintTriadCardFace — full box at +2,+2
            # canvas.drawRect(Rect.fromLTWH(ti_x+2, ti_y+2, box_w, box_h), Paint()..color=Color(0x66000000))
            shadow = Image.new("RGBA", (box_w, box_h), (0,0,0,102))
            bg.paste(shadow, (ti_x + 2, ti_y + 2), shadow)
            bg.paste(ti, (ti_x + offset_x, ti_y + offset_y), ti)

        # ── 5. Rarity frame (topmost) ──
        if holo:
            frame_key = "frame_holo"
        else:
            frame_key = f"frame_{rarity}" if f"frame_{rarity}" in self._card_assets else "frame_common"
        frame_img = self._card_assets.get(frame_key)
        if frame_img:
            frm = frame_img.resize((S, S), Image.NEAREST).convert("RGBA")
            bg.paste(frm, (0, 0), frm)

        # ── 6. Rounded corners ──
        r = int(S * 0.08)
        mask = Image.new("L", (S, S), 0)
        md = ImageDraw.Draw(mask)
        md.rounded_rectangle([(0,0),(S-1,S-1)], radius=r, fill=255)
        bg.putalpha(mask)

        return bg

    def _preview_card_detail(self, card_obj=None):
        if card_obj is None:
            tv = self._tv["card_db"]["tv"]
            sel = tv.selection()
            if not sel: return
            row = tv.item(sel[0])["values"]
            cid = row[13]
            for c in self._cards_data:
                if c["id"] == cid: card_obj = c; break
        if not card_obj: return
        if not HAS_PIL:
            messagebox.showinfo("Card", json.dumps(card_obj, indent=2))
            return

        base = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        S = 384  # 3x game size
        card_img = self._paint_card_game(card_obj, S, base)
        if not card_img: return

        d = tk.Toplevel(self.root)
        d.title(card_obj.get("name",""))
        d.configure(bg="#0d1117")
        photo = ImageTk.PhotoImage(card_img)
        lbl = tk.Label(d, image=photo, bg="#0d1117")
        lbl.image = photo
        lbl.pack(padx=15, pady=15)

        info = f"{card_obj.get('name','')}  |  #{card_obj.get('cardNumber','')}  |  {card_obj.get('rarity','').title()}  |  {card_obj.get('affinity','')}"
        tk.Label(d, text=info, fg="#c9a44c", bg="#0d1117", font=("Segoe UI",12,"bold")).pack(pady=(0,2))
        v = card_obj.get("values",{})
        tk.Label(d, text=f"N:{v.get('north','')}  S:{v.get('south','')}  E:{v.get('east','')}  W:{v.get('west','')}  |  ₽{card_obj.get('worth','')}",
                 fg="#ccc", bg="#0d1117", font=("Segoe UI",11)).pack(pady=(0,2))
        extras = []
        if card_obj.get("isStarter"): extras.append("⭐ Starter")
        if card_obj.get("holo"): extras.append("✨ Holo")
        if card_obj.get("evolvesTo"): extras.append(f"→ {card_obj['evolvesTo']}")
        if extras: tk.Label(d, text="  ".join(extras), fg="#f39c12", bg="#0d1117", font=("Segoe UI",10)).pack(pady=(0,5))
        tk.Label(d, text=card_obj.get("id",""), fg="#555", bg="#0d1117", font=("Consolas",9)).pack(pady=(0,10))
        tk.Button(d, text="Close", bg="#e74c3c", fg="white", font=("Segoe UI",10),
                  relief=tk.FLAT, padx=20, pady=5, command=d.destroy).pack(pady=(0,10))

    def _sort_card_db(self, col):
        idx = {"#":0,"Name":1,"Rarity":2,"Type":3,"N":4,"S":5,"E":6,"W":7,"Worth":8,"Card#":9,"Starter":10,"Holo":11,"Evolves":12,"ID":13}[col]
        tv = self._tv["card_db"]["tv"]
        rows = [(tv.set(item, col), item) for item in tv.get_children("")]
        try:
            rows.sort(key=lambda x: int(x[0]) if x[0].isdigit() else x[0].lower())
        except:
            rows.sort(key=lambda x: str(x[0]).lower())
        for i, (_, item) in enumerate(rows):
            tv.move(item, "", i)

    # ── TAB: Sets (local sets.json) ────────────────────────────────────
    def _tab_sets(self, nb):
        f = tk.Frame(nb, bg="#1a1a2e")
        nb.add(f, text="📦 Sets")

        set_path = os.path.join(os.path.dirname(__file__), "..", "assets", "data", "sets.json")
        self._sets_data = []
        try:
            with open(set_path, "r") as fh:
                self._sets_data = json.load(fh).get("sets", [])
        except Exception as e:
            tk.Label(f, text=f"Failed to load sets.json: {e}", fg="#e74c3c", bg="#1a1a2e",
                     font=("Segoe UI", 11)).pack(pady=30)
            return

        # Build card lookup from cards.json (loaded in _tab_card_db)
        card_path = os.path.join(os.path.dirname(__file__), "..", "assets", "data", "cards.json")
        self._card_lookup = {}
        try:
            with open(card_path, "r") as fh:
                for c in json.load(fh).get("cards", []):
                    self._card_lookup[c["id"]] = c
        except:
            pass

        tk.Label(f, text=f"{len(self._sets_data)} sets loaded", fg="#2ecc71", bg="#1a1a2e",
                 font=("Segoe UI", 10)).pack(pady=5)

        # Main set list (top half)
        pf = tk.Frame(f, bg="#1a1a2e")
        pf.pack(fill=tk.BOTH, expand=True, padx=10, pady=5)

        sets_cols = ("Set ID", "Name", "Description", "Cards")
        sets_widths = (150, 200, 350, 60)
        self.sets_tv = ttk.Treeview(pf, columns=sets_cols, show="headings", height=8)
        for c, w in zip(sets_cols, sets_widths):
            self.sets_tv.heading(c, text=c)
            self.sets_tv.column(c, width=w, minwidth=40)
        sets_sb = ttk.Scrollbar(pf, orient=tk.VERTICAL, command=self.sets_tv.yview)
        self.sets_tv.configure(yscrollcommand=sets_sb.set)
        self.sets_tv.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        sets_sb.pack(side=tk.RIGHT, fill=tk.Y)

        for s in self._sets_data:
            self.sets_tv.insert("", tk.END, values=(
                s.get("id",""), s.get("name",""), s.get("description",""),
                len(s.get("cardIds",[]))
            ))

        self.sets_tv.bind("<<TreeviewSelect>>", self._on_set_selected)

        # Card list for selected set (bottom half)
        tk.Label(f, text="Cards in selected set:", fg="#ccc", bg="#1a1a2e",
                 font=("Segoe UI", 10, "bold")).pack(anchor="w", padx=15)

        cf = tk.Frame(f, bg="#1a1a2e")
        cf.pack(fill=tk.BOTH, expand=True, padx=10, pady=(0,10))

        card_cols = ("Card ID", "Name", "Rarity", "Affinity", "N", "S", "E", "W", "Worth")
        card_widths = (160, 120, 70, 60, 30, 30, 30, 30, 50)
        self.set_cards_tv = ttk.Treeview(cf, columns=card_cols, show="headings", height=8)
        for c, w in zip(card_cols, card_widths):
            self.set_cards_tv.heading(c, text=c)
            self.set_cards_tv.column(c, width=w, minwidth=30)
        card_sb = ttk.Scrollbar(cf, orient=tk.VERTICAL, command=self.set_cards_tv.yview)
        self.set_cards_tv.configure(yscrollcommand=card_sb.set)
        self.set_cards_tv.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        card_sb.pack(side=tk.RIGHT, fill=tk.Y)

    def _on_set_selected(self, event):
        sel = self.sets_tv.selection()
        if not sel:
            return
        set_id = self.sets_tv.item(sel[0])["values"][0]
        self.set_cards_tv.delete(*self.set_cards_tv.get_children())

        # Find set
        card_ids = []
        for s in self._sets_data:
            if s["id"] == set_id:
                card_ids = s.get("cardIds", [])
                break

        for cid in card_ids:
            card = self._card_lookup.get(cid, {})
            v = card.get("values", {})
            self.set_cards_tv.insert("", tk.END, values=(
                cid,
                card.get("name",""),
                card.get("rarity",""),
                card.get("affinity",""),
                v.get("north",""),
                v.get("south",""),
                v.get("east",""),
                v.get("west",""),
                card.get("worth","")
            ))

    # ── TAB: Logs ──────────────────────────────────────────────────────
    def _tab_logs(self, nb):
        f = tk.Frame(nb, bg="#1a1a2e")
        nb.add(f, text="📜 Logs")

        self.log_text = scrolledtext.ScrolledText(f, bg="#0d1117", fg="#eee",
            font=("Consolas", 10), height=25)
        self.log_text.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        bf = tk.Frame(f, bg="#1a1a2e")
        bf.pack(pady=5)
        for lbl, lines in [("Tail (40)", "40"), ("Full (200)", "200"), ("Errors", "ERR")]:
            cmd = f"tail -{lines} /tmp/api.log" if lines != "ERR" else "grep -i 'error\\|traceback\\|exception' /tmp/api.log | tail -50"
            tk.Button(bf, text=f"📄 {lbl}", bg="#7f8c8d", fg="white", font=("Segoe UI", 10),
                      relief=tk.FLAT, padx=14, pady=4,
                      command=lambda c=cmd: threading.Thread(target=lambda: self._show_logs(c), daemon=True).start()
                      ).pack(side=tk.LEFT, padx=5)

        tk.Button(bf, text="🔁 Clear Log", bg="#c0392b", fg="white", font=("Segoe UI", 10),
                  relief=tk.FLAT, padx=14, pady=4,
                  command=lambda: self._run("> /tmp/api.log")).pack(side=tk.LEFT, padx=5)

    def _show_logs(self, cmd):
        r = self._run(cmd)
        self.log_text.delete(1.0, tk.END)
        if r:
            self.log_text.insert(tk.END, r)

    # ── Reusable Data Tab Builder ──────────────────────────────────────
    def __init_data_tabs(self):
        if not hasattr(self, "_tv"):
            self._tv = {}

    def _data_tab(self, parent, key, query, columns, widths, *, db_cols=None, edit_table=None, edit_where=None,
                  edit_fields=None, delete_table=None, delete_where=None, delete_msg=""):
        self.__init_data_tabs()

        # Toolbar
        tb = tk.Frame(parent, bg="#1a1a2e")
        tb.pack(fill=tk.X, padx=10, pady=(5,0))

        info = {}
        info["query"] = query
        info["columns"] = columns
        info["db_cols"] = db_cols or columns  # actual SQL column names, defaults to display names
        info["edit_table"] = edit_table
        info["edit_where"] = edit_where
        info["edit_fields"] = edit_fields
        info["delete_table"] = delete_table
        info["delete_where"] = delete_where
        info["delete_msg"] = delete_msg

        tk.Button(tb, text="🔄 Refresh", bg="#3498db", fg="white", font=("Segoe UI", 10),
                  relief=tk.FLAT, padx=14, pady=3,
                  command=lambda: threading.Thread(target=lambda: self._refresh_tree(key), daemon=True).start()
                  ).pack(side=tk.LEFT, padx=3)

        if edit_table:
            tk.Button(tb, text="✏️ Edit Selected", bg="#f39c12", fg="white", font=("Segoe UI", 10),
                      relief=tk.FLAT, padx=14, pady=3,
                      command=lambda: self._edit_row(key)).pack(side=tk.LEFT, padx=3)

        tk.Button(tb, text="🗑 Delete Selected", bg="#e74c3c", fg="white", font=("Segoe UI", 10),
                  relief=tk.FLAT, padx=14, pady=3,
                  command=lambda: self._delete_row(key)).pack(side=tk.LEFT, padx=3)

        # Treeview
        frame = tk.Frame(parent, bg="#1a1a2e")
        frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=5)

        tv = ttk.Treeview(frame, columns=columns, show="headings", height=12)
        for col, w in zip(columns, widths):
            tv.heading(col, text=col)
            tv.column(col, width=w, minwidth=30)

        sb = ttk.Scrollbar(frame, orient=tk.VERTICAL, command=tv.yview)
        tv.configure(yscrollcommand=sb.set)
        tv.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        sb.pack(side=tk.RIGHT, fill=tk.Y)

        # Double-click to edit
        if edit_table:
            tv.bind("<Double-1>", lambda e: self._edit_row(key))

        self._tv[key] = {"tv": tv, "info": info}

        # Initial load
        threading.Thread(target=lambda: self._populate_tree(key), daemon=True).start()

    def _populate_tree(self, key, custom_query=None):
        info = self._tv[key]["info"]
        tv = self._tv[key]["tv"]
        if "query" not in info:
            return
        q = custom_query or info["query"]
        rows = self._db(q)
        try:
            self.root.after(0, lambda: tv.delete(*tv.get_children()))
        except RuntimeError:
            return
        if isinstance(rows, list):
            db_cols = info["db_cols"]
            for row in rows:
                vals = [row.get(c, "") for c in db_cols]
                try:
                    self.root.after(0, lambda v=vals, t=tv: t.insert("", tk.END, values=v))
                except RuntimeError:
                    return

    def _refresh_tree(self, key):
        if "query" not in self._tv[key]["info"]:
            return  # non-SQL tab, skip
        self._tv[key]["tv"].delete(*self._tv[key]["tv"].get_children())
        self._populate_tree(key)

    def _get_selected(self, key):
        tv = self._tv[key]["tv"]
        sel = tv.selection()
        if not sel:
            messagebox.showwarning("None Selected", "Select a row first.")
            return None
        return tv.item(sel[0])["values"]

    def _edit_row(self, key):
        row = self._get_selected(key)
        if not row:
            return
        info = self._tv[key]["info"]
        pk_val = row[0]  # first column = primary key
        pk_col = info["edit_where"]
        table = info["edit_table"]
        fields = info["edit_fields"]
        cols = info["columns"]

        # Build edit dialog
        d = tk.Toplevel(self.root)
        d.title(f"Edit {table}")
        d.configure(bg="#16213e")
        d.geometry("420x350")

        db_cols = info.get("db_cols", cols)
        entries = {}
        for i, fld in enumerate(fields):
            frm = tk.Frame(d, bg="#16213e")
            frm.pack(fill=tk.X, padx=15, pady=3)
            tk.Label(frm, text=fld, fg="#ccc", bg="#16213e", font=("Consolas", 10), width=20, anchor="e").pack(side=tk.LEFT, padx=5)
            e = tk.Entry(frm, bg="#0d1117", fg="#eee", insertbackground="#eee", font=("Consolas", 10))
            e.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5)
            # Find value: match field name against db_cols to get the index
            val = ""
            for j, c in enumerate(db_cols):
                if c == fld:
                    val = str(row[j]) if row[j] is not None else ""
                    break
            e.insert(0, val)
            entries[fld] = e

        def save():
            sets = []
            for fld, e in entries.items():
                v = e.get().strip()
                if v.isdigit() or (v.startswith("-") and v[1:].isdigit()):
                    sets.append(f"{fld}={v}")
                else:
                    sets.append(f"{fld}='{v}'")
            sql = f"UPDATE {table} SET {', '.join(sets)} WHERE {pk_col}={pk_val}"
            r = self._run(f"mysql -u {DB_USER} -p{DB_PASS} -h 127.0.0.1 {DB_NAME} -e \"{sql}\" 2>&1")
            if r and "ERROR" in r:
                messagebox.showerror("Error", r, parent=d)
            else:
                messagebox.showinfo("Saved", "Record updated.", parent=d)
                d.destroy()
                self._refresh_tree(key)

        tk.Button(d, text="💾 Save", bg="#2ecc71", fg="white", font=("Segoe UI", 11, "bold"),
                  relief=tk.FLAT, padx=20, pady=6, command=save).pack(pady=15)

    def _delete_row(self, key):
        row = self._get_selected(key)
        if not row:
            return
        info = self._tv[key]["info"]
        pk_val = row[0]
        table = info["delete_table"]
        where = info["delete_where"]
        msg = info["delete_msg"]

        if not messagebox.askyesno("Confirm Delete", f"{msg}\n\n{table} {where}={pk_val}"):
            return

        sql = f"DELETE FROM {table} WHERE {where}={pk_val}"
        r = self._run(f"mysql -u {DB_USER} -p{DB_PASS} -h 127.0.0.1 {DB_NAME} -e \"{sql}\" 2>&1")
        if r and "ERROR" in r:
            messagebox.showerror("Error", r)
        else:
            self._refresh_tree(key)

    def _on_tab_change(self, event):
        nb = event.widget
        idx = nb.index(nb.select())
        tabs = ["dashboard", "players", "cards", "gifts", "story", "decks", "card_db", "sets", "logs"]
        if idx < len(tabs):
            key = tabs[idx]
            if key in getattr(self, "_tv", {}):
                if key == "card_db":
                    self._render_card_gallery()
                elif key != "sets":
                    threading.Thread(target=lambda: self._refresh_tree(key), daemon=True).start()
            elif key == "dashboard":
                threading.Thread(target=self._refresh_dashboard, daemon=True).start()
            elif key == "logs":
                threading.Thread(target=lambda: self._show_logs("tail -40 /tmp/api.log"), daemon=True).start()

if __name__ == "__main__":
    App()
