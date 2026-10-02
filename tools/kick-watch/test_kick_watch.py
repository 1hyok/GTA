"""기록기 회귀 검사. 게임 입력이나 실제 화면 캡처를 하지 않는다."""
import importlib.machinery
import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch


source = pathlib.Path(__file__).with_name("kick-watch.pyw")
loader = importlib.machinery.SourceFileLoader("kick_watch", str(source))
spec = importlib.util.spec_from_loader(loader.name, loader)
watch = importlib.util.module_from_spec(spec)
loader.exec_module(watch)


class LogTests(unittest.TestCase):
    def test_unavailable_log_recovers_without_crashing(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "later.log"
            tail = watch.LogTail(path)
            self.assertEqual(tail.read(), [])
            path.write_text("new input\n")
            self.assertEqual(tail.read(), ["new input"])
            with patch("builtins.open", side_effect=PermissionError("shared lock")):
                self.assertEqual(tail.read(), [])
                self.assertIn("PermissionError", tail.error)
            self.assertEqual(tail.read(), [])
            self.assertIsNone(tail.error)

    def test_existing_partial_and_rotated_logs(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "afk.log"
            path.write_bytes(b"old pulse\n")
            tail = watch.LogTail(path)
            self.assertEqual(tail.read(), [])
            encoded = "한글 mouse pulse\n".encode()
            with path.open("ab") as f:
                f.write(encoded[:2])
            self.assertEqual(tail.read(), [])
            with path.open("ab") as f:
                f.write(encoded[2:])
            self.assertEqual(tail.read(), ["한글 mouse pulse"])
            self.assertEqual(tail.read(), [])
            path.write_bytes(b"on\n")
            self.assertEqual(tail.read(), ["on"])
            replacement = pathlib.Path(folder) / "new.log"
            replacement.write_bytes(b"replacement is larger than previous log\n")
            replacement.replace(path)
            self.assertEqual(tail.read(), ["replacement is larger than previous log"])

    def test_structured_records_are_json(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(watch, "OUT", folder):
            watch.record("test", state={"os_idle_s": 5})
            row = json.loads((pathlib.Path(folder) / "observations.jsonl").read_text(encoding="utf-8"))
            self.assertEqual(row["event"], "test")
            self.assertEqual(row["state"]["os_idle_s"], 5)

    def test_snapshot_retention_is_separate(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            session = root / "shots"
            session.mkdir()
            incident = session / "existing.png"
            incident.write_bytes(b"incident")
            afk = root / "afk-shots"
            afk.mkdir()
            for n in range(4):
                watch.save_png(b"frame", str(n), str(afk), 2)
            self.assertEqual(len(list(afk.glob("*.png"))), 2)
            self.assertEqual(incident.read_bytes(), b"incident")


class ObserverTests(unittest.TestCase):
    def test_capture_error_does_not_escape_to_session_watcher(self):
        from unittest.mock import Mock
        observer = Mock()
        observer.sample.side_effect = OSError("capture unavailable")
        with patch.object(watch, "append") as log:
            watch.observe_safely(observer, "sample")
            log.assert_called_once()
        watch.observe_safely(observer, "session_change")
        observer.session_change.assert_called_once()

    def test_background_does_not_capture_desktop(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(watch, "AFK_LOG", str(pathlib.Path(folder)/"none")):
            observer = watch.AFKObserver()
            with patch.object(watch, "capture_png") as capture:
                frame = observer.frame({"game_rect": None})
                self.assertIsNone(frame["png"])
                capture.assert_not_called()

    def test_input_event_keeps_context_and_delayed_frame(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "afk.log"
            path.write_text("old\n")
            state = {"game_rect": [0, 0, 1920, 1080], "monotonic": 100.0}
            records = []
            with patch.object(watch, "AFK_LOG", str(path)), \
                    patch.object(watch, "observation", side_effect=lambda: dict(state)), \
                    patch.object(watch, "capture_png", return_value=b"png"), \
                    patch.object(watch, "save_png", side_effect=lambda png, tag, *args: tag if png else ""), \
                    patch.object(watch, "record", side_effect=lambda event, **data: records.append((event, data))), \
                    patch.object(watch.time, "monotonic", return_value=100.0) as clock:
                observer = watch.AFKObserver()
                observer.sample()
                with path.open("a") as stream:
                    stream.write("12:00:01 mouse pulse (MCT) idle=400s\n")
                state["monotonic"] = 101.0
                clock.return_value = 101.0
                observer.sample()
                event = next(data for kind, data in records if kind == "afk_input_logged")
                self.assertEqual(event["before_age_s"], 1.0)
                self.assertEqual(event["before"]["state"]["monotonic"], 100.0)
                self.assertEqual(event["after"]["state"]["monotonic"], 101.0)
                self.assertFalse(any(kind == "afk_after_2s" for kind, _ in records))
                clock.return_value = state["monotonic"] = 103.0
                observer.sample()
                self.assertEqual(sum(kind == "afk_after_2s" for kind, _ in records), 1)
                observer.sample()
                self.assertEqual(sum(kind == "afk_after_2s" for kind, _ in records), 1)
                clock.return_value = state["monotonic"] = 120.0
                with path.open("a") as stream:
                    stream.write("12:00:20 tap w,s idle=500s\n")
                observer.sample()
                events = [data for kind, data in records if kind == "afk_input_logged"]
                self.assertIsNone(events[-1]["before"])


if __name__ == "__main__":
    unittest.main()
