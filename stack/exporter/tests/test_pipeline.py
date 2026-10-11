import os, tempfile, unittest
from datetime import datetime, timezone
from glexport import config, main, spool, window

U = timezone.utc
def d(h, m, s=0): return datetime(2026, 10, 11, h, m, s, tzinfo=U)


class FakeClient:
    def __init__(self, data=None, fail=False, journal=0):
        self.data, self.fail, self.calls, self.journal = data or {}, fail, [], journal
    def backlog(self):
        return self.journal
    def fetch(self, start, end):
        self.calls.append((start, end))
        if self.fail: raise RuntimeError("graylog 503")
        return self.data.get(start, [])


class FakeUp:
    def __init__(self, fail=False, poison=()): self.fail, self.sent, self.poison, self.calls = fail, [], poison, 0
    def send(self, path):
        self.calls += 1
        if self.fail or os.path.basename(path) in self.poison: raise RuntimeError("oci 500")
        self.sent.append(os.path.basename(path))
        n = os.path.getsize(path)
        return {"name": os.path.basename(path), "bytes": n, "md5": "x", "remote_size": n, "remote_md5": "x", "ok": True}


def cfg(t, **kw):
    e = {"GRAYLOG_TOKEN": "tok", "STATE_DIR": t + "/state", "SPOOL_DIR": t + "/spool", "EXPORT_ENABLED": "true", "OCI_BUCKET": "b"}
    e.update(kw); os.makedirs(e["STATE_DIR"]); os.makedirs(e["SPOOL_DIR"]); return config.load(e)

def cp(c, now): return window.load_checkpoint(c.state_dir + "/checkpoint", now, 1, 720)[0]


class TestRunOnce(unittest.TestCase):
    def test_exports_nonempty_windows_only_and_advances(self):
        with tempfile.TemporaryDirectory() as t:
            c = cfg(t); window.save_checkpoint(c.state_dir + "/checkpoint", d(18, 0))
            cl = FakeClient({d(18, 0): [("2026-10-11T18:00:05.000Z", "h", "3", "m")]}); up = FakeUp()
            r = main.run_once(c, d(18, 3, 10), cl, up)
            self.assertEqual(up.sent, ["levels_0_a_3_20261011_150100.csv"])
            self.assertEqual(spool.pending(c.spool_dir), [])
            self.assertEqual(cp(c, d(18, 3, 10)), d(18, 2))
            self.assertEqual(r["windows"], 2)

    def test_graylog_failure_does_not_advance_or_create_file(self):
        with tempfile.TemporaryDirectory() as t:
            c = cfg(t); window.save_checkpoint(c.state_dir + "/checkpoint", d(18, 0))
            main.run_once(c, d(18, 3, 10), FakeClient(fail=True), FakeUp())
            self.assertEqual(spool.pending(c.spool_dir), [])
            self.assertEqual(cp(c, d(18, 3, 10)), d(18, 0))

    def test_upload_failure_keeps_file_and_retries_next_pass(self):
        with tempfile.TemporaryDirectory() as t:
            c = cfg(t); window.save_checkpoint(c.state_dir + "/checkpoint", d(18, 0))
            cl = FakeClient({d(18, 0): [("t", "h", "3", "m")]})
            main.run_once(c, d(18, 2, 10), cl, FakeUp(fail=True))
            self.assertEqual(len(spool.pending(c.spool_dir)), 1)
            up = FakeUp(); main.run_once(c, d(18, 2, 40), cl, up)
            self.assertEqual(len(up.sent), 1); self.assertEqual(spool.pending(c.spool_dir), [])

    def test_disabled_does_nothing(self):
        with tempfile.TemporaryDirectory() as t:
            c = cfg(t, EXPORT_ENABLED="false"); cl = FakeClient()
            main.run_once(c, d(18, 3), cl, FakeUp()); self.assertEqual(cl.calls, [])

    def test_orphan_tmp_in_spool_is_ignored(self):
        with tempfile.TemporaryDirectory() as t:
            c = cfg(t)
            with open(c.spool_dir + "/x.csv.tmp", "w") as f: f.write("meia")
            self.assertEqual(spool.pending(c.spool_dir), [])

    def test_crash_after_upload_before_delete_reuploads_same_name(self):
        with tempfile.TemporaryDirectory() as t:
            c = cfg(t); spool.write_atomic(c.spool_dir, "levels_0_a_3_20261011_150100.csv", "x\n")
            up = FakeUp(); main.run_once(c, d(18, 5), FakeClient(), up)      # envia e apaga
            spool.write_atomic(c.spool_dir, "levels_0_a_3_20261011_150100.csv", "x\n")  # "sobrou" apos crash
            main.run_once(c, d(18, 6), FakeClient(), up)
            self.assertEqual(up.sent, ["levels_0_a_3_20261011_150100.csv"] * 2)
            self.assertEqual(spool.pending(c.spool_dir), [])

    def test_checkpoint_reset_is_recorded_in_ledger(self):
        with tempfile.TemporaryDirectory() as t:
            c = cfg(t); main.run_once(c, d(18, 5), FakeClient(), FakeUp())
            self.assertIn("checkpoint_reset", open(c.state_dir + "/ledger.jsonl").read())


class TestBacklogAndGap(unittest.TestCase):
    def test_journal_backlog_defers_windows_without_advancing(self):
        with tempfile.TemporaryDirectory() as t:
            c = cfg(t); window.save_checkpoint(c.state_dir + "/checkpoint", d(18, 0))
            cl = FakeClient({d(18, 0): [("t", "h", "3", "m")]}, journal=10 ** 6)
            r = main.run_once(c, d(18, 3, 10), cl, FakeUp())
            self.assertEqual(cl.calls, []); self.assertEqual(cp(c, d(18, 3, 10)), d(18, 0))
            self.assertIn("atrasado", r["error"])

    def test_unknown_backlog_does_not_block_exports(self):
        with tempfile.TemporaryDirectory() as t:
            c = cfg(t); window.save_checkpoint(c.state_dir + "/checkpoint", d(18, 0))
            cl = FakeClient(journal=None); main.run_once(c, d(18, 3, 10), cl, FakeUp())
            self.assertEqual(len(cl.calls), 2)

    def test_data_gap_is_recorded_in_status(self):
        with tempfile.TemporaryDirectory() as t:
            c = cfg(t, MAX_CATCHUP_MIN="60"); window.save_checkpoint(c.state_dir + "/checkpoint", d(1, 0))
            main.run_once(c, d(18, 10), FakeClient(), FakeUp())
            st = __import__("json").load(open(c.state_dir + "/status.json"))
            self.assertIn("antigo", st["last_gap"]["why"]); self.assertTrue(st["last_gap"]["ts"])


class TestSpoolAndStatus(unittest.TestCase):
    def test_poison_head_file_does_not_block_later_files(self):
        with tempfile.TemporaryDirectory() as t:
            c = cfg(t)
            for n in ("levels_0_a_3_a.csv", "levels_0_a_3_b.csv", "levels_0_a_3_c.csv"): spool.write_atomic(c.spool_dir, n, "x\n")
            up = FakeUp(poison=("levels_0_a_3_a.csv",)); r = main.run_once(c, d(18, 5), FakeClient(), up)
            self.assertEqual(sorted(up.sent), ["levels_0_a_3_b.csv", "levels_0_a_3_c.csv"])
            self.assertEqual(spool.pending(c.spool_dir), ["levels_0_a_3_a.csv"]); self.assertIn("levels_0_a_3_a.csv", r["error"])

    def test_bucket_down_costs_at_most_two_attempts_per_tick(self):
        with tempfile.TemporaryDirectory() as t:
            c = cfg(t)
            for i in range(10): spool.write_atomic(c.spool_dir, f"levels_0_a_3_{i}.csv", "x\n")
            up = FakeUp(fail=True); main.run_once(c, d(18, 5), FakeClient(), up)
            self.assertLessEqual(up.calls, 2); self.assertEqual(len(spool.pending(c.spool_dir)), 10)

    def test_orphan_tmp_older_than_an_hour_is_removed_recent_kept(self):
        with tempfile.TemporaryDirectory() as t:
            c = cfg(t); old, new = c.spool_dir + "/a.csv.tmp", c.spool_dir + "/b.csv.tmp"
            for p in (old, new):
                with open(p, "w") as f: f.write("x")
            os.utime(old, (1, 1)); spool.cleanup_tmp(c.spool_dir, 3600)
            self.assertFalse(os.path.exists(old)); self.assertTrue(os.path.exists(new))

    def test_last_ok_is_kept_when_a_later_tick_fails(self):
        import json
        with tempfile.TemporaryDirectory() as t:
            c = cfg(t); window.save_checkpoint(c.state_dir + "/checkpoint", d(18, 0))
            main.run_once(c, d(18, 3, 10), FakeClient(), FakeUp())
            ok1 = json.load(open(c.state_dir + "/status.json"))["last_ok"]
            main.run_once(c, d(18, 4, 10), FakeClient(fail=True), FakeUp())
            st = json.load(open(c.state_dir + "/status.json"))
            self.assertEqual(st["last_ok"], ok1); self.assertTrue(st["last_error"])

    def test_ledger_rotates_when_too_big(self):
        from glexport import ledger
        with tempfile.TemporaryDirectory() as t:
            for i in range(60): ledger.append(t, {"i": i, "pad": "x" * 100}, max_bytes=2000, keep=3)
            names = sorted(os.listdir(t)); self.assertIn("ledger.jsonl", names); self.assertIn("ledger.jsonl.1", names)
            self.assertLessEqual(len([n for n in names if n.startswith("ledger.jsonl")]), 4)
            self.assertLessEqual(os.path.getsize(t + "/ledger.jsonl"), 2200)


if __name__ == "__main__":
    unittest.main()
