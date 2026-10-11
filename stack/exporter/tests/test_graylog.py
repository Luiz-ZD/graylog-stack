import unittest
from datetime import datetime, timezone
from glexport import config, graylog

U = timezone.utc
CFG = config.load({"GRAYLOG_TOKEN": "t", "EXPORT_FILTER": "level:[0 TO 3]", "EXPORT_EXCLUDE_SOURCES": "A-1,B-2"})


class TestGraylog(unittest.TestCase):
    def test_query_has_exclusive_upper_bound_filter_and_exclusions(self):
        q = graylog.build_query(CFG, datetime(2026, 10, 11, 18, 0, tzinfo=U), datetime(2026, 10, 11, 18, 1, tzinfo=U))
        self.assertEqual(q, 'gl2_receive_timestamp:["2026-10-11 18:00:00.000" TO "2026-10-11 18:01:00.000"} AND (level:[0 TO 3])'
                            ' AND NOT (source:"A-1" OR source:"B-2")')

    def test_parse_csv_graylog_style_normalizes_and_sorts_desc(self):
        text = ('"timestamp","source","level","message"\r\n'
                '"2026-10-11T15:45:51.000-03:00","H1","3","a ""q"", b"\r\n'
                '"2026-10-11T15:46:10.000-03:00","H2","","linha1\nlinha2"\r\n')
        rows = graylog.parse_csv(text)
        self.assertEqual(rows, [("2026-10-11T18:46:10.000Z", "H2", "", "linha1\nlinha2"),
                                ("2026-10-11T18:45:51.000Z", "H1", "3", 'a "q", b')])

    def test_parse_csv_empty_result(self):
        self.assertEqual(graylog.parse_csv(""), [])
        self.assertEqual(graylog.parse_csv('"timestamp","source","level","message"\r\n'), [])

    def test_query_escapes_quotes_and_backslashes_in_source_names(self):
        c = config.load({"GRAYLOG_TOKEN": "t", "EXPORT_FILTER": "level:[0 TO 3]", "EXPORT_EXCLUDE_SOURCES": 'a"b,c\\d'})
        q = graylog.build_query(c, datetime(2026, 10, 11, 18, 0, tzinfo=U), datetime(2026, 10, 11, 18, 1, tzinfo=U))
        self.assertIn('source:"a\\"b"', q); self.assertIn('source:"c\\\\d"', q)

    def test_default_slack_covers_devices_with_wrong_clocks(self):
        self.assertGreaterEqual(CFG.slack_hours, 24 * 365)

    def test_parse_csv_bad_header_raises(self):
        with self.assertRaises(graylog.GraylogError):
            graylog.parse_csv('"a","b"\r\n"1","2"\r\n')


if __name__ == "__main__":
    unittest.main()
