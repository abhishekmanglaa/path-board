import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
import plistlib
from tempfile import TemporaryDirectory
from unittest.mock import patch

import iphone_install


class ProvisioningTests(unittest.TestCase):
    def test_renewal_has_two_days_of_margin_including_expired_profiles(self):
        now = datetime(2026, 11, 3, tzinfo=timezone.utc)
        self.assertFalse(iphone_install.needs_renewal(now + timedelta(days=3), now))
        self.assertTrue(iphone_install.needs_renewal(now + timedelta(days=2), now))
        self.assertTrue(iphone_install.needs_renewal(now - timedelta(seconds=1), now))

    def test_widget_expiry_can_be_earlier_than_app_expiry(self):
        with TemporaryDirectory() as directory:
            app = Path(directory) / "App.app"
            (app / "PlugIns/Widget.appex").mkdir(parents=True)
            expiries = [datetime(2026, 11, 10), datetime(2026, 11, 9)]
            with patch("iphone_install.subprocess.check_output", side_effect=[
                plistlib.dumps({"ExpirationDate": date}) for date in expiries
            ]):
                self.assertEqual(iphone_install.profile_expiry(app),
                                 expiries[1].replace(tzinfo=timezone.utc))

    def test_missing_widget_is_not_reported_as_a_complete_build(self):
        with TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                iphone_install.profile_expiry(Path(directory))


if __name__ == "__main__":
    unittest.main()
