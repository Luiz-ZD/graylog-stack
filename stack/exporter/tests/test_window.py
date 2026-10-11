import os, tempfile, unittest
from datetime import datetime, timedelta, timezone
from glexport import window

U = timezone.utc
def d(h, m, s=0): return datetime(2026, 10, 11, h, m, s, tzinfo=U)


class TestWindow(unittest.TestCase):
    def test_closed_windows_respect_lag(self):
        ws = list(window.closed_windows(d(18, 0), d(18, 3, 30), lag_min=1))
        self.assertEqual(ws, [(d(18, 0), d(18, 1)), (d(18, 1), d(18, 2))])

    def test_boundary_belongs_to_one_window(self):
        ws = list(window.closed_windows(d(18, 0), d(18, 5), lag_min=1))
        starts = [a for a, _ in ws]; ends = [b for _, b in ws]
        self.assertEqual(ends[:-1], starts[1:])

    def test_filename_uses_local_tz_of_window_end(self):
        self.assertEqual(window.filename(d(18, 1), "America/Sao_Paulo"), "levels_0_a_3_20261011_150100.csv")

    def test_lucene_ts_format(self):
        self.assertEqual(window.lucene_ts(d(18, 1)), "2026-10-11 18:01:00.000")

    def test_checkpoint_missing_starts_now(self):
        with tempfile.TemporaryDirectory() as t:
            start, why = window.load_checkpoint(os.path.join(t, "cp"), d(18, 10, 20), 1, 720)
            self.assertEqual(start, d(18, 9)); self.assertIn("sem checkpoint", why)

    def test_checkpoint_corrupt_or_empty_starts_now(self):
        with tempfile.TemporaryDirectory() as t:
            for content in ["", "lixo", "9999-99-99"]:
                p = os.path.join(t, "cp"); open(p, "w").write(content)
                start, why = window.load_checkpoint(p, d(18, 10, 20), 1, 720)
                self.assertEqual(start, d(18, 9)); self.assertTrue(why)

    def test_checkpoint_too_old_is_clamped(self):
        with tempfile.TemporaryDirectory() as t:
            p = os.path.join(t, "cp"); window.save_checkpoint(p, d(1, 0))
            start, why = window.load_checkpoint(p, d(18, 10), 1, 120)
            self.assertEqual(start, d(18, 9) - timedelta(minutes=120)); self.assertIn("antigo", why)

    def test_checkpoint_in_the_future_is_reset(self):
        with tempfile.TemporaryDirectory() as t:
            p = os.path.join(t, "cp"); window.save_checkpoint(p, d(23, 0))
            start, why = window.load_checkpoint(p, d(18, 10), 1, 720)
            self.assertEqual(start, d(18, 9)); self.assertIn("futuro", why)

    def test_checkpoint_roundtrip(self):
        with tempfile.TemporaryDirectory() as t:
            p = os.path.join(t, "cp"); window.save_checkpoint(p, d(17, 59))
            self.assertEqual(window.load_checkpoint(p, d(18, 10), 1, 720), (d(17, 59), None))


if __name__ == "__main__":
    unittest.main()
