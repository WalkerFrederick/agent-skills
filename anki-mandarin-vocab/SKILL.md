---
name: anki-mandarin-vocab
description: 'Add Mandarin vocabulary notes to Anki. Use when: user provides hanzi/pinyin/English words to add to the Mandarin vocab decks, asks to add words to Anki, or wants new vocab cards created. Each note generates both a Pinyin→English and English→Pinyin card. Generates example sentences reusing known vocabulary. Requires Anki to be closed (direct SQLite DB edit).'
---

# Add Mandarin Vocabulary to Anki

## Goal

Add new Mandarin vocabulary notes to the user's Anki collection. Each note produces exactly **two cards**:
- Template ord 0 → deck `Mandarin::Pinyin → English` (did 1787160042420)
- Template ord 1 → deck `Mandarin::English → Pinyin` (did 1787621977420)

## Critical Constraints

- **Anki must be closed** before touching the DB. If Anki is running, quit it first (`osascript -e 'quit app "Anki"'`, verify with `pgrep -f Anki.app`; if it lingers, `kill <pid>`). Reopen with `open -a Anki` when done.
- Never edit the DB while Anki is open — you'll get `database is locked` or worse.
- The collection lives at `~/Library/Application Support/Anki2/User 1/collection.anki2`.

## Step 0: Check Last Sync

Before making any changes, check the last sync time and warn the user if it's stale:

```python
import sqlite3, datetime
c = sqlite3.connect(db)
ls, mod = c.execute("SELECT ls, mod FROM col").fetchone()
ls_dt = datetime.datetime.fromtimestamp(ls/1000) if ls else None
mod_dt = datetime.datetime.fromtimestamp(mod)
```

- `col.ls` = last sync timestamp (ms). `col.mod` = last collection modification (ms).
- If last sync is **more than 3 days ago**, or `mod` is much newer than `ls` (large unsynced changes), remind the user to sync Anki before/after adding words. Just a one-line reminder; don't block the workflow.
- Report the sync time in the final summary (e.g. "Last sync: 2026-09-17 19:39 — consider syncing after this change").

## Step 1: Backup (Required Before Any Insert)

Before inserting anything, copy the collection to a timestamped backup so any run can be reverted:

```bash
mkdir -p "~/Library/Application Support/Anki2/User 1/pre-skill-backup"
cp "~/Library/Application Support/Anki2/User 1/collection.anki2" \
   "~/Library/Application Support/Anki2/User 1/pre-skill-backup/collection-$(date +%Y-%m-%d@%H-%M-%S).anki2"
```

Better as Python (handles the space in the path and WAL checkpoint):

```python
import shutil, subprocess, os, datetime
db = '/Users/walkerfrederick/Library/Application Support/Anki2/User 1/collection.anki2'
bdir = os.path.join(os.path.dirname(db), 'pre-skill-backup')
os.makedirs(bdir, exist_ok=True)
# checkpoint WAL so the backup is complete
subprocess.run(['sqlite3', db, 'PRAGMA wal_checkpoint(TRUNCATE);'], check=False)
ts = datetime.datetime.now().strftime('%Y-%m-%d@%H-%M-%S')
bpath = os.path.join(bdir, f'collection-{ts}.anki2')
shutil.copy2(db, bpath)
print('backup:', bpath)
```

Rules:
- One backup per run, taken **after** closing Anki and **before** the first insert.
- Keep only the most recent 5 backups; delete older ones after a successful insert.
- Tell the user the backup path in the final summary so a revert is easy.

## Revert Procedure (if user asks to undo)

1. Quit Anki.
2. Restore: `cp <backup path> "~/Library/Application Support/Anki2/User 1/collection.anki2"` and delete the `-wal`/`-shm` files next to it.
3. Reopen Anki.
4. Note: any reviews done after the backup will be lost too — warn the user before restoring. If only the last run's words need removing, prefer deleting those specific notes (by the `added::` tag) instead of a full restore.

## Step 2: Parse User Input

The user provides words in any combination of:
- hanzi + pinyin + meaning (complete)
- hanzi only (look up pinyin and meaning yourself; use tone-marked pinyin)
- pinyin + meaning only (look up hanzi)
- pinyin only (look up hanzi and meaning)

Rules:
- Normalize pinyin to tone-marked form (e.g. "haowan" → hǎowán).
- Meanings should be concise; keep any region notes the user gives (e.g. "Taiwan wording").
- Skip grammar patterns (like "上星期 + (一, 二, 三...)") unless the user explicitly wants them — they're not single vocab items.
- Show the user the parsed word list (hanzi/pinyin/meaning) and get confirmation **before** inserting when the input was ambiguous, more than ~20 words, or any meaning had to be guessed. If the input is clean and complete, proceed without asking.

## Step 3: Dedupe

Check existing notes before inserting. The first field (Hanzi) is the dedupe key:

```python
existing = set()
for (flds,) in c.execute("SELECT flds FROM notes"):
    parts = flds.split('\x1f')
    if parts: existing.add(parts[0].strip())
```

Report how many words are new vs. already exist, and only insert new ones.

## Step 4: Generate Example Sentences

Every note should get an example sentence in fields 9-11 (Example Sentence Pinyin 1, Example Sentence Hanzi 1, Example Sentence English Translation 1). Field order matters — see field list below.

Requirements:
- Simple sentence that naturally demonstrates the word.
- **Aim to reuse words already in the collection**, but introducing 1-2 new words in a sentence is acceptable when it makes the sentence more natural. Before writing sentences, query existing vocabulary (hanzi + pinyin) as the primary source. If the target word is rare (e.g. a place name), a minimal frame like "X 很好玩" is fine.
- Correct, natural Mandarin. Watch tone sandhi in the pinyin (e.g. yí kè, búcuò).

Known vocabulary to draw from (verified in collection): 你好，谢谢，我，你，他，她，朋友，同学，老师，学生，喜欢，想，去，要，吃，喝，看，学，说，是，有，很，不，大，小，书，猫，狗，水，茶，中国，美国，现在，今天，明天，昨天，周末，星期，时间，电影，音乐，电脑，手机，家，学校，商店，超市，银行，咖啡馆/咖啡厅，饭馆，朋友，妈妈，爸爸，哥哥，姐姐，弟弟，妹妹，作业，工作，早上，中午，晚上，晚上好，每天，通常，有时候，很少，一起，山，出去，干净，好玩，有名，周/这周/上周/下周，早上好，中午好，晚上好，晚安，回头见，明天见，周末，回家，洗澡，放假

(This list is a snapshot; prefer querying the DB for the authoritative set.)

## Step 5: Tag by Date

Tag each new note with the date added, format: `added::2026-09-18`. Do NOT add category/topic tags.

## Step 6: Insert

Note type: **Mandarin Vocabulary** (ntid `1787154020847`).

Field order (13 fields, separated by `\x1f`):
1. Hanzi
2. Pinyin
3. Meaning in English
4. Phonetic Pronunciation Notes
5. Extra Notes
6. Word Audio 1
7. Word Audio 2
8. Word Image
9. Example Sentence Audio 1
10. Example Sentence Pinyin 1
11. Example Sentence Hanzi 1
12. Example Sentence English Translation 1
13. Example Sentence Image 1

Fill fields 1, 2, 3, 10, 11, 12. Leave the rest as empty strings.

Insert template (register the `unicase` collation or queries on note tables will fail). Wrap all inserts in a single transaction so a mid-run failure doesn't leave partial data; on failure, restore from the Step 1 backup or roll back:

```python
import sqlite3, time, base64, random, hashlib
c = sqlite3.connect(db)
c.create_collation('unicase', lambda a,b: (a>b)-(a<b))
NTID = 1787154020847
DID_PINYIN = 1787160042420
DID_ENGLISH = 1787621977420
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
    c.rollback()
    raise
```

Schema gotchas (these columns are NOT NULL and required):
- `notes`: needs `csum` (sha1 of first field, first 8 hex digits as base-16 int) and `sfld` (first field)
- `cards`: column is named `left`, not `lefts`

## Step 7: Verify, Prune Backups, Reopen

1. Verify counts: both decks should have equal card counts, and each new note should have exactly 2 cards (ords 0 and 1).
2. Prune backups: keep the 5 most recent in `pre-skill-backup/`, delete older ones.
3. Reopen Anki: `open -a Anki`.
4. Report to user: number of notes added, any words skipped as duplicates, the backup path, the last sync time, and the example sentences used (so they can sanity-check them).
