import unittest
from glexport import csvout


class TestCsv(unittest.TestCase):
    def test_matches_real_bucket_lines(self):
        got = csvout.render([("2026-07-13T18:08:04.000Z", "host-01", "6",
            "host-01 systemd[1]: session-c10587.scope: Deactivated successfully.")])
        self.assertEqual(got, 'timestamp,source,level,message\n'
            '"2026-07-13T18:08:04.000Z","host-01",6,'
            '"host-01 systemd[1]: session-c10587.scope: Deactivated successfully."\n')

    def test_quotes_commas_newlines_cr_unicode(self):
        msg = 'a "b", c\r\nlinha2 ação 🚀'
        self.assertEqual(csvout.row("t", "s", "3", msg), '"t","s",3,"a ""b"", c\r\nlinha2 ação 🚀"')

    def test_empty_level_is_empty_field(self):
        self.assertEqual(csvout.row("t", "s", "", "m"), '"t","s",,"m"')

    def test_non_numeric_level_is_quoted(self):
        self.assertEqual(csvout.row("t", "s", "warning", "m"), '"t","s","warning","m"')

    def test_empty_window_renders_nothing(self):
        self.assertEqual(csvout.render([]), "")

    def test_utc_ts_converts_local_offset_to_zulu(self):
        self.assertEqual(csvout.utc_ts("2026-10-11T15:45:51.000-03:00"), "2026-10-11T18:45:51.000Z")

    def test_utc_ts_keeps_zulu_and_pads_millis(self):
        self.assertEqual(csvout.utc_ts("2026-09-20T00:33:47.000Z"), "2026-09-20T00:33:47.000Z")
        self.assertEqual(csvout.utc_ts("2026-09-20T00:33:47Z"), "2026-09-20T00:33:47.000Z")
        self.assertEqual(csvout.utc_ts("2026-09-20T00:33:47.5+00:00"), "2026-09-20T00:33:47.500Z")

    def test_utc_ts_garbage_is_returned_unchanged(self):
        self.assertEqual(csvout.utc_ts("nao-eh-data"), "nao-eh-data")


if __name__ == "__main__":
    unittest.main()
