"""Contract checks using synthetic ledger bytes, never live game files."""
import csv
from datetime import datetime, timezone
from html.parser import HTMLParser
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import ledger_report as report


BASE = 1792022400  # 2026-10-15 00:00:00 UTC, 09:00 in UTC+09:00.


def row(epoch=BASE, amount=50000, direction="income", source="Nightclub", transaction="safe_nightclub", evidence="confirmed"):
    stamp = datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    return f"{epoch}\t{stamp}\t{amount}\t{direction}\t{transaction}\t{source}\t{evidence}\n"


def ledger(*rows):
    header = "unix_epoch\tlocal_time\tcash_delta\tdirection\ttransaction\tsource\tevidence\n"
    return (header + "".join(rows)).encode("utf-8")


class ParseTests(unittest.TestCase):
    def test_producer_header_bom_crlf_and_non_ascii_fields(self):
        data = b"\xef\xbb\xbf" + ledger(row(source="보석 사무소", evidence='선택 "A" 확인')).replace(b"\n", b"\r\n")
        result = report.parse_ledger(data)
        self.assertEqual(result.rows[0].source, "보석 사무소")
        self.assertEqual(result.rows[0].evidence, '선택 "A" 확인')
        self.assertEqual(result.rows[0].unix_epoch, BASE)
        self.assertEqual(result.data_lines, 1)
        self.assertEqual(result.diagnostics, [])

    def test_rejects_missing_or_wrong_header(self):
        for data in (b"", b"unix_epoch\n", ledger().rstrip(b"\n"), ledger(row()).replace(b"source", b"source_name", 1)):
            with self.subTest(data=data):
                with self.assertRaises(ValueError):
                    report.parse_ledger(data)

    def test_invalid_rows_are_reported_and_never_repaired(self):
        cases = {
            "column_count": "too\tfew\n",
            "invalid_epoch": row().replace(str(BASE), "NaN", 1),
            "invalid_local_time": row().replace("2026-10-15", "2026-02-30"),
            "invalid_amount": row(amount=0),
            "invalid_direction": row(direction="refund"),
            "direction_mismatch": row(amount=-7500),
            "control_character": row(source="bad\x00source"),
        }
        for code, bad in cases.items():
            with self.subTest(code=code):
                result = report.parse_ledger(ledger(row(), bad, row(BASE + 60)))
                self.assertEqual(len(result.rows), 2)
                self.assertEqual([(d.line, d.code) for d in result.diagnostics], [(3, code)])

    def test_noninteger_and_unrepresentable_numeric_fields_are_excluded(self):
        for amount in ("1.5", "NaN", "1e5", "9" * 5000):
            with self.subTest(amount=amount[:20]):
                self.assertEqual(report.parse_ledger(ledger(row(amount=amount))).diagnostics[0].code, "invalid_amount")
        for epoch in ("-1", "1.5", "9" * 5000, "999999999999"):
            with self.subTest(epoch=epoch[:20]):
                bad = row().replace(str(BASE), epoch, 1)
                self.assertEqual(report.parse_ledger(ledger(bad)).diagnostics[0].code, "invalid_epoch")

    def test_both_partial_and_structurally_complete_unterminated_rows_are_excluded(self):
        for tail in (b"1792022400\t20", row().rstrip("\n").encode()):
            result = report.parse_ledger(ledger(row()) + tail)
            self.assertEqual(len(result.rows), 1)
            self.assertEqual(result.data_lines, 2)
            self.assertEqual(result.diagnostics[0].code, "incomplete_final_row")

    def test_invalid_utf8_does_not_hide_later_valid_rows(self):
        result = report.parse_ledger(ledger(row()) + b"\xff\n" + row(BASE + 1).encode())
        self.assertEqual(len(result.rows), 2)
        self.assertEqual(result.diagnostics[0].code, "invalid_utf8")

    def test_identical_rows_remain_in_totals_as_duplicate_candidates(self):
        result = report.build_report(report.parse_ledger(ledger(row(), row(), row(evidence="different evidence"))), "snapshot.tsv", "UTC")
        self.assertEqual(result["totals"], {"count": 3, "income": 150000, "expense": 0, "net": 150000})
        self.assertEqual(result["quality"]["duplicate_candidates"], 1)
        self.assertEqual(result["rows"][1]["duplicate_of"], 2)
        self.assertIsNone(result["rows"][2]["duplicate_of"])
        self.assertEqual(result["quality"]["duplicate_policy"], "keep")


class AggregateTests(unittest.TestCase):
    def test_documented_example_keeps_duplicate_and_excludes_two_bad_rows(self):
        parsed = report.parse_ledger(Path(__file__).with_name("example.tsv").read_bytes())
        result = report.build_report(parsed, "example.tsv", "UTC+09:00")
        self.assertEqual(result["totals"], {"count": 8, "income": 360000, "expense": 85000, "net": 275000})
        self.assertEqual(result["quality"]["excluded_rows"], 2)
        self.assertEqual(result["quality"]["duplicate_candidates"], 1)

    def test_source_period_and_cross_totals_match_hand_calculated_cash_movements(self):
        parsed = report.parse_ledger(ledger(
            row(BASE + 7200, -7500, "expense", "Warehouse"),
            row(BASE, 50000),
            row(BASE + 60, -10000, "expense", "Nightclub"),
            row(BASE + 7800, 30000, "income", "Bail Office"),
        ))
        result = report.build_report(parsed, "snapshot.tsv", "UTC+09:00")
        self.assertEqual(result["totals"], {"count": 4, "income": 80000, "expense": 17500, "net": 62500})
        self.assertEqual(result["by_source"], [
            {"source": "Bail Office", "count": 1, "income": 30000, "expense": 0, "net": 30000},
            {"source": "Nightclub", "count": 2, "income": 50000, "expense": 10000, "net": 40000},
            {"source": "Warehouse", "count": 1, "income": 0, "expense": 7500, "net": -7500},
        ])
        self.assertEqual([g["period"] for g in result["by_time"]], ["2026-10-15T09:00+09:00", "2026-10-15T11:00+09:00"])
        self.assertEqual([g["net"] for g in result["by_time"]], [40000, 22500])
        self.assertEqual(sum(g["net"] for g in result["by_time_source"]), 62500)
        self.assertEqual(result["coverage"]["longest_inter_record_gaps"][0]["seconds"], 7140)
        self.assertFalse(result["coverage"]["runtime_known"])
        self.assertIsNone(result["coverage"]["hourly_rate"])

    def test_offset_changes_date_bucket_without_reinterpreting_recorded_local_time(self):
        result = report.build_report(report.parse_ledger(ledger(row())), "x.tsv", "UTC-03:00", "day")
        self.assertEqual(result["by_time"][0]["period"], "2026-10-14")
        self.assertEqual(result["rows"][0]["local_time"], "2026-10-15 00:00:00")
        self.assertEqual(result["rows"][0]["display_time"], "2026-10-14T21:00:00-03:00")

    def test_filters_include_start_exclude_end_and_keep_quality_for_whole_input(self):
        parsed = report.parse_ledger(ledger(row(BASE - 1), row(), row(BASE + 3599), row(BASE + 3600), "bad\n"))
        result = report.build_report(parsed, "x.tsv", "UTC", start=BASE, end=BASE + 3600)
        self.assertEqual(result["totals"]["count"], 2)
        self.assertEqual(result["quality"]["outside_filter_rows"], 2)
        self.assertEqual(result["quality"]["excluded_rows"], 1)
        self.assertEqual(result["filter"], {"start_inclusive": "2026-10-15T00:00:00+00:00", "end_exclusive": "2026-10-15T01:00:00+00:00"})

    def test_no_records_and_no_matching_records_do_not_create_zero_buckets(self):
        for parsed in (report.parse_ledger(ledger()), report.parse_ledger(ledger(row(BASE - 1)))):
            result = report.build_report(parsed, "x.tsv", "UTC", start=BASE)
            self.assertEqual(result["by_time"], [])
            self.assertEqual(result["by_source"], [])
            self.assertEqual(result["coverage"]["longest_inter_record_gaps"], [])
            self.assertIsNone(result["coverage"]["first_selected_record"])
            self.assertIn("활동 또는 수익이 없었다는 뜻은 아닙니다", report.render_html(result))

    def test_repeated_dst_hour_is_two_distinct_buckets_when_zone_database_available(self):
        try:
            report.parse_timezone("America/New_York")
        except ValueError:
            self.skipTest("IANA timezone database unavailable; fixed offset tests still run")
        a = report.parse_boundary("2026-11-01T01:30:00-04:00")
        b = report.parse_boundary("2026-11-01T01:30:00-05:00")
        result = report.build_report(report.parse_ledger(ledger(row(a), row(b))), "x.tsv", "America/New_York")
        self.assertEqual([g["period"] for g in result["by_time"]], ["2026-11-01T01:00-04:00", "2026-11-01T01:00-05:00"])

    def test_filters_reject_ambiguous_fractional_or_inverted_intervals(self):
        for value in ("2026-10-15", "2026-10-15T09:00:00", "2026-10-15T09:00:00.5+09:00", "2026-10-15T09:00:00+09:00:00.5", "invalid"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                report.parse_boundary(value)
        self.assertEqual(report.parse_boundary("2026-10-15T09:00:00+09:00"), BASE)
        self.assertEqual(report.parse_boundary("2026-10-15T00:00:00Z"), BASE)
        with self.assertRaises(ValueError):
            report.build_report(report.parse_ledger(ledger()), "x", "UTC", start=BASE, end=BASE)
        for zone in ("UTC+24:00", "UTC+09:60", "Some/MissingZone"):
            with self.subTest(zone=zone), self.assertRaises(ValueError):
                report.parse_timezone(zone)


class ExportTests(unittest.TestCase):
    def test_html_escapes_every_untrusted_visible_field(self):
        payload = '<script>alert("x")</script>&'
        result = report.build_report(report.parse_ledger(ledger(row(source=payload, transaction=payload, evidence=payload))), payload, "UTC", label=payload)
        html = report.render_html(result)
        class Elements(HTMLParser):
            def __init__(self):
                super().__init__()
                self.tags = []
            def handle_starttag(self, tag, attrs):
                self.tags.append(tag)
        elements = Elements()
        elements.feed(html)
        self.assertNotIn("script", elements.tags)
        self.assertNotIn("img", elements.tags)
        self.assertIn("&lt;script&gt;", html)
        self.assertIn("Content-Security-Policy", html)

    def test_csv_formula_text_is_escaped_while_validated_numbers_stay_numeric(self):
        for source in ('=HYPERLINK("https://example.invalid")', " +SUM(1,1)", "-1+2", "@SUM(1,1)"):
            with self.subTest(source=source):
                result = report.build_report(report.parse_ledger(ledger(row(amount=-7500, direction="expense", source=source))), "x", "UTC")
                groups = list(csv.DictReader(io.StringIO(report.render_csv(result))))
                group = next(item for item in groups if item["record_type"] == "source")
                self.assertEqual(group["source"], "'" + source)
                self.assertEqual(group["net"], "-7500")
                self.assertTrue(any(item["record_type"] == "scope" and "수동 창고 판매" in item["note"] for item in groups))
        result = report.build_report(report.parse_ledger(ledger(row())), "=bad.tsv", "UTC", label="=unsafe label")
        groups = list(csv.DictReader(io.StringIO(report.render_csv(result))))
        self.assertEqual(next(item for item in groups if item["record_type"] == "label")["note"], "'=unsafe label")
        self.assertEqual(next(item for item in groups if item["record_type"] == "input_name")["note"], "'=bad.tsv")

    def test_csv_quotes_comma_and_double_quote_without_losing_text(self):
        name = 'Warehouse, "North"'
        result = report.build_report(report.parse_ledger(ledger(row(source=name))), "x", "UTC")
        groups = list(csv.DictReader(io.StringIO(report.render_csv(result))))
        self.assertEqual(next(item for item in groups if item["record_type"] == "source")["source"], name)

    def test_cli_creates_three_reports_preserves_input_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "ledger with spaces.tsv"
            output = root / "new reports"
            data = ledger(row(), row(BASE + 60, -10000, "expense"))
            source.write_bytes(data)
            command = [sys.executable, str(Path(report.__file__)), str(source), "--output", str(output), "--timezone", "UTC+09:00", "--label", "합성 표본"]
            completed = subprocess.run(command, text=True, capture_output=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(source.read_bytes(), data)
            self.assertEqual(set(p.name for p in output.iterdir()), {"report.html", "report.json", "summary.csv"})
            result = json.loads((output / "report.json").read_text(encoding="utf-8"))
            self.assertEqual(result["totals"]["net"], 40000)
            self.assertEqual(result["label"], "합성 표본")
            self.assertTrue((output / "summary.csv").read_bytes().startswith(b"\xef\xbb\xbf"))
            previous = {p.name: p.read_bytes() for p in output.iterdir()}
            again = subprocess.run(command, text=True, capture_output=True)
            self.assertEqual(again.returncode, 2)
            self.assertEqual(previous, {p.name: p.read_bytes() for p in output.iterdir()})
            self.assertEqual(source.read_bytes(), data)

    def test_cli_missing_input_or_bad_timezone_leaves_no_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "ledger.tsv"
            output = root / "report"
            base = [sys.executable, str(Path(report.__file__)), str(source), "--output", str(output)]
            missing = subprocess.run(base + ["--timezone", "UTC"], capture_output=True)
            self.assertEqual(missing.returncode, 2)
            self.assertFalse(output.exists())
            source.write_bytes(ledger(row()))
            bad_zone = subprocess.run(base + ["--timezone", "Some/MissingZone"], capture_output=True)
            self.assertEqual(bad_zone.returncode, 2)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
