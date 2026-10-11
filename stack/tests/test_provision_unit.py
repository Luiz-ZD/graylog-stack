import importlib.util, os, unittest
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("provision", os.path.join(HERE, "..", "provision", "provision.py"))
prov = importlib.util.module_from_spec(spec); spec.loader.exec_module(prov)


class TestPassword(unittest.TestCase):
    def test_password_comes_from_env_not_argv(self):
        self.assertEqual(prov.resolve_password(None, {"GRAYLOG_ADMIN_PASSWORD": "s3cr3t"}), "s3cr3t")

    def test_argv_still_works_but_env_wins_when_both(self):
        self.assertEqual(prov.resolve_password("x", {"GRAYLOG_ADMIN_PASSWORD": "y"}), "y")
        self.assertEqual(prov.resolve_password("x", {}), "x")

    def test_missing_password_exits(self):
        with self.assertRaises(SystemExit): prov.resolve_password(None, {})


if __name__ == "__main__":
    unittest.main()
