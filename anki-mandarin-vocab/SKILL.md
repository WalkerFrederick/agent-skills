---
name: anki-mandarin-vocab
description: 'Add Mandarin vocabulary notes to Anki. Use when: user provides hanzi/pinyin/English words to add to the Mandarin vocab decks, asks to add words to Anki, or wants new vocab cards created. Each note generates both a Pinyin→English and English→Pinyin card. Generates example sentences reusing known vocabulary. Primary path: AnkiConnect API (Anki open). Fallback: direct SQLite edit (Anki closed, backup required).'
---

# Add Mandarin Vocabulary to Anki

## Goal

Add new Mandarin vocabulary notes to the user's Anki collection. Each note produces exactly **two cards**:
- Template ord 0 → deck `Mandarin::Pinyin → English` (did 1787160042420)
- Template ord 1 → deck `Mandarin::English → Pinyin` (did 1787621970)

Note type: **Mandarin Vocabulary** (ntid 1787154020847). Fill fields: Hanzi (1), Pinyin (2), Meaning in English (3), Example Sentence Pinyin 1 (10), Example Sentence Hanzi 1 (11), Example Sentence English Translation 1 (12). All other fields stay empty. Tag each note `added::YYYY-MM-DD` — no category/topic tags.

## Path Selection

1. **Primary — AnkiConnect API** (`http://127.0.0.1:8765`). Use when Anki is running and AnkiConnect responds. Safe, no backup needed, no DB locking.
2. **Fallback — direct SQLite edit.** Use only if AnkiConnect is unavailable AND the user accepts quitting Anki. Requires Anki closed and a backup (see "Fallback: Direct DB Path" at the bottom).

Check AnkiConnect first: `curl -sS http://127.0.0.1:8765 -X POST -d '{"action":"version","version":6}'` — an `Anki-Connect`/version response means use the primary path.

## Parse User Input (both paths)

The user provides words in any combination of:
- hanzi + pinyin + meaning (complete)
- hanzi only (look up pinyin and meaning; use tone-marked pinyin)
- pinyin + meaning only (look up hanzi)
- pinyin only (look up hanzi and meaning)

Rules:
- Normalize pinyin to tone-marked form (e.g. "haowan" → hǎowán).
- Meanings should be concise; keep any region notes the user gives (e.g. "Taiwan wording").
- Skip grammar patterns (like "上星期 + (一, 二, 三...)") unless explicitly requested — not single vocab items.
- Show the user the parsed word list (hanzi/pinyin/meaning) and get confirmation **before** inserting when the input was ambiguous, more than ~20 words, or any meaning had to be guessed. Clean and complete input: proceed without asking.

## Example Sentences (both paths)

Every note gets one example sentence (fields 10-12). Requirements:
- Simple sentence that naturally demonstrates the word.
- **Aim to reuse words already in the collection**; 1-2 new words in a sentence is acceptable when it makes it more natural. Query existing vocabulary (AnkiConnect `findNotes`/`notesInfo`, or DB on the fallback path) as the primary source. If the target word is rare (e.g. a place name), a minimal frame like "X 很好玩" is fine.
- Correct, natural Mandarin. Watch tone sandhi in the pinyin (e.g. yí kè, búcuò).

Known vocabulary snapshot (prefer querying the collection for the authoritative set):
你好，谢谢，我，你，他，她，朋友，同学，老师，学生，喜欢，想，去，要，吃，喝，看，学，说，是，有，很，不，大，小，书，猫，狗，水，茶，中国，美国，现在，今天，明天，昨天，周末，星期，时间，电影，音乐，电脑，手机，家，学校，商店，超市，银行，咖啡馆/咖啡厅，饭馆，妈妈，爸爸，哥哥，姐姐，弟弟，妹妹，作业，工作，早上，中午，晚上，晚上好，每天，通常，有时候，很少，一起，山，出去，干净，好玩，有名，周/这周/上周/下周，早上好，中午好，晚安，回头见，明天见，回家，洗澡，放假

## Primary Path: AnkiConnect Workflow

AnkiConnect API basics: JSON POST to `http://127.0.0.1:8765` with `{action, version: 6, params}`; every response has `result` and `error` — always check `error`. Prefer curl + jq or Python `requests`/`urllib`.

### 1. Dedupe

First field (Hanzi) is the dedupe key. Per word:

```
{"action": "findNotes", "params": {"query": "\"note:Mandarin Vocabulary\" Hanzi:<hanzi>"}}
```

(`nc:` prefix helps when hanzi has variant forms.) Report new vs. existing counts; only add new ones. Adding a duplicate is not catastrophic (AnkiConnect duplicates are allowed) — avoid them anyway.

### 2. Pre-flight

Use `canAddNotesWithErrorDetail` with the exact payloads you'll send to catch field/model errors before committing anything.

### 3. Add notes

Add to a single deck first (cards split next step). Model must be exactly `Mandarin Vocabulary`; field names must match the model. Tag `added::<today>`:

```
{"action": "addNotes", "params": {"notes": [{
  "deckName": "Mandarin",
  "modelName": "Mandarin Vocabulary",
  "fields": {
    "Hanzi": "...", "Pinyin": "...", "Meaning in English": "...",
    "Example Sentence Pinyin 1": "...", "Example Sentence Hanzi 1": "...",
    "Example Sentence English Translation 1": "..."
  },
  "tags": ["added::2026-11-02"],
  "options": {"allowDuplicate": false}
}]}}
```

`addNotes` returns an array with note IDs (`false` per failed note — check each).

### 4. Split cards into the two decks

A new note's two cards (template ord 0 and ord 1) both land in the deck used at add time. Split them:

1. For each new note ID: `{"action": "findCards", "params": {"query": "nid:<note_id>"}}` → two card IDs.
2. `{"action": "cardsInfo", "params": {"cards": [<ids>]}}` → inspect each card's question/front: the card whose question shows the **pinyin** (asking for English) is template ord 0 → `Mandarin::Pinyin → English`; the card asking you to produce **pinyin** from English is ord 1 → `Mandarin::English → Pinyin`.
3. Move each card: `{"action": "changeDeck", "params": {"cards": [<card_id>], "deck": "Mandarin::Pinyin → English"}}` (and the other to `Mandarin::English → Pinyin`).

`changeDeck` modifies card scheduling state — per this skill's standing authorization this card-to-deck move is part of the add workflow the user asked for; still, batch all card moves under the one confirmation already given for the add.

### 5. Verify and report

- Verify: `deckNames` + per-deck counts via `findCards` (`"deck:Mandarin::Pinyin → English is:new added:<today>"`) — both decks should gain the same number of new cards.
- Report: notes added, duplicates skipped, the example sentences used (so the user can sanity-check them), and suggest running Anki sync (you can offer `{"action": "sync"}` — but never call `sync` without asking, it contacts AnkiWeb).
- If anything failed mid-run, the affected notes can be removed precisely by note ID (`deleteNotes` — confirm with the user first) — no backup/restore needed on this path.

Undo note: AnkiConnect `addNotes`/`changeDeck` are undoable from within Anki (Ctrl+Z) or via `guiUndo`.

## Fallback: Direct DB Path (only if AnkiConnect is unavailable)

**Critical constraints:**
- **Anki must be closed.** If running: `osascript -e 'quit app "Anki"'`, verify with `pgrep -f Anki.app`; if it lingers, `kill <pid>`. Reopen with `open -a Anki` when done.
- Never edit the DB while Anki is open — `database is locked` or worse.
- Collection: `~/Library/Application Support/Anki2/User 1/collection.anki2`.
- Tell the user this fallback quits Anki and edit the DB directly — get an explicit OK first.

### Sync check (fallback only)

```python
import sqlite3, datetime
c = sqlite3.connect(db)
ls, mod = c.execute("SELECT ls, mod FROM col").fetchone()
```

`col.ls` = last sync (ms), `col.mod` = last modification (ms). If last sync is **>3 days ago** or `mod` ≫ `ls`, give a one-line reminder to sync before/after — don't block.

### Backup (required, fallback only)

```python
import shutil, subprocess, os, datetime
db = '/Users/walkerfrederick/Library/Application Support/Anki2/User 1/collection.anki2'
bdir = os.path.join(os.path.dirname(db), 'pre-skill-backup')
os.makedirs(bdir, exist_ok=True)
subprocess.run(['sqlite3', db, 'PRAGMA wal_checkpoint(TRUNCATE);'], check=False)  # checkpoint WAL
ts = datetime.datetime.now().strftime('%Y-%m-%d@%H-%M-%S')
bpath = os.path.join(bdir, f'collection-{ts}.anki2')
shutil.copy2(db, bpath)
```

One backup per run, after closing Anki, before the first insert. Keep the 5 most recent in `pre-skill-backup/`; prune older ones after success. Tell the user the backup path in the summary.

Revert (if user asks to undo): quit Anki → restore the backup over `collection.anki2` and delete `-wal`/`-shm` files → reopen. Restoring also loses reviews done since the backup — warn first. Prefer deleting just the run's notes (by the `added::` tag) if only those must go.

### Dedupe (fallback)

```python
existing = set()
for (flds,) in c.execute("SELECT flds FROM notes"):
    parts = flds.split('\x1f')
    if parts: existing.add(parts[0].strip())
```

Report new vs. existing; insert only new.

### Insert (fallback)

Field order (13 fields, `\x1f`-separated): 1 Hanzi, 2 Pinyin, 3 Meaning in English, 4 Phonetic Pronunciation Notes, 5 Extra Notes, 6 Word Audio 1, 7 Word Audio 2, 8 Word Image, 9 Example Sentence Audio 1, 10 Example Sentence Pinyin 1, 11 Example Sentence Hanzi 1, 12 Example Sentence English Translation 1, 13 Example Sentence Image 1. Fill 1, 2, 3, 10, 11, 12; leave the rest empty.

```python
import sqlite3, time, base64, random, hashlib, datetime
c = sqlite3.connect(db)
c.create_collation('unicase', lambda a,b: (a>b)-(a<b))  # required or note queries fail
NTID = 1787154020847
DID_PINYIN = 1787160042420
DID_ENGLISH = 1787621970
now = int(time.time()); usn = -1
tag = 'added::' + datetime.date.today().isoformat()

def nid(): return random.randrange(1, 1<<63) & 0x7fffffffffffffff
def csum(s): return int(hashlib.sha1(s.encode('utf-8')).hexdigest()[:8], 16)

try:
    for hanzi, pinyin, meaning, sent_pinyin, sent_hanzi, sent_en in rows:
        flds = '\x1f'.join([hanzi, pinyin, meaning, '', '', '', '', '', '', sent_pinyin, sent_hanzi, sent_en, ''])
        n = nid()
        guid = base64.b64encode(random.randbytes(8)).decode().rstrip('=')
        c.execute("INSERT INTO notes (id,guid,mid,mod,usn,tags,flds,sfld,csum,flags,data) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (n, guid, NTID, now, usn, tag, flds, hanzi, csum(hanzi), 0, ''))
        for ord_, did in ((0, DID_PINYIN), (1, DID_ENGLISH)):
            c.execute("INSERT INTO cards (id,nid,did,ord,mod,usn,type,queue,due,ivl,factor,reps,lapses,left,odue,odid,flags,data) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (nid(), n, did, ord_, now, usn, 0, 0, now, 0, 0, 0, 0, 0, 0, 0, 0, ''))
    c.commit()
except Exception:
    c.rollback(); raise
```

Schema gotchas: `notes` needs `csum` (sha1 of first field, first 8 hex digits as base-16 int) and `sfld` (first field); the cards column is `left`, not `lefts`. Wrap all inserts in a single transaction.

### Verify, prune, reopen (fallback)

1. Both decks should have equal card counts; each new note has exactly 2 cards (ords 0 and 1).
2. Prune backups to the 5 most recent.
3. `open -a Anki`.
4. Report: notes added, duplicates skipped, backup path, last sync time, and the example sentences used.
