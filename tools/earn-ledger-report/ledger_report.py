#!/usr/bin/env python3
"""Read one EarnLedger TSV snapshot and write an offline cash-flow report."""
from __future__ import annotations

import argparse
import csv
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone, tzinfo
import hashlib
from html import escape
import io
import json
from pathlib import Path
import re
import sys
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


HEADER = (
    "unix_epoch", "local_time", "cash_delta", "direction", "transaction", "source", "evidence"
)
LIMITATIONS = [
    "자동화가 확인하고 이 파일에 기록한 현금 이동만 집계합니다. 수동 창고 판매와 전체 지갑 잔액은 포함하지 않습니다.",
    "지출 뒤 쌓인 재고 자산을 평가하지 않습니다. 현금 순액을 사업 이익이나 손실로 해석하지 않습니다.",
    "기록 사이 공백은 수익 0 또는 자동화 실행·중단의 증거가 아닙니다. 기록이 없는 시간 구간은 표에 만들지 않습니다.",
    "첫·마지막 거래 시각은 가동 시작·종료 시각이 아닙니다. 가동시간과 시간당 수익률을 계산하지 않습니다.",
    "거래 ID가 없으므로 동일한 7열 행도 별개의 실제 거래일 수 있습니다. 중복 후보를 표시하되 합계에는 유지합니다.",
    "시간 필터와 그룹은 unix_epoch를 사용합니다. 원장의 local_time에는 시간대가 없어 표시 시간대로 재해석하지 않습니다.",
]


@dataclass(frozen=True)
class Row:
    line: int
    unix_epoch: int
    local_time: str
    cash_delta: int
    direction: str
    transaction: str
    source: str
    evidence: str
    duplicate_of: int | None = None


@dataclass(frozen=True)
class Diagnostic:
    line: int
    code: str
    message: str


@dataclass
class Ledger:
    rows: list[Row]
    diagnostics: list[Diagnostic]
    sha256: str
    size_bytes: int
    data_lines: int


def parse_ledger(data: bytes) -> Ledger:
    """Ignore invalid/incomplete rows without inventing a repaired transaction."""
    physical_lines = data.split(b"\n")
    if len(physical_lines) < 2:
        raise ValueError("TSV 헤더와 줄바꿈이 필요합니다.")
    try:
        header = physical_lines[0].removesuffix(b"\r").decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ValueError("TSV 헤더가 UTF-8이 아닙니다.") from exc
    if header.split("\t") != list(HEADER):
        raise ValueError("EarnLedger의 7열 TSV 헤더와 일치하지 않습니다.")

    rows: list[Row] = []
    diagnostics: list[Diagnostic] = []
    seen: dict[tuple[str, ...], int] = {}
    data_lines = 0
    for index, raw in enumerate(physical_lines[1:], start=2):
        terminated = index <= len(physical_lines) - 1
        if not raw and not terminated:
            continue
        data_lines += 1
        if not terminated:
            diagnostics.append(Diagnostic(index, "incomplete_final_row", "마지막 줄에 줄바꿈이 없어 집계에서 제외했습니다."))
            continue
        try:
            fields = raw.removesuffix(b"\r").decode("utf-8").split("\t")
        except UnicodeDecodeError:
            diagnostics.append(Diagnostic(index, "invalid_utf8", "UTF-8로 읽을 수 없어 집계에서 제외했습니다."))
            continue
        try:
            if len(fields) != len(HEADER):
                raise ValueError("column_count|7열 TSV가 아닙니다.")
            if any(any(ord(char) < 32 or ord(char) == 127 for char in field) for field in fields):
                raise ValueError("control_character|필드에 제어 문자가 있습니다.")
            if not re.fullmatch(r"[0-9]+", fields[0]):
                raise ValueError("invalid_epoch|unix_epoch가 0 이상의 정수가 아닙니다.")
            try:
                epoch = int(fields[0])
                datetime.fromtimestamp(epoch, timezone.utc)
            except (ValueError, OverflowError, OSError):
                raise ValueError("invalid_epoch|unix_epoch가 지원하는 날짜 범위를 벗어납니다.") from None
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}", fields[1]):
                raise ValueError("invalid_local_time|local_time 형식이 올바르지 않습니다.")
            try:
                datetime.strptime(fields[1], "%Y-%m-%d %H:%M:%S")
            except ValueError:
                raise ValueError("invalid_local_time|local_time 날짜가 유효하지 않습니다.") from None
            if not re.fullmatch(r"-?[0-9]+", fields[2]):
                raise ValueError("invalid_amount|cash_delta가 정수가 아닙니다.")
            try:
                delta = int(fields[2])
            except ValueError:
                raise ValueError("invalid_amount|cash_delta가 지원하는 정수 범위를 벗어납니다.") from None
            if delta == 0:
                raise ValueError("invalid_amount|0원 거래는 원장 계약에 맞지 않습니다.")
            if fields[3] not in ("income", "expense"):
                raise ValueError("invalid_direction|direction은 income 또는 expense여야 합니다.")
            if (delta > 0) != (fields[3] == "income"):
                raise ValueError("direction_mismatch|금액 부호와 direction이 다릅니다.")
        except ValueError as exc:
            code, message = str(exc).split("|", 1)
            diagnostics.append(Diagnostic(index, code, message + " 집계에서 제외했습니다."))
            continue

        identity = tuple(fields)
        duplicate_of = seen.get(identity)
        if duplicate_of is None:
            seen[identity] = index
        else:
            diagnostics.append(Diagnostic(index, "duplicate_candidate", f"{duplicate_of}행과 7열이 같습니다. 거래 ID가 없어 합계에 유지했습니다."))
        rows.append(Row(index, epoch, fields[1], delta, fields[3], fields[4], fields[5], fields[6], duplicate_of))
    return Ledger(rows, diagnostics, hashlib.sha256(data).hexdigest(), len(data), data_lines)


def parse_timezone(value: str) -> tzinfo:
    """Fixed offsets work on Windows without installing an IANA timezone database."""
    if value == "UTC":
        return timezone.utc
    match = re.fullmatch(r"UTC([+-])(\d{2}):(\d{2})", value)
    if match:
        hours, minutes = int(match[2]), int(match[3])
        if hours > 23 or minutes > 59:
            raise ValueError("UTC 오프셋은 24시간 미만이며 분은 00~59여야 합니다.")
        offset = timedelta(hours=hours, minutes=minutes)
        return timezone(offset if match[1] == "+" else -offset, value)
    try:
        return ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError) as exc:
        raise ValueError(f"시간대 {value!r}를 읽을 수 없습니다. UTC 또는 UTC+09:00 같은 고정 오프셋을 사용하세요.") from exc


def parse_boundary(value: str) -> int:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError("필터 시각은 2026-10-15T00:00:00+09:00 같은 ISO 8601 형식이어야 합니다.") from exc
    if parsed.tzinfo is None or parsed.utcoffset() is None or parsed.microsecond:
        raise ValueError("필터 시각에 UTC 오프셋을 지정하고 초 단위 정수를 사용하세요.")
    timestamp = parsed.timestamp()
    if not timestamp.is_integer():
        raise ValueError("필터 시각의 UTC 오프셋도 초 단위 정수여야 합니다.")
    return int(timestamp)


def displayed(epoch: int, zone: tzinfo) -> str:
    return datetime.fromtimestamp(epoch, zone).isoformat(timespec="seconds")


def totals(rows: list[Row]) -> dict[str, int]:
    income = sum(row.cash_delta for row in rows if row.cash_delta > 0)
    expense = -sum(row.cash_delta for row in rows if row.cash_delta < 0)
    return {"count": len(rows), "income": income, "expense": expense, "net": income - expense}


def build_report(ledger: Ledger, input_name: str, zone_name: str, bucket: str = "hour",
                 start: int | None = None, end: int | None = None, label: str = "") -> dict:
    if bucket not in ("hour", "day"):
        raise ValueError("bucket은 hour 또는 day여야 합니다.")
    if start is not None and end is not None and start >= end:
        raise ValueError("시작 시각은 종료 시각보다 빨라야 합니다.")
    zone = parse_timezone(zone_name)
    selected = sorted((row for row in ledger.rows
                       if (start is None or row.unix_epoch >= start)
                       and (end is None or row.unix_epoch < end)), key=lambda row: (row.unix_epoch, row.line))
    by_source: dict[str, list[Row]] = {}
    by_time: dict[str, list[Row]] = {}
    by_time_source: dict[tuple[str, str], list[Row]] = {}
    for row in selected:
        by_source.setdefault(row.source, []).append(row)
        date = datetime.fromtimestamp(row.unix_epoch, zone)
        # An offset keeps the repeated hour of a DST fall-back distinguishable.
        time_key = (date.replace(minute=0, second=0, microsecond=0).isoformat(timespec="minutes")
                    if bucket == "hour" else date.date().isoformat())
        by_time.setdefault(time_key, []).append(row)
        by_time_source.setdefault((time_key, row.source), []).append(row)
    first = displayed(selected[0].unix_epoch, zone) if selected else None
    last = displayed(selected[-1].unix_epoch, zone) if selected else None
    gaps = [{"from": displayed(before.unix_epoch, zone), "to": displayed(after.unix_epoch, zone),
             "seconds": after.unix_epoch - before.unix_epoch}
            for before, after in zip(selected, selected[1:]) if after.unix_epoch > before.unix_epoch]
    gaps.sort(key=lambda gap: gap["seconds"], reverse=True)
    return {
        "schema_version": 1,
        "title": "GTA 확정 자동화 현금흐름",
        "label": label,
        "input": {"name": input_name, "sha256": ledger.sha256, "size_bytes": ledger.size_bytes},
        "timezone": zone_name,
        "bucket": bucket,
        "filter": {"start_inclusive": displayed(start, zone) if start is not None else None,
                   "end_exclusive": displayed(end, zone) if end is not None else None},
        "coverage": {"first_selected_record": first, "last_selected_record": last,
                     "runtime_known": False, "hourly_rate": None,
                     "longest_inter_record_gaps": gaps[:5]},
        "quality": {"data_lines": ledger.data_lines, "valid_rows": len(ledger.rows),
                    "selected_rows": len(selected), "outside_filter_rows": len(ledger.rows) - len(selected),
                    "excluded_rows": sum(item.code != "duplicate_candidate" for item in ledger.diagnostics),
                    "duplicate_candidates": sum(row.duplicate_of is not None for row in ledger.rows),
                    "selected_duplicate_candidates": sum(row.duplicate_of is not None for row in selected),
                    "duplicate_policy": "keep"},
        "totals": totals(selected),
        "by_source": [{"source": source, **totals(rows)} for source, rows in sorted(by_source.items())],
        "by_time": [{"period": period, **totals(rows)} for period, rows in by_time.items()],
        "by_time_source": [{"period": period, "source": source, **totals(rows)}
                           for (period, source), rows in by_time_source.items()],
        "rows": [{**asdict(row), "display_time": displayed(row.unix_epoch, zone)} for row in selected],
        "diagnostics": [asdict(item) for item in ledger.diagnostics],
        "limitations": LIMITATIONS,
    }


def csv_cell(value: object) -> object:
    # Numeric cells come from validated integers. Untrusted text stays text in Excel.
    if isinstance(value, str) and value.lstrip().startswith(("=", "+", "-", "@")):
        return "'" + value
    return value


def render_csv(report: dict) -> str:
    output = io.StringIO(newline="")
    writer = csv.writer(output)
    writer.writerow(["record_type", "timezone", "period", "source", "count", "income", "expense", "net", "note"])
    def write(values: list[object]) -> None:
        writer.writerow([csv_cell(value) for value in values])
    write(["scope", report["timezone"], "", "", "", "", "", "", " | ".join(report["limitations"])])
    write(["label", report["timezone"], "", "", "", "", "", "", report["label"]])
    write(["input_name", report["timezone"], "", "", "", "", "", "", report["input"]["name"]])
    write(["quality", report["timezone"], "", "", "", "", "", "", json.dumps(report["quality"], ensure_ascii=False)])
    write(["filter", report["timezone"], "", "", "", "", "", "", json.dumps(report["filter"], ensure_ascii=False)])
    write(["input_sha256", report["timezone"], "", "", "", "", "", "", report["input"]["sha256"]])
    for kind, groups in (("total", [report["totals"]]), ("source", report["by_source"]),
                         ("period", report["by_time"]), ("period_source", report["by_time_source"])):
        for group in groups:
            write([kind, report["timezone"], group.get("period", ""), group.get("source", ""),
                   group["count"], group["income"], group["expense"], group["net"], ""])
    return output.getvalue()


def money(value: int) -> str:
    return ("-" if value < 0 else "") + "$" + f"{abs(value):,}"


def render_html(report: dict) -> str:
    def text(value: object) -> str:
        return escape(str(value), quote=True)
    def table(headers: list[str], rows: list[list[object]]) -> str:
        if not rows:
            return '<p class="empty">조건에 맞는 기록이 없습니다. 활동 또는 수익이 없었다는 뜻은 아닙니다.</p>'
        head = "".join(f'<th scope="col">{text(header)}</th>' for header in headers)
        body = "".join("<tr>" + "".join(f"<td>{text(cell)}</td>" for cell in row) + "</tr>" for row in rows)
        return f'<div class="table-wrap"><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>'
    def group_table(groups: list[dict], key: str, heading: str) -> str:
        return table([heading, "거래 수", "수입", "지출", "순액"],
                     [[group[key] or "(미기록)", group["count"], money(group["income"]),
                       money(group["expense"]), money(group["net"])] for group in groups])
    quality = report["quality"]
    summary = report["totals"]
    coverage = report["coverage"]
    filters = report["filter"]
    label = f'<p class="label">{text(report["label"])}</p>' if report["label"] else ""
    limits = "".join(f"<li>{text(item)}</li>" for item in report["limitations"])
    cards = "".join(f'<div class="card"><span>{name}</span><strong>{text(value)}</strong></div>' for name, value in (
        ("확정 수입", money(summary["income"])), ("확정 지출", money(summary["expense"])),
        ("기록 순액", money(summary["net"])), ("선택 거래", f'{summary["count"]}건')))
    diagnostics = table(["입력 행", "분류", "처리"],
                        [[item["line"], item["code"], item["message"]] for item in report["diagnostics"]]) if report["diagnostics"] else '<p>행 형식 오류와 동일 행 후보가 없습니다. 기록의 완전성을 보장하지는 않습니다.</p>'
    gaps = table(["앞 기록", "다음 기록", "기록 간격(초)"],
                 [[gap["from"], gap["to"], gap["seconds"]] for gap in coverage["longest_inter_record_gaps"]])
    entries = table(["행", "표시 시각", "원장 local_time", "출처", "거래", "금액", "확인 근거", "동일 행 후보"],
                    [[row["line"], row["display_time"], row["local_time"], row["source"], row["transaction"],
                      money(row["cash_delta"]), row["evidence"], row["duplicate_of"] or ""] for row in report["rows"]])
    return f'''<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<title>{text(report["title"])}</title><style>
:root{{font-family:system-ui,-apple-system,sans-serif;color:#182936;background:#f3f6f8;line-height:1.65}}
body{{margin:0}}main{{max-width:1200px;margin:auto;padding:36px 24px 60px}}h1{{font-size:30px;margin:0 0 6px;line-height:1.3}}
h2{{font-size:21px;margin:0 0 14px}}p{{margin:6px 0 12px}}.eyebrow{{color:#426574;font-size:13px;letter-spacing:.08em}}
.label{{display:inline-block;background:#e6edf5;padding:4px 12px;border-radius:5px;font-weight:650}}.muted{{color:#536572}}
.cards{{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:24px 0}}.card,section{{background:white;border:1px solid #d8e2e9;border-radius:12px;padding:20px}}
.card span{{display:block;font-size:14px;color:#536572}}.card strong{{display:block;font-size:28px;margin-top:8px;font-variant-numeric:tabular-nums}}
section{{margin:20px 0}}.notice{{border-left:5px solid #bb7d18;background:#fff9ed}}ul{{padding-left:21px;margin:8px 0}}
.table-wrap{{overflow:auto}}table{{width:100%;border-collapse:collapse;font-size:14px}}th,td{{text-align:left;padding:11px 12px;border-bottom:1px solid #e4ebf0;vertical-align:top;overflow-wrap:anywhere}}
th{{background:#edf3f6;white-space:nowrap}}td{{font-variant-numeric:tabular-nums}}details>summary{{cursor:pointer;font-weight:650}}
code{{overflow-wrap:anywhere;font-size:12px}}.empty{{color:#536572}}footer{{font-size:12px;color:#536572}}
@media(max-width:700px){{main{{padding:24px 14px}}.cards{{grid-template-columns:repeat(2,1fr)}}.card strong{{font-size:24px}}h1{{font-size:25px}}}}
@media print{{body{{background:white}}main{{padding:0}}section,.card{{break-inside:avoid}}details{{display:block}}}}
</style></head><body><main>
<p class="eyebrow">GTA / OFFLINE LEDGER REPORT</p><h1>{text(report["title"])}</h1>{label}
<p class="muted">{text(report["input"]["name"])} · 표시 시간대 {text(report["timezone"])} · {"시간별" if report["bucket"] == "hour" else "날짜별"} 거래 합계</p>
<div class="cards">{cards}</div>
<section class="notice"><h2>이 숫자가 뜻하는 범위</h2><ul>{limits}</ul></section>
<section><h2>기록과 품질</h2><p>선택 기록: {text(coverage["first_selected_record"] or "없음")} ~ {text(coverage["last_selected_record"] or "없음")}</p>
<p>필터: 시작 포함 {text(filters["start_inclusive"] or "제한 없음")} / 종료 제외 {text(filters["end_exclusive"] or "제한 없음")}</p>
<p>입력 {quality["data_lines"]}행 · 유효 {quality["valid_rows"]}행 · 필터 밖 {quality["outside_filter_rows"]}행 · 제외 {quality["excluded_rows"]}행 · 동일 행 후보 {quality["duplicate_candidates"]}건 (선택 구간 {quality["selected_duplicate_candidates"]}건, 합계 유지)</p>
<details><summary>행별 처리 내역</summary>{diagnostics}</details></section>
<section><h2>출처별 현금흐름</h2>{group_table(report["by_source"], "source", "출처")}</section>
<section><h2>{"시간별" if report["bucket"] == "hour" else "날짜별"} 현금흐름</h2><p class="muted">해당 구간에 기록된 거래의 합계입니다. 시간당 수익률이 아닙니다.</p>{group_table(report["by_time"], "period", "기록 구간")}</section>
<section><h2>가장 긴 기록 사이 간격</h2><p class="muted">상위 5개입니다. 중단 시간이나 수익이 없던 시간으로 해석하지 않습니다.</p>{gaps}</section>
<section><h2>선택된 거래 원문</h2><details><summary>{summary["count"]}건 펼치기</summary>{entries}</details></section>
<footer>입력 스냅샷 SHA-256: <code>{text(report["input"]["sha256"])}</code><br>입력 {report["input"]["size_bytes"]:,} bytes · 보고서 스키마 {report["schema_version"]} · 외부 요청과 게임 입력 없음</footer>
</main></body></html>'''


def write_reports(report: dict, output: Path, input_path: Path) -> None:
    names = ("report.html", "report.json", "summary.csv")
    if output.exists():
        raise ValueError("출력 디렉터리가 이미 있습니다. 입력과 이전 보고서를 보존하도록 새 경로를 지정하세요.")
    if output.resolve() == input_path.resolve() or output.resolve() in input_path.resolve().parents:
        raise ValueError("출력 경로가 입력 파일 또는 입력의 상위 디렉터리입니다.")
    contents = (render_html(report), json.dumps(report, ensure_ascii=False, indent=2) + "\n", render_csv(report))
    output.mkdir(parents=True, exist_ok=False)
    for name, content in zip(names, contents):
        with (output / name).open("x", encoding="utf-8-sig" if name.endswith(".csv") else "utf-8", newline="") as stream:
            stream.write(content)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="명시한 GTA 원장 사본을 읽어 현금흐름 HTML/JSON/CSV 보고서를 만듭니다.")
    parser.add_argument("input", type=Path, help="EarnLedger 7열 TSV 입력 파일")
    parser.add_argument("--output", type=Path, required=True, help="아직 존재하지 않는 결과 디렉터리")
    parser.add_argument("--timezone", required=True, help="표시 시간대: UTC, UTC+09:00 또는 IANA 이름")
    parser.add_argument("--bucket", choices=("hour", "day"), default="hour")
    parser.add_argument("--start", help="시작 포함, UTC 오프셋을 명시한 ISO 8601 시각")
    parser.add_argument("--end", help="종료 제외, UTC 오프셋을 명시한 ISO 8601 시각")
    parser.add_argument("--label", default="", help="보고서에 표시할 표본·자료 설명")
    args = parser.parse_args(argv)
    try:
        start = parse_boundary(args.start) if args.start else None
        end = parse_boundary(args.end) if args.end else None
        report = build_report(parse_ledger(args.input.read_bytes()), args.input.name, args.timezone,
                              args.bucket, start, end, args.label)
        write_reports(report, args.output, args.input)
    except (OSError, ValueError, OverflowError) as exc:
        parser.exit(2, f"오류: {exc}\n")
    print(json.dumps({"output": str(args.output.resolve()), "totals": report["totals"],
                      "quality": report["quality"]}, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
